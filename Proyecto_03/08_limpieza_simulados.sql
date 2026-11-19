CREATE OR REPLACE VIEW staging.v_ventas_simuladas_limpias AS
WITH datos_tipados AS (
    SELECT
        TRIM(orden_id)::integer AS orden_id,

        TRIM(fecha_hora)::timestamptz
            AT TIME ZONE 'America/Guatemala' AS fecha_hora_local,

        TRIM(sucursal_id)::integer AS sucursal_id,
        TRIM(nombre_sucursal) AS nombre_sucursal,

        CASE
            WHEN cliente_id IS NULL
                 OR UPPER(TRIM(cliente_id)) IN ('', 'NULL')
            THEN NULL
            ELSE TRIM(cliente_id)::integer
        END AS cliente_id,

        TRIM(platillo_id)::integer AS platillo_id,
        TRIM(nombre_platillo) AS nombre_platillo,
        TRIM(categoria) AS categoria,
        TRIM(cantidad)::integer AS cantidad,
        TRIM(precio_unitario)::numeric(10,2) AS precio_unitario

    FROM staging.ventas_simuladas
)
SELECT
    orden_id,
    fecha_hora_local,
    fecha_hora_local::date AS fecha,
    EXTRACT(HOUR FROM fecha_hora_local)::integer AS hora,
    sucursal_id,
    nombre_sucursal,
    cliente_id,
    platillo_id,
    nombre_platillo,
    categoria,
    cantidad,
    precio_unitario,
    (cantidad * precio_unitario)::numeric(12,2) AS importe,
    'Simulado SQL'::text AS origen_datos
FROM datos_tipados;

SELECT
    COUNT(*) AS lineas,
    COUNT(DISTINCT orden_id) AS compras,
    SUM(cantidad) AS unidades,
    SUM(importe) AS ventas_simuladas,
    MIN(fecha) AS primera_fecha,
    MAX(fecha) AS ultima_fecha,

    COUNT(*) FILTER (
        WHERE cantidad IS NULL
           OR cantidad <= 0
           OR precio_unitario IS NULL
           OR precio_unitario < 0
    ) AS lineas_invalidas,

    COUNT(*) - COUNT(
        DISTINCT (orden_id, platillo_id)
    ) AS lineas_duplicadas

FROM staging.v_ventas_simuladas_limpias;