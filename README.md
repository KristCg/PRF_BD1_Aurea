# Cafetería Áurea · Base de datos

Proyecto No. 2 · CC3088 Base de Datos 1 · Semestre II 2026

Sistema de gestión para una cadena de cafeterías con tres sedes: reservas de mesas,
control de inventario por lotes con caducidad, historial de clientes y bitácora de
cambios. PostgreSQL.

---

## Carga de la base desde cero

La base se construye con seis scripts de SQL plano que se corren en orden. No hay
respaldos binarios ni `pg_restore`: cualquiera con PostgreSQL puede reproducir la
base completa en menos de diez segundos, en Windows, Linux o Mac.

### Con psql

```bash
createdb PRF_Aurea
psql -d PRF_Aurea -v ON_ERROR_STOP=1 -f 01_schema.sql
psql -d PRF_Aurea -v ON_ERROR_STOP=1 -f 02_funciones.sql
psql -d PRF_Aurea -v ON_ERROR_STOP=1 -f 03_vistas.sql
psql -d PRF_Aurea -v ON_ERROR_STOP=1 -f 04_indices.sql
psql -d PRF_Aurea -v ON_ERROR_STOP=1 -f 05_seed_catalogo.sql
psql -d PRF_Aurea -v ON_ERROR_STOP=1 -f 06_seed_demo.sql
```

### Con pgAdmin 4

1. Clic derecho en **Databases → Create → Database**, nombre `PRF_Aurea`.
2. Clic derecho sobre la base → **Query Tool**.
3. Abrir cada archivo con el botón de carpeta y ejecutarlo con **F5**, en orden del
   01 al 06. Esperar a que cada uno termine antes de abrir el siguiente.

El script 06 imprime al final un resumen de filas y dos verificaciones de integridad
que deben dar cero.

### Qué hace cada script

| Archivo | Contenido |
|---|---|
| `01_schema.sql` | 20 tablas con llaves, restricciones de integridad y CHECK |
| `02_funciones.sql` | 17 funciones y 17 triggers: 12 de bitácora y 5 de lógica de negocio |
| `03_vistas.sql` | 6 vistas de apoyo y los 5 reportes del enunciado, con CTEs |
| `04_indices.sql` | 30 índices además de los de llave primaria, dos de ellos parciales |
| `05_seed_catalogo.sql` | 3 sedes, 10 empleados, 8 usuarios, 42 mesas, 31 insumos, 21 platillos, 103 líneas de receta |
| `06_seed_demo.sql` | 25 clientes, ~850 reservas, ~440 órdenes facturadas, ~97 lotes y ~5600 movimientos |

**Todas las fechas del seed son relativas a `CURRENT_DATE`.** No hay una sola fecha
fija. El día que se corra, las reservas seguirán repartidas entre pasado y futuro,
y los lotes seguirán cayendo dentro de las ventanas de caducidad. Esto es lo que
hace que las alertas se vean vivas en cualquier momento.

### Usuarios de prueba

| Usuario | Rol | Clave |
|---|---|---|
| `kristel.admin` | Administrador | la original del equipo |
| `maya.gerente` | Gerente | `aurea2026` |
| `diego.mesero` | Mesero | `aurea2026` |
| `carlos.inv` | Encargado de Inventario | `aurea2026` |

Hay además un gerente y un encargado de inventario por cada una de las otras dos
sedes. Las contraseñas se guardan con `bcrypt` a través de `pgcrypto`, nunca en
texto plano.

---

## Los cinco casos de uso

### 1. Sign in y log in con roles

`registrar_usuario(usuario, empleado_id, clave)` crea la cuenta con el hash bcrypt.
`login_usuario(usuario, clave)` devuelve una fila con el rol y la sucursal si las
credenciales son válidas, y ninguna fila si no lo son. También verifica que el
empleado siga activo.

```sql
SELECT * FROM login_usuario('maya.gerente', 'aurea2026');
```

Después del login, la aplicación debe declarar quién está trabajando para que la
bitácora lo registre:

```sql
SET aurea.usuario = 'maya.gerente';
```

### 2. Gestión de reservas

`crear_reserva(...)` registra la reserva y le asigna mesa en una sola transacción.
Busca primero la mesa individual más chica que alcance, para no quemar una mesa de
ocho con dos personas; si no hay, combina mesas de mayor a menor. Si no alcanza,
levanta excepción y no deja la reserva huérfana.

`mesas_disponibles(sucursal, fecha, hora, duración)` lista lo que está libre en esa
franja. `disponibilidad_dia(sucursal, fecha)` es la alerta de disponibilidad que
pide el enunciado: recorre el día en franjas de 30 minutos y marca cada una como
`Holgado`, `Crítico` o `Lleno`.

Dos triggers impiden el doble uso de una mesa. El primero actúa al asignarla; el
segundo revalida cuando una reserva se mueve de día u hora, porque sin él bastaría
con crear la reserva a las 15:00 y después moverla a las 19:00 para esquivar al
primero.

### 3. Gestión de inventario

El inventario se lleva por lotes, cada uno con su fecha de caducidad y su saldo. La
aplicación nunca actualiza el saldo: inserta un movimiento y el trigger
`fn_aplicar_movimiento` recalcula. El trigger bloquea la fila del lote con
`SELECT ... FOR UPDATE`, así que dos salidas simultáneas del mismo lote no pueden
consumir el mismo saldo.

Cuatro tipos de movimiento. `Entrada` suma, `Salida` y `Merma` restan, y `Ajuste`
recibe el **conteo físico final**, no una cantidad a sumar: si había 5 kg y se
cuentan 3, se ingresa 3 y el sistema registra una variación de −2.

Un lote vencido queda fuera del stock utilizable y solo acepta mermas o ajustes que
reduzcan.

### 4. Historial de clientes

`v_historial_cliente` reúne reservas, órdenes, gasto y preferencias de cada cliente.
Las preferencias se declaran en `preferencia_cliente`; las observaciones sobre la
experiencia van en `reserva.observaciones`.

### 5. Control de cambios

Una sola función, `fn_bitacora()`, enganchada a 12 tablas. Usa `to_jsonb(OLD)` y
`to_jsonb(NEW)`, así que guarda la fila completa sin nombrar una sola columna y
agregar una tabla más a la auditoría es una línea.

```sql
SELECT fecha_hora, tabla, operacion, usuario FROM bitacora ORDER BY bitacora_id DESC LIMIT 20;
```

---

## Decisiones de modelado

### La regla del 15%

El enunciado pide alertar cuando quede un mínimo del 15% del inventario. La
interpretación que tomamos es un umbral de reposición por insumo y por sucursal:

```
stock disponible = suma de lotes NO vencidos de ese insumo en esa sede
umbral           = mayor(stock_minimo, stock_referencia × 0.15)
alerta           = stock disponible <= umbral
```

Con una referencia de 20 kg y un mínimo de 2 kg, la alerta salta a los 3 kg. Si el
mínimo fuera 5 kg, salta a los 5. La alerta es individual: no espera a que el 15%
del catálogo completo esté en riesgo.

Un lote cuenta como **por vencer** si tiene saldo y caduca dentro de los próximos 7
días, incluyendo hoy. El plazo de 7 días es decisión del grupo, porque el enunciado
no lo especifica.

### Conversión de unidades

Las recetas se escriben como se cocina, en gramos y mililitros. El inventario se
lleva como se compra, en kilos y litros. La tabla `unidad_conversion` y la función
`convertir()` son el puente.

Sin ellas el descuento por venta restaría mil veces de más: un plato con 200 g de
papa bajaría 200 kg del inventario. El script 05 termina con una verificación que
falla si alguna línea de receta no tiene conversión posible.

### Descuento de inventario por venta

Es lo que conecta las tres mitades del sistema. Cuando una orden pasa a
`Completada`, el trigger `fn_descontar_inventario`:

1. Lee la receta de cada platillo de la orden.
2. Convierte cada cantidad a la unidad del insumo.
3. Descuenta de los lotes de **esa** sucursal con criterio **FEFO**, consumiendo
   primero el que caduca antes, que es como se maneja un almacén de perecederos.
4. Si un insumo no alcanza, levanta excepción y la orden entera se revierte.

El punto 4 importa: el sistema no permite vender algo que no se puede preparar.

### Una sola fuente de verdad para las ventas

`detalle_orden` es lo que se vendió. `detalle_factura` es la copia fiscal, y **no se
escribe a mano**: la llena un trigger desde `detalle_orden` al emitir la factura, y
el mismo trigger calcula el total. Así las dos tablas no pueden discrepar, y el
reporte de platos más vendidos siempre da el mismo número venga de donde venga.

### Los datos del cliente son opcionales

En una cafetería mucha gente no quiere dejar sus datos, así que `nit`, `nombre`,
`apellido`, `telefono` y `correo` admiten NULL.

Lo único que se exige es que la ficha sirva para algo: **nombre, teléfono o correo,
al menos uno**. Sin esa regla una ficha vacía es solo un ID, se crearía una nueva en
cada visita y el reporte de clientes frecuentes contaría a la misma persona muchas
veces.

El cliente que no quiere dar nada no necesita ficha. `orden.cliente_id` admite NULL
y la venta se registra igual: entra al reporte de platos más vendidos y no al de
clientes frecuentes, que es lo correcto. `factura.cliente_id` también admite NULL,
y en ese caso la factura sale a Consumidor Final con NIT `CF`.

Como nombre y apellido pueden faltar, concatenarlos con `||` devolvería NULL y las
pantallas saldrían en blanco. Por eso existe `nombre_cliente(id, nombre, apellido)`,
que devuelve lo que haya y, si no hay nada, `Cliente #<id>`. Las cuatro vistas que
muestran clientes la usan, así que el formato se cambia en un solo lugar.

### El estado de la mesa

`mesa.estado` guarda el estado **físico**: `Disponible`, `Ocupada` o
`Mantenimiento`. Que esté reservada no se guarda ahí, porque una mesa no está
reservada en absoluto: está reservada de 19:00 a 20:30 del jueves. Eso se calcula
desde `reserva` y `reserva_mesa`.

---

## Los cinco reportes

Todos son vistas y todos usan CTEs.

| Reporte | Vista |
|---|---|
| i. Top 10 de los platos más vendidos | `rpt_top_platillos` |
| ii. Top 10 de los clientes más frecuentes | `rpt_clientes_frecuentes` |
| iii. Top 5 de clientes con mayores reservas y su preferencia | `rpt_clientes_reservas` |
| iv. Reporte mensual de insumos a punto de terminarse o caducar | `rpt_insumos_criticos` |
| v. Comportamiento de sucursales con mayor cantidad de reservas y ventas | `rpt_sucursales` |

```sql
SELECT * FROM rpt_top_platillos;
SELECT * FROM rpt_insumos_criticos WHERE sucursal_id = 1;
```

El reporte iii combina las dos lecturas de "preferencia": lo que el cliente declaró
y lo que más ha pedido en la práctica.

---

## Verificar que todo quedó bien

```sql
-- Ninguna mesa puede estar reservada dos veces a la misma hora
SELECT count(*) FROM reserva_mesa a
  JOIN reserva ra ON ra.reserva_id = a.reserva_id
  JOIN reserva_mesa b ON b.mesa_id = a.mesa_id AND b.sucursal_id = a.sucursal_id
                     AND b.reserva_id > a.reserva_id
  JOIN reserva rb ON rb.reserva_id = b.reserva_id
 WHERE ra.estado <> 'Cancelada' AND rb.estado <> 'Cancelada'
   AND ra.fecha_reserva = rb.fecha_reserva
   AND ra.hora_reserva < rb.hora_reserva + make_interval(mins => rb.duracion_min)
   AND rb.hora_reserva < ra.hora_reserva + make_interval(mins => ra.duracion_min);

-- La factura siempre cuadra con su orden
SELECT count(*) FROM (
  SELECT f.factura_id FROM factura f JOIN detalle_orden d ON d.orden_id = f.orden_id
   GROUP BY f.factura_id, f.total
  HAVING f.total <> sum(d.cantidad * d.precio_unitario)) t;

-- Ningún lote con saldo negativo
SELECT count(*) FROM lote_inventario WHERE cantidad_disponible < 0;
```

Las tres deben dar cero.

---

## Notas para el equipo

**Módulo de inventario.** La aplicación web de inventario fue desarrollada contra un
esquema `inventario` separado. Para apuntarla a esta base hay que cambiar en
`app.py`:

- `options='-c search_path=inventario,public ...'` → `search_path=public`
- `'SELECT 1 FROM inventario.ingrediente LIMIT 1'` → `FROM ingrediente`
- La tupla `CATEGORIES` ahora es: `Carnes`, `Lácteos`, `Panadería`, `Despensa`,
  `Frutas y verduras`, `Café y té`, `Bebidas`
- Al registrar un movimiento, enviar `empleado_id` además de `responsable`

Las demás consultas no se tocan: todas usan nombres sin calificar y el cambio de
`search_path` las reapunta solas.

**Insumos y recetas.** `stock_minimo` y `stock_referencia` venían en NULL y sin
ellos la alerta del 15% no tiene de dónde calcular. Los valores actuales son
estimaciones de consumo semanal; cámbienlos si tienen datos mejores. Las unidades
`P` de Pan Artesanal y Hielo, que no estaban definidas en ningún lado, quedaron en
`ud` y `kg`.
