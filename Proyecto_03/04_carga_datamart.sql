BEGIN;

-- 1. Calendario: una fila por día del período.
INSERT INTO datamart.dim_fecha (
    fecha, anio, mes, nombre_mes,
    trimestre, dia, dia_semana, nombre_dia
)
SELECT
    fecha,
    EXTRACT(YEAR FROM fecha)::integer,
    EXTRACT(MONTH FROM fecha)::integer,
    (ARRAY[
        'Enero', 'Febrero', 'Marzo', 'Abril',
        'Mayo', 'Junio', 'Julio', 'Agosto',
        'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'
    ])[EXTRACT(MONTH FROM fecha)::integer],
    EXTRACT(QUARTER FROM fecha)::integer,
    EXTRACT(DAY FROM fecha)::integer,
    EXTRACT(ISODOW FROM fecha)::integer,
    (ARRAY[
        'Lunes', 'Martes', 'Miércoles', 'Jueves',
        'Viernes', 'Sábado', 'Domingo'
    ])[EXTRACT(ISODOW FROM fecha)::integer]
FROM (
    SELECT MIN(fecha) + serie.n AS fecha
    FROM staging.v_ventas_limpias
    CROSS JOIN LATERAL generate_series(
        0,
        (
            SELECT MAX(fecha) - MIN(fecha)
            FROM staging.v_ventas_limpias
        )
    ) AS serie(n)
    GROUP BY serie.n
) AS calendario
ON CONFLICT (fecha) DO NOTHING;

-- 2. Sucursales.
INSERT INTO datamart.dim_sucursal (
    sucursal_id, nombre_sucursal
)
SELECT DISTINCT sucursal_id, nombre_sucursal
FROM staging.v_ventas_limpias
ON CONFLICT (sucursal_id) DO NOTHING;

-- 3. Platillos.
INSERT INTO datamart.dim_platillo (
    platillo_id, nombre_platillo, categoria
)
SELECT DISTINCT platillo_id, nombre_platillo, categoria
FROM staging.v_ventas_limpias
ON CONFLICT (platillo_id) DO NOTHING;

-- 4. Cliente especial para ventas anónimas.
INSERT INTO datamart.dim_cliente (
    cliente_id, etiqueta, identificado
)
VALUES (0, 'Sin identificar', false)
ON CONFLICT (cliente_id) DO NOTHING;

-- Clientes identificados del archivo.
INSERT INTO datamart.dim_cliente (
    cliente_id, etiqueta, identificado
)
SELECT DISTINCT
    cliente_id,
    'Cliente #' || cliente_id::text,
    true
FROM staging.v_ventas_limpias
WHERE cliente_id IS NOT NULL
ON CONFLICT (cliente_id) DO NOTHING;

-- 5. Líneas de venta.
INSERT INTO datamart.fact_ventas (
    origen_datos,
    orden_id,
    fecha,
    sucursal_id,
    platillo_id,
    cliente_id,
    hora,
    cantidad,
    precio_unitario,
    importe
)
SELECT
    origen_datos,
    orden_id,
    fecha,
    sucursal_id,
    platillo_id,
    COALESCE(cliente_id, 0),
    hora,
    cantidad,
    precio_unitario,
    importe
FROM staging.v_ventas_limpias
ON CONFLICT (origen_datos, orden_id, platillo_id)
DO NOTHING;

COMMIT;

SELECT
    COUNT(*) AS lineas,
    COUNT(DISTINCT (origen_datos, orden_id)) AS compras,
    SUM(cantidad) AS unidades,
    SUM(importe) AS ventas,
    ROUND(
        SUM(importe)
        / NULLIF(COUNT(DISTINCT (origen_datos, orden_id)), 0),
        2
    ) AS ticket_promedio
FROM datamart.fact_ventas
WHERE origen_datos = 'Proyecto 2';