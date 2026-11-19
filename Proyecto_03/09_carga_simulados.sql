BEGIN;

-- 1. Ampliar el calendario para cubrir ambos orígenes.
WITH limites AS (
    SELECT
        MIN(fecha) AS inicio,
        MAX(fecha) AS fin
    FROM (
        SELECT fecha
        FROM staging.v_ventas_limpias

        UNION ALL

        SELECT fecha
        FROM staging.v_ventas_simuladas_limpias
    ) AS fechas
),
calendario AS (
    SELECT inicio + n AS fecha
    FROM limites
    CROSS JOIN LATERAL generate_series(
        0, fin - inicio
    ) AS serie(n)
)
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
FROM calendario
ON CONFLICT (fecha) DO NOTHING;

-- 2. Cargar las ventas simuladas.
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
FROM staging.v_ventas_simuladas_limpias
ON CONFLICT (origen_datos, orden_id, platillo_id)
DO NOTHING;

COMMIT;

SELECT
    origen_datos,
    COUNT(*) AS lineas,
    COUNT(DISTINCT orden_id) AS compras,
    SUM(cantidad) AS unidades,
    SUM(importe) AS ventas
FROM datamart.fact_ventas
GROUP BY origen_datos
ORDER BY origen_datos;

SELECT
    origen_datos,
    COUNT(*) AS lineas,
    SUM(importe) AS ventas
FROM datamart.v_ventas_analisis
GROUP BY origen_datos
ORDER BY origen_datos;