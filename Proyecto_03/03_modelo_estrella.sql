CREATE SCHEMA IF NOT EXISTS datamart;

-- DIMENSIONES

CREATE TABLE datamart.dim_fecha (
    fecha           date PRIMARY KEY,
    anio            integer NOT NULL,
    mes             integer NOT NULL,
    nombre_mes      varchar(15) NOT NULL,
    trimestre       integer NOT NULL,
    dia             integer NOT NULL,
    dia_semana      integer NOT NULL,
    nombre_dia      varchar(15) NOT NULL
);

CREATE TABLE datamart.dim_sucursal (
    sucursal_id      integer PRIMARY KEY,
    nombre_sucursal  varchar(100) NOT NULL
);

CREATE TABLE datamart.dim_platillo (
    platillo_id      integer PRIMARY KEY,
    nombre_platillo  varchar(100) NOT NULL,
    categoria        varchar(50) NOT NULL
);

CREATE TABLE datamart.dim_cliente (
    cliente_id      integer PRIMARY KEY,
    etiqueta        varchar(60) NOT NULL,
    identificado    boolean NOT NULL
);

-- TABLA DE HECHOS

CREATE TABLE datamart.fact_ventas (
    venta_id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    origen_datos    text NOT NULL,
    orden_id        integer NOT NULL,

    fecha           date NOT NULL
                    REFERENCES datamart.dim_fecha(fecha),

    sucursal_id     integer NOT NULL
                    REFERENCES datamart.dim_sucursal(sucursal_id),

    platillo_id     integer NOT NULL
                    REFERENCES datamart.dim_platillo(platillo_id),

    cliente_id      integer NOT NULL
                    REFERENCES datamart.dim_cliente(cliente_id),

    hora            integer NOT NULL
                    CHECK (hora BETWEEN 0 AND 23),

    cantidad        integer NOT NULL
                    CHECK (cantidad > 0),

    precio_unitario numeric(10,2) NOT NULL
                    CHECK (precio_unitario >= 0),

    importe         numeric(12,2) NOT NULL
                    CHECK (importe >= 0),

    CONSTRAINT venta_origen_orden_platillo_unica
        UNIQUE (origen_datos, orden_id, platillo_id),

    CONSTRAINT importe_venta_correcto
        CHECK (importe = cantidad * precio_unitario)
);

SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'datamart'
  AND table_type = 'BASE TABLE'
ORDER BY table_name;