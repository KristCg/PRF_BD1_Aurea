WITH limites AS (
    SELECT
        MIN(fecha) AS fecha_inicial,
        MAX(fecha) - MIN(fecha) + 1 AS dias_base,
        MAX(orden_id) + 1 AS salto_orden
    FROM staging.v_ventas_limpias
),
dias_simulados AS (
    SELECT
        DATE '2026-07-01' + n AS fecha,
        n AS numero_dia
    FROM generate_series(
        0,
        DATE '2026-09-30' - DATE '2026-07-01'
    ) AS serie(n)
)
SELECT
    -- Cada día tendrá números de orden distintos.
    (
        1000000
        + d.numero_dia::bigint * l.salto_orden
        + b.orden_id
    ) AS orden_id,

    -- Conservar el horario de la plantilla.
    (
        (d.fecha + b.fecha_hora_local::time)
        AT TIME ZONE 'America/Guatemala'
    ) AS fecha_hora,

    b.sucursal_id,
    b.nombre_sucursal,
    b.cliente_id,
    b.platillo_id,
    b.nombre_platillo,
    b.categoria,

    -- Variación sencilla y reproducible de cantidades.
    b.cantidad
        + CASE
            WHEN (b.orden_id + d.numero_dia) % 7 = 0
            THEN 1
            ELSE 0
          END AS cantidad,

    b.precio_unitario

FROM dias_simulados AS d
CROSS JOIN limites AS l
JOIN staging.v_ventas_limpias AS b
    ON b.fecha = l.fecha_inicial
        + (d.numero_dia % l.dias_base)

ORDER BY d.fecha, orden_id, b.platillo_id;