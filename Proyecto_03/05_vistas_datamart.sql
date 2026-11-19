CREATE OR REPLACE VIEW datamart.v_ventas_analisis AS
SELECT
    v.venta_id,
    v.origen_datos,

    -- Identificador de compra único entre distintos orígenes.
    v.origen_datos || ':' || v.orden_id::text AS compra_clave,

    v.orden_id,
    v.fecha,
    f.anio,
    f.mes,
    f.nombre_mes,
    f.trimestre,
    f.dia_semana,
    f.nombre_dia,
    v.hora,

    v.sucursal_id,
    s.nombre_sucursal,

    v.platillo_id,
    p.nombre_platillo,
    p.categoria,

    v.cliente_id,
    c.etiqueta AS cliente,
    c.identificado AS cliente_identificado,

    v.cantidad,
    v.precio_unitario,
    v.importe

FROM datamart.fact_ventas AS v

JOIN datamart.dim_fecha AS f
    ON f.fecha = v.fecha

JOIN datamart.dim_sucursal AS s
    ON s.sucursal_id = v.sucursal_id

JOIN datamart.dim_platillo AS p
    ON p.platillo_id = v.platillo_id

JOIN datamart.dim_cliente AS c
    ON c.cliente_id = v.cliente_id;


SELECT nombre_sucursal,
    COUNT(DISTINCT compra_clave) AS compras,
    SUM(cantidad) AS unidades,
    SUM(importe) AS ventas,
    ROUND(
        SUM(importe)
        / NULLIF(COUNT(DISTINCT compra_clave), 0),
        2
    ) AS ticket_promedio
FROM datamart.v_ventas_analisis
GROUP BY nombre_sucursal
ORDER BY ventas DESC;