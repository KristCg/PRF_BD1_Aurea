# Áurea · Gestión de inventario

Módulo web del proyecto de Base de Datos 1 para la cafetería Áurea. Interfaz en español con colores beige, dorado y café, inspirada en la referencia proporcionada.

## Iniciar con Docker

Requisito: Docker Desktop iniciado, usando contenedores Linux y Docker Compose. Desde la carpeta del repositorio:

```powershell
docker compose up
```

Abrir **http://localhost:8080**. Compose construye la aplicación en el primer inicio, prepara PostgreSQL y carga los datos automáticamente. No necesitas instalar Python, Node ni PostgreSQL en tu computadora. La primera construcción necesita Internet para descargar las imágenes y dependencias.

Para dejarlo en segundo plano o reconstruir después de modificar código:

```powershell
docker compose up --build -d
```

Para detenerlo conservando los datos:

```powershell
docker compose down
```

Configuración opcional: copiar `.env.example` como `.env` y ajustar `APP_PORT` o `DB_PASSWORD` **antes del primer arranque**. PostgreSQL se comunica por la red interna de Compose. Cambiar la contraseña del archivo después de inicializar un volumen no modifica la contraseña almacenada en PostgreSQL.

## Alcance

Solo se implementa gestión de inventario:

- Catálogo de insumos: alta, búsqueda, edición y eliminación si no hay lotes relacionados.
- Filtros por categoría y estado, y paginación de tablas.
- Recepción de lotes con cantidad, sucursal y vencimiento.
- Entradas, salidas, mermas y ajustes por conteo físico.
- Existencias y alertas por sucursal.
- Historial completo de movimientos con responsable, motivo, variación y saldo resultante.
- Exportación CSV de la vista y filtros actuales.

Las sucursales son un catálogo precargado para separar existencias. No hay pantallas de administración de sucursales, autenticación, reservas, clientes, menú, personal ni reportería general. El responsable de cada movimiento se captura como texto; no representa una sesión autenticada. La auditoría SQL se limita a los datos de este módulo.

## Uso rápido

1. Seleccionar **Áurea Cayalá** o **Áurea Naranjo** en la esquina superior derecha.
2. Crear un insumo con su unidad, existencia mínima y existencia de referencia.
3. Usar **+** junto al insumo o **Lotes → Recibir lote** para registrar una recepción.
4. Registrar una **Salida** por consumo o una **Merma** por pérdida. Una **Entrada** agrega cantidad al mismo lote; si cambia el vencimiento, recibir un lote nuevo.
5. Un **Ajuste** recibe el conteo físico final, no una cantidad que se suma. Si había 5 kg y se cuentan 3 kg, ingresar 3: se registra una variación de −2 kg.
6. Revisar **Alertas**. Los indicadores del resumen también abren vistas filtradas.

Cada cantidad admite hasta tres decimales. Unidades: kg, g, L, ml y ud. No se hacen conversiones automáticas. La unidad queda fija cuando el insumo tiene algún lote en cualquier sucursal. Los códigos de lote son únicos en todo el módulo.

## Reglas de las alertas

La indicación del 15% se concreta como un umbral de reposición por insumo y sucursal:

```text
stock disponible = suma de lotes no vencidos
umbral de alerta = mayor(existencia mínima, existencia de referencia × 0.15)
existencias bajas = stock disponible <= umbral de alerta
```

Ejemplo: referencia de 20 kg y mínimo de 2 kg → alerta al llegar a 3 kg o menos. Si el mínimo fuera 5 kg, se alerta desde 5 kg. La referencia se configura en el formulario; no cambia con cada compra.

- **Por vencer:** lote con saldo positivo que vence entre hoy y los próximos 7 días, ambos incluidos.
- **Vencido:** vencimiento anterior a hoy. Su saldo no cuenta como disponible para usar.
- Un lote que vence hoy sigue vigente durante ese día.
- Los lotes vencidos solo admiten mermas o ajustes que reduzcan el saldo.
- Las alertas son individuales: no esperan a que el 15% de todos los insumos esté en riesgo.

El intervalo de 7 días es una decisión del módulo porque la rúbrica no especifica ese plazo. Las fechas se calculan en PostgreSQL con la zona `America/Guatemala`; la interfaz se actualiza al cargar, cambiar de sucursal o guardar.

## Base de datos y carga reproducible

PostgreSQL 17, Flask, psycopg y HTML/CSS/JavaScript sin dependencias externas de navegador.

En el primer inicio, sobre un volumen vacío, PostgreSQL ejecuta:

1. `db/01_schema.sql`: esquema `inventario`, tablas, restricciones, índices, vista con CTE y triggers.
2. `db/02_seed.sql`: 2 sucursales, 10 ingredientes, 20 lotes y 20 movimientos iniciales. Las caducidades son relativas al día de carga; hay ejemplos de existencias bajas y lotes por vencer.

Los datos se guardan en el volumen `inventario_data`. Reiniciar los contenedores no vuelve a insertar el catálogo ni elimina cambios. Editar los scripts de inicialización tampoco altera un volumen ya inicializado.

Para replicar la carga aisladamente conservando los datos de trabajo, usar otro proyecto y puerto desde PowerShell:

```powershell
$env:APP_PORT = '8081'
docker compose -p aurea-inventario-demo up --build -d
Remove-Item Env:APP_PORT
```

La copia estará en http://localhost:8081 y tendrá su propio volumen. Para detenerla: `docker compose -p aurea-inventario-demo down`.

### Relación con el respaldo del equipo

`Base_datos_Aurea_Inicio.sql` se conserva intacto. Aunque termina en `.sql`, es un respaldo binario PostgreSQL custom (`PGDMP`), por lo que requiere `pg_restore` y no ejecución como texto SQL.

El módulo retoma las entidades ingrediente, lote, movimiento y sucursal en el esquema independiente `inventario`. No restaura ni modifica tablas `public` del respaldo. Es autónomo para esta entrega; **la integración con la base compartida del equipo requiere una migración posterior**. Diferencias deliberadas:

- Cantidades `numeric(12,3)` en lugar de `smallint`, para admitir insumos fraccionarios.
- Categoría y existencia de referencia para filtros y la regla del 15%.
- Código de lote de hasta 30 caracteres.
- Responsable de texto en lugar de `empleado_id`, manteniendo independencia de autenticación y personal.
- Sucursal con identificador y nombre: catálogo mínimo para separar existencias.
- Saldo anterior y resultante en los movimientos para trazabilidad.

Ver [documentación del modelo y API](docs/inventario.md).

## Pruebas

Con los servicios iniciados:

```powershell
docker compose run --rm --no-deps --volume ./tests:/tests:ro --volume ./db:/schema:ro web python /tests/test_inventario.py
```

Las 16 pruebas crean y eliminan una base temporal `inventario_test_<uuid>` dentro de PostgreSQL. No modifican las existencias de la aplicación. Verifican transacciones, decimales, restricciones, auditoría, aislamiento por sucursal, umbrales, caducidad y dos salidas simultáneas del mismo lote.

Para consultar estado y registros:

```powershell
docker compose ps
docker compose logs web db
```

## Archivos principales

```text
compose.yaml                 Aplicación, PostgreSQL, volumen y healthchecks
Dockerfile                   Imagen de la aplicación
app.py                       API y validaciones
static/                      Interfaz Áurea
db/01_schema.sql             Modelo y lógica SQL
db/02_seed.sql               Datos de demostración
tests/test_inventario.py     Pruebas con PostgreSQL real
docs/inventario.md           Modelo y API
```

## Referencia del proyecto original

Proyecto 2 y Final del curso de Base de Datos 1


Documento con información general y base del menú, ingredientes, etc. de Aurea. https://app.notion.com/p/ESTILO-Y-MEN-CAFETER-A-3faf6ebcf13680e78cc0c4b55fde6609
