# Modelo de datos

Se conserva el esquema del respaldo `Base_datos_Aurea_Inicio.sql`. Aunque tiene extensión SQL, el archivo es un respaldo **custom de PostgreSQL**. `db/001_base.sql` contiene su estructura exportada con `pg_restore --schema-only --no-owner --no-privileges`.

| Tabla añadida | Uso y relaciones |
| --- | --- |
| usuario | Correo único, hash, rol de acceso; referencia opcional a empleado |
| preferencia | N:M cliente/platillo, con clave primaria compuesta |
| visita | N:1 a cliente y sucursal; fecha y observaciones |
| venta | N:1 a visita y platillo; cantidad positiva y precio histórico |
| bitacora | Usuario, fecha, operación, tabla y versiones JSONB |

La migración agrega duración y observaciones a reservas. Cambia el teléfono de cliente de smallint a varchar(15), y permite decimales en cantidades de inventario y movimientos.

Las claves compuestas originales conservan la pertenencia de mesa y reserva a sucursal. Las claves foráneas impiden borrar datos utilizados; las reservas se cancelan para conservar su historial.

Las vistas `v_ventas` y `v_alertas_inventario` centralizan cálculos. Los índices cubren fecha/sucursal y cliente de reservas, sucursal/vencimiento de lotes, cliente/fecha de visitas y fecha de bitácora. Los triggers registran cambios dentro de su misma transacción.

Las reservas toman un bloqueo transaccional de sucursal para comprobar cruces de horarios. Esta regla se aplica en la API: cualquier integración que escriba directamente debe usar la misma lógica. En un servidor central se recomienda un proxy HTTPS y acceso privado de PostgreSQL limitado al servidor.

## Diagrama entidad-relación actualizado

GitHub y los visores compatibles con Mermaid muestran este diagrama directamente. Las mesas usan clave compuesta mesa_id/sucursal_id; reserva_mesa también referencia reserva_id/sucursal_id como pareja.

```mermaid
erDiagram
    CLIENTE ||--o{ RESERVA : realiza
    CLIENTE ||--o{ VISITA : registra
    CLIENTE ||--o{ PREFERENCIA : tiene
    PLATILLO ||--o{ PREFERENCIA : favorito
    PLATILLO ||--o{ VENTA : consumido
    PLATILLO ||--o{ DETALLE_RECETA : contiene
    INGREDIENTE ||--o{ DETALLE_RECETA : integra
    INGREDIENTE ||--o{ LOTE_INVENTARIO : recibido
    SUCURSAL ||--o{ LOTE_INVENTARIO : almacena
    SUCURSAL ||--o{ MESA : dispone
    SUCURSAL ||--o{ RESERVA : recibe
    SUCURSAL ||--o{ VISITA : recibe
    SUCURSAL ||--o{ EMPLEADO : emplea
    ROL ||--o{ EMPLEADO : clasifica
    EMPLEADO |o--o{ USUARIO : vincula
    EMPLEADO ||--o{ MOVIMIENTO_INVENTARIO : registra
    LOTE_INVENTARIO ||--o{ MOVIMIENTO_INVENTARIO : afecta
    RESERVA ||--o{ RESERVA_MESA : asigna
    MESA ||--o{ RESERVA_MESA : utiliza
    VISITA ||--o{ VENTA : incluye
    CLIENTE {
        integer cliente_id PK
        varchar nit
        varchar nombre
        varchar apellido
        varchar telefono
    }
    RESERVA {
        integer reserva_id PK
        integer cliente_id FK
        integer sucursal_id FK
        date fecha_reserva
        time hora_reserva
        integer personas
        integer duracion_minutos
        text estado
        text observaciones
    }
    MESA {
        integer mesa_id PK
        integer sucursal_id PK,FK
        integer capacidad
        text estado
    }
    RESERVA_MESA {
        integer reserva_id PK,FK
        integer mesa_id PK,FK
        integer sucursal_id PK,FK
    }
    SUCURSAL {
        integer sucursal_id PK
        varchar nombre_sucursal
        varchar telefono
        varchar dirreccion
        integer capacidad
    }
    EMPLEADO {
        integer empleado_id PK
        varchar nombre_empleado
        varchar apellido
        date fecha_contratacion
        integer rol_id FK
        integer sucursal_id FK
        text estado
    }
    ROL {
        integer rol_id PK
        varchar rol
    }
    USUARIO {
        integer usuario_id PK
        varchar nombre
        varchar correo UK
        text password_hash
        text rol
        integer empleado_id FK
        timestamptz creado_en
    }
    INGREDIENTE {
        integer ingrediente_id PK
        varchar nombre_ingrediente
        varchar unidad_medida
        numeric stock_minimo
    }
    LOTE_INVENTARIO {
        varchar lote_id PK
        integer ingrediente_id FK
        integer sucursal_id FK
        date fecha_ingreso
        date fecha_vencimiento
        numeric cantidad_disponible
    }
    MOVIMIENTO_INVENTARIO {
        integer movimiento_id PK
        varchar lote_id FK
        integer empleado_id FK
        timestamp fecha_hora
        text tipo_movimiento
        numeric cantidad
        varchar motivo
    }
    PLATILLO {
        integer platillo_id PK
        varchar nombre_platillo
        numeric precio
        varchar categoria
    }
    DETALLE_RECETA {
        integer platillo_id PK,FK
        integer ingrediente_id PK,FK
        numeric cantidad
        varchar unidad_medida
    }
    PREFERENCIA {
        integer cliente_id PK,FK
        integer platillo_id PK,FK
    }
    VISITA {
        integer visita_id PK
        integer cliente_id FK
        integer sucursal_id FK
        date fecha
        text observaciones
    }
    VENTA {
        integer venta_id PK
        integer visita_id FK
        integer platillo_id FK
        integer cantidad
        numeric precio_unitario
    }
    BITACORA {
        bigint bitacora_id PK
        timestamptz fecha_hora
        text usuario
        text tabla
        text operacion
        jsonb anterior
        jsonb nuevo
    }
```

Bitácora recibe eventos de las tablas auditadas por triggers. Su usuario se conserva como texto histórico para no perder la atribución al eliminar cuentas.
