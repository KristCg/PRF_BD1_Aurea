
SELECT
    current_database() AS base_actual,
    (SELECT COUNT(*) FROM sucursal) AS sucursales,
    (SELECT COUNT(*) FROM platillo) AS platillos,
    (SELECT COUNT(*) FROM cliente) AS clientes,
    (SELECT COUNT(*) FROM orden) AS ordenes,
    (
        SELECT COUNT(*)
        FROM orden
        WHERE estado = 'Completada'
    ) AS ordenes_completadas,
    (SELECT COUNT(*) FROM detalle_orden) AS detalles;


	SELECT
    MIN(fecha_hora)::date AS primera_venta,
    MAX(fecha_hora)::date AS ultima_venta,
    COUNT(*) AS ordenes_completadas
FROM orden
WHERE estado = 'Completada';

SELECT
    o.orden_id,
    o.fecha_hora,
    s.nombre_sucursal AS sucursal,
    o.cliente_id,
    p.nombre_platillo AS platillo,
    p.categoria,
    d.cantidad,
    d.precio_unitario,
    d.cantidad * d.precio_unitario AS importe
FROM orden AS o
JOIN detalle_orden AS d
    ON d.orden_id = o.orden_id
JOIN platillo AS p
    ON p.platillo_id = d.platillo_id
JOIN sucursal AS s
    ON s.sucursal_id = o.sucursal_id
WHERE o.estado = 'Completada'
ORDER BY o.fecha_hora, o.orden_id, p.platillo_id
LIMIT 20;

SELECT
    COUNT(DISTINCT o.orden_id) AS compras,
    COUNT(*) AS lineas_de_venta,
    SUM(d.cantidad) AS unidades_vendidas,
    SUM(d.cantidad * d.precio_unitario) AS ventas_totales,
    ROUND(
        SUM(d.cantidad * d.precio_unitario)
        / NULLIF(COUNT(DISTINCT o.orden_id), 0),
        2
    ) AS ticket_promedio
FROM orden AS o
JOIN detalle_orden AS d
    ON d.orden_id = o.orden_id
WHERE o.estado = 'Completada';


SELECT
    o.orden_id,
    o.fecha_hora,
    o.sucursal_id,
    s.nombre_sucursal,
    o.cliente_id,
    d.platillo_id,
    p.nombre_platillo,
    p.categoria,
    d.cantidad,
    d.precio_unitario
FROM orden AS o
JOIN detalle_orden AS d
    ON d.orden_id = o.orden_id
JOIN platillo AS p
    ON p.platillo_id = d.platillo_id
JOIN sucursal AS s
    ON s.sucursal_id = o.sucursal_id
WHERE o.estado = 'Completada'
ORDER BY o.fecha_hora, o.orden_id, d.platillo_id;

CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS datamart;

CREATE TABLE staging.ventas_originales (
    orden_id         text,
    fecha_hora       text,
    sucursal_id      text,
    nombre_sucursal  text,
    cliente_id       text,
    platillo_id      text,
    nombre_platillo  text,
    categoria        text,
    cantidad         text,
    precio_unitario  text
);

SELECT COUNT(*) AS filas_importadas
FROM staging.ventas_originales;


SELECT *
FROM staging.ventas_originales
LIMIT 5;