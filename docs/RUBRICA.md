# Cobertura de la rúbrica

| Requisito | Implementación |
| --- | --- |
| Registro y login por roles | Acceso, registro de meseros, sesiones HTTPOnly y contraseñas PBKDF2 con sal; permisos también en la API |
| Reservas y disponibilidad | Búsqueda, alta, edición, cancelación y finalización; varias mesas; capacidad, horario y sucursal validados transaccionalmente |
| Inventario por ingredientes | Existencias, lotes, vencimientos, entradas, salidas, mermas y ajustes; sin saldos negativos |
| Alertas del 15% | Inicio, campana e inventario; porcentaje de ingredientes por sucursal afectados |
| Historial de clientes | Detalle de cliente, visitas, consumos, observaciones, reservas y múltiples platos favoritos |
| Bitácora automática | Triggers INSERT/UPDATE/DELETE con usuario y valores anteriores/nuevos; se excluyen hashes de contraseña |
| Top 10 platos vendidos | Reporte 01: porciones y ventas del período |
| Top 10 clientes frecuentes | Reporte 02: visitas registradas |
| Top 5 reservas y preferencias | Reporte 03: reservas no canceladas y favoritos, mediante CTE |
| Reporte mensual de insumos | Reporte 04: consultar un mes completo; stock actual bajo y lotes que vencen en el período |
| Reservas y ventas por sucursal | Reporte 05: agregaciones independientes para evitar multiplicar totales |
| PostgreSQL, vistas, CTEs, índices, triggers | Migración SQL y consultas parametrizadas en el servidor |
| Carga reproducible | Inicialización y carga ficticia transaccional, documentadas en README |

## Decisiones para validar con el docente

Se interpreta el umbral de 15% como la proporción de ingredientes/sucursal afectados. El stock bajo ocurre cuando las existencias son menores o iguales al mínimo configurado; la caducidad próxima abarca siete días. Las alertas individuales se muestran siempre, aunque no se alcance el 15% general.

Las ventas provienen de consumos registrados en visitas y conservan el precio de ese momento. No se implementa facturación fiscal. El menú es común a todas las sucursales. El estado de mesa representa disponibilidad operativa; las reservas futuras se verifican por intervalos.

El registro público crea cuentas de mesero. La asignación de otro rol se realiza administrativamente en PostgreSQL. La interfaz muestra los últimos 300 cambios de bitácora y 200 movimientos; los históricos completos se conservan en la base.

## Entrega académica

El modelo y el DER actualizado se incluyen en `docs/MODELO.md`. El equipo debe revisarlos como parte de su entrega y preparar la exposición. Se conserva también la imagen del DER original.

El modo demo guarda información ficticia en el navegador. Para demostrar conexión directa, consultas y triggers, se debe iniciar con PostgreSQL. La demo no sustituye ese requisito de la rúbrica.
