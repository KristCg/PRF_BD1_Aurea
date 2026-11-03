-- =====================================================================
-- Cafeteria AUREA · CC3088 Base de Datos 1 · Proyecto No. 2
-- 03 · VISTAS Y REPORTES
--
-- Requiere 01_schema.sql y 02_funciones.sql
-- Los cinco reportes del enunciado estan al final, con CTEs.
-- =====================================================================


-- =====================================================================
-- A · VISTAS DE APOYO
-- =====================================================================

CREATE OR REPLACE VIEW v_usuario_sesion AS
SELECT u.usuario_id, u.nombre_usuario, u.estado, u.ultimo_login,
       e.empleado_id, e.sucursal_id,
       (e.nombre_empleado || ' ' || e.apellido) AS empleado,
       r.rol
  FROM usuario u
  JOIN empleado e ON e.empleado_id = u.empleado_id
  JOIN rol      r ON r.rol_id      = e.rol_id;


-- Existencias por insumo y sucursal. El stock utilizable excluye los
-- lotes vencidos. El umbral del 15% se resuelve aqui, una sola vez.
CREATE OR REPLACE VIEW existencias AS
WITH saldos AS (
    SELECT i.ingrediente_id, s.sucursal_id,
           COALESCE(sum(l.cantidad_disponible)
                    FILTER (WHERE l.fecha_vencimiento >= CURRENT_DATE), 0) AS stock_actual,
           COALESCE(sum(l.cantidad_disponible)
                    FILTER (WHERE l.fecha_vencimiento <  CURRENT_DATE), 0) AS stock_vencido,
           count(l.lote_id) FILTER (WHERE l.cantidad_disponible > 0
                    AND l.fecha_vencimiento BETWEEN CURRENT_DATE AND CURRENT_DATE + 7)
                    AS lotes_por_vencer,
           min(l.fecha_vencimiento) FILTER (WHERE l.cantidad_disponible > 0
                    AND l.fecha_vencimiento >= CURRENT_DATE) AS proximo_vencimiento
      FROM ingrediente i
     CROSS JOIN sucursal s
      LEFT JOIN lote_inventario l
             ON l.ingrediente_id = i.ingrediente_id AND l.sucursal_id = s.sucursal_id
     GROUP BY i.ingrediente_id, s.sucursal_id
)
SELECT i.ingrediente_id, i.nombre_ingrediente, i.categoria, i.unidad_medida,
       i.stock_minimo, i.stock_referencia,
       s.sucursal_id, s.stock_actual, s.stock_vencido,
       s.lotes_por_vencer, s.proximo_vencimiento,
       greatest(i.stock_minimo, i.stock_referencia * 0.15) AS umbral_alerta,
       s.stock_actual <= greatest(i.stock_minimo, i.stock_referencia * 0.15) AS stock_bajo
  FROM saldos s JOIN ingrediente i USING (ingrediente_id);

COMMENT ON VIEW existencias IS
'Regla del 15%: umbral = mayor(stock_minimo, stock_referencia * 0.15).
 La alerta es por insumo y por sucursal, no espera a que el 15% del
 catalogo completo este en riesgo.';


-- Reserva con su cliente, su sede y las mesas que tiene asignadas.
CREATE OR REPLACE VIEW v_reserva_detalle AS
SELECT r.reserva_id, r.fecha_reserva, r.hora_reserva,
       (r.hora_reserva + make_interval(mins => r.duracion_min))::time AS hora_fin,
       r.duracion_min, r.estado, r.personas, r.observaciones,
       c.cliente_id, (c.nombre || ' ' || c.apellido) AS cliente, c.telefono,
       s.sucursal_id, s.nombre_sucursal,
       count(rm.mesa_id)                                      AS mesas_asignadas,
       string_agg(rm.mesa_id::text, ', ' ORDER BY rm.mesa_id) AS mesas,
       COALESCE(sum(m.capacidad), 0)                          AS capacidad_asignada
  FROM reserva  r
  JOIN cliente  c ON c.cliente_id  = r.cliente_id
  JOIN sucursal s ON s.sucursal_id = r.sucursal_id
  LEFT JOIN reserva_mesa rm ON rm.reserva_id = r.reserva_id
  LEFT JOIN mesa m ON m.mesa_id = rm.mesa_id AND m.sucursal_id = rm.sucursal_id
 GROUP BY r.reserva_id, c.cliente_id, s.sucursal_id;


CREATE OR REPLACE VIEW v_agenda_hoy AS
SELECT * FROM v_reserva_detalle
 WHERE fecha_reserva = CURRENT_DATE AND estado IN ('Pendiente','Confirmada')
 ORDER BY sucursal_id, hora_reserva;


CREATE OR REPLACE VIEW v_reservas_sin_mesa AS
SELECT * FROM v_reserva_detalle
 WHERE mesas_asignadas = 0 AND estado IN ('Pendiente','Confirmada')
 ORDER BY fecha_reserva, hora_reserva;


-- Busqueda de reservas del requisito 2. Todos los filtros son
-- opcionales: NULL significa "no filtres por esto". p_texto busca por
-- nombre, apellido o telefono del cliente.
--
-- Va aqui y no en 02 porque devuelve SETOF de la vista de arriba.
CREATE OR REPLACE FUNCTION buscar_reservas(
    p_sucursal_id integer DEFAULT NULL,
    p_fecha_desde date    DEFAULT NULL,
    p_fecha_hasta date    DEFAULT NULL,
    p_estado      text    DEFAULT NULL,
    p_texto       text    DEFAULT NULL)
RETURNS SETOF v_reserva_detalle
LANGUAGE sql STABLE AS $$
    SELECT v.*
      FROM v_reserva_detalle v
     WHERE (p_sucursal_id IS NULL OR v.sucursal_id    = p_sucursal_id)
       AND (p_fecha_desde IS NULL OR v.fecha_reserva >= p_fecha_desde)
       AND (p_fecha_hasta IS NULL OR v.fecha_reserva <= p_fecha_hasta)
       AND (p_estado      IS NULL OR v.estado         = p_estado)
       AND (p_texto       IS NULL OR v.cliente  ILIKE '%' || p_texto || '%'
                                  OR v.telefono ILIKE '%' || p_texto || '%')
     ORDER BY v.fecha_reserva DESC, v.hora_reserva DESC;
$$;


-- Requisito 4: historial completo de visitas del cliente.
CREATE OR REPLACE VIEW v_historial_cliente AS
WITH reservas AS (
    SELECT cliente_id,
           count(*)                                        AS reservas_totales,
           count(*) FILTER (WHERE estado = 'Completada')    AS reservas_cumplidas,
           count(*) FILTER (WHERE estado = 'Cancelada')     AS reservas_canceladas,
           max(fecha_reserva)                               AS ultima_reserva
      FROM reserva GROUP BY cliente_id
),
consumo AS (
    SELECT o.cliente_id,
           count(DISTINCT o.orden_id)        AS ordenes,
           COALESCE(sum(f.total), 0)         AS gasto_total
      FROM orden o LEFT JOIN factura f USING (orden_id)
     WHERE o.cliente_id IS NOT NULL AND o.estado = 'Completada'
     GROUP BY o.cliente_id
)
SELECT c.cliente_id, (c.nombre || ' ' || c.apellido) AS cliente, c.nit, c.telefono,
       COALESCE(r.reservas_totales, 0)    AS reservas_totales,
       COALESCE(r.reservas_cumplidas, 0)  AS reservas_cumplidas,
       COALESCE(r.reservas_canceladas, 0) AS reservas_canceladas,
       r.ultima_reserva,
       COALESCE(k.ordenes, 0)             AS ordenes,
       COALESCE(k.gasto_total, 0)         AS gasto_total,
       (SELECT string_agg(p.nombre_platillo, ', ' ORDER BY p.nombre_platillo)
          FROM preferencia_cliente pc JOIN platillo p USING (platillo_id)
         WHERE pc.cliente_id = c.cliente_id) AS preferencias
  FROM cliente c
  LEFT JOIN reservas r USING (cliente_id)
  LEFT JOIN consumo  k USING (cliente_id);


-- =====================================================================
-- B · LOS CINCO REPORTES DEL ENUNCIADO
-- =====================================================================

-- ---------------------------------------------------------------------
-- i. Top 10 de los platos mas vendidos
--
-- Sale de detalle_orden, que es la unica fuente de verdad de la venta.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW rpt_top_platillos AS
WITH ventas AS (
    SELECT d.platillo_id,
           sum(d.cantidad)                         AS unidades,
           sum(d.cantidad * d.precio_unitario)     AS ingresos,
           count(DISTINCT d.orden_id)              AS ordenes
      FROM detalle_orden d JOIN orden o USING (orden_id)
     WHERE o.estado = 'Completada'
     GROUP BY d.platillo_id
),
clasificado AS (
    -- row_number y no rank: con rank, un empate en el puesto 10
    -- devuelve 11 filas y el reporte deja de ser un top 10.
    -- El desempate por ingresos lo hace determinista.
    SELECT v.*, row_number() OVER (ORDER BY v.unidades DESC, v.ingresos DESC,
                                            v.platillo_id) AS posicion
      FROM ventas v
)
SELECT c.posicion, p.platillo_id, p.nombre_platillo, p.categoria,
       c.unidades, c.ordenes, c.ingresos,
       round(100.0 * c.ingresos / NULLIF(sum(c.ingresos) OVER (), 0), 2)
           AS pct_de_ingresos
  FROM clasificado c JOIN platillo p USING (platillo_id)
 WHERE c.posicion <= 10
 ORDER BY c.posicion;


-- ---------------------------------------------------------------------
-- ii. Top 10 de los clientes mas frecuentes
--
-- "Frecuente" = visitas, contando reservas cumplidas y ordenes.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW rpt_clientes_frecuentes AS
WITH visitas AS (
    SELECT cliente_id, count(*) AS n, max(fecha_reserva)::date AS ultima
      FROM reserva WHERE estado = 'Completada' GROUP BY cliente_id
    UNION ALL
    SELECT cliente_id, count(*), max(fecha_hora)::date
      FROM orden WHERE estado = 'Completada' AND cliente_id IS NOT NULL
     GROUP BY cliente_id
),
total AS (
    SELECT cliente_id, sum(n) AS visitas, max(ultima) AS ultima_visita
      FROM visitas GROUP BY cliente_id
),
gasto AS (
    SELECT o.cliente_id, COALESCE(sum(f.total), 0) AS gasto_total
      FROM orden o JOIN factura f USING (orden_id)
     WHERE o.cliente_id IS NOT NULL GROUP BY o.cliente_id
)
SELECT rank() OVER (ORDER BY t.visitas DESC, COALESCE(g.gasto_total,0) DESC) AS posicion,
       c.cliente_id, (c.nombre || ' ' || c.apellido) AS cliente, c.telefono,
       t.visitas, t.ultima_visita,
       COALESCE(g.gasto_total, 0) AS gasto_total,
       round(COALESCE(g.gasto_total,0) / NULLIF(t.visitas,0), 2) AS gasto_promedio
  FROM total t
  JOIN cliente c USING (cliente_id)
  LEFT JOIN gasto g USING (cliente_id)
 ORDER BY posicion
 LIMIT 10;


-- ---------------------------------------------------------------------
-- iii. Top 5 de los clientes con mayores reservas y su preferencia
--
-- La preferencia sale de dos lados: lo que el cliente declaro en
-- preferencia_cliente, y lo que mas ha pedido en la practica.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW rpt_clientes_reservas AS
WITH ranking AS (
    SELECT cliente_id, count(*) AS reservas,
           count(*) FILTER (WHERE estado = 'Completada') AS cumplidas,
           count(*) FILTER (WHERE estado = 'Cancelada')  AS canceladas
      FROM reserva GROUP BY cliente_id
    ORDER BY count(*) DESC LIMIT 5
),
mas_pedido AS (
    SELECT DISTINCT ON (o.cliente_id)
           o.cliente_id, p.nombre_platillo, sum(d.cantidad) AS veces
      FROM orden o
      JOIN detalle_orden d USING (orden_id)
      JOIN platillo p USING (platillo_id)
     WHERE o.estado = 'Completada' AND o.cliente_id IS NOT NULL
     GROUP BY o.cliente_id, p.nombre_platillo
     ORDER BY o.cliente_id, sum(d.cantidad) DESC, p.nombre_platillo
)
SELECT row_number() OVER (ORDER BY r.reservas DESC, c.cliente_id) AS posicion,
       c.cliente_id, (c.nombre || ' ' || c.apellido) AS cliente,
       r.reservas, r.cumplidas, r.canceladas,
       (SELECT string_agg(p.nombre_platillo, ', ' ORDER BY p.nombre_platillo)
          FROM preferencia_cliente pc JOIN platillo p USING (platillo_id)
         WHERE pc.cliente_id = c.cliente_id)    AS preferencia_declarada,
       m.nombre_platillo                        AS plato_mas_pedido,
       m.veces                                  AS veces_pedido
  FROM ranking r
  JOIN cliente c USING (cliente_id)
  LEFT JOIN mas_pedido m USING (cliente_id)
 ORDER BY posicion;


-- ---------------------------------------------------------------------
-- iv. Reporte mensual de insumos a punto de terminarse o caducar
--
-- Cubre las dos mitades del requisito 3: existencias bajo el umbral
-- del 15% y lotes que caducan dentro del mes.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW rpt_insumos_criticos AS
WITH por_caducar AS (
    SELECT l.ingrediente_id, l.sucursal_id,
           count(*)                       AS lotes_del_mes,
           sum(l.cantidad_disponible)     AS cantidad_en_riesgo,
           min(l.fecha_vencimiento)       AS vence_primero
      FROM lote_inventario l
     WHERE l.cantidad_disponible > 0
       AND l.fecha_vencimiento BETWEEN CURRENT_DATE AND CURRENT_DATE + 30
     GROUP BY l.ingrediente_id, l.sucursal_id
),
vencidos AS (
    SELECT ingrediente_id, sucursal_id, sum(cantidad_disponible) AS cantidad_vencida
      FROM lote_inventario
     WHERE cantidad_disponible > 0 AND fecha_vencimiento < CURRENT_DATE
     GROUP BY ingrediente_id, sucursal_id
)
SELECT e.sucursal_id, s.nombre_sucursal,
       e.ingrediente_id, e.nombre_ingrediente, e.categoria, e.unidad_medida,
       e.stock_actual, e.umbral_alerta, e.stock_bajo,
       COALESCE(c.lotes_del_mes, 0)      AS lotes_por_caducar,
       COALESCE(c.cantidad_en_riesgo, 0) AS cantidad_por_caducar,
       c.vence_primero,
       COALESCE(v.cantidad_vencida, 0)   AS cantidad_vencida,
       CASE WHEN COALESCE(v.cantidad_vencida,0) > 0        THEN 'Vencido'
            WHEN e.stock_actual = 0                        THEN 'Agotado'
            WHEN e.stock_bajo AND c.lotes_del_mes > 0      THEN 'Bajo y por caducar'
            WHEN e.stock_bajo                              THEN 'Existencias bajas'
            ELSE 'Por caducar' END       AS alerta
  FROM existencias e
  JOIN sucursal s USING (sucursal_id)
  LEFT JOIN por_caducar c
         ON c.ingrediente_id = e.ingrediente_id AND c.sucursal_id = e.sucursal_id
  LEFT JOIN vencidos v
         ON v.ingrediente_id = e.ingrediente_id AND v.sucursal_id = e.sucursal_id
 WHERE e.stock_bajo
    OR c.lotes_del_mes      IS NOT NULL
    OR v.cantidad_vencida   IS NOT NULL
 ORDER BY e.sucursal_id,
          CASE WHEN COALESCE(v.cantidad_vencida,0) > 0 THEN 1
               WHEN e.stock_actual = 0 THEN 2 ELSE 3 END,
          c.vence_primero NULLS LAST,
          e.nombre_ingrediente;


-- ---------------------------------------------------------------------
-- v. Comportamiento de sucursales con mayor cantidad de reservas y ventas
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW rpt_sucursales AS
WITH reservas AS (
    SELECT sucursal_id,
           count(*)                                      AS reservas,
           count(*) FILTER (WHERE estado = 'Completada')  AS cumplidas,
           count(*) FILTER (WHERE estado = 'Cancelada')   AS canceladas,
           COALESCE(sum(personas) FILTER (WHERE estado = 'Completada'), 0) AS comensales
      FROM reserva GROUP BY sucursal_id
),
ventas AS (
    SELECT o.sucursal_id,
           count(DISTINCT o.orden_id)            AS ordenes,
           COALESCE(sum(f.total), 0)             AS ingresos
      FROM orden o LEFT JOIN factura f USING (orden_id)
     WHERE o.estado = 'Completada'
     GROUP BY o.sucursal_id
),
capacidad AS (
    SELECT sucursal_id, count(*) AS mesas, sum(capacidad) AS asientos
      FROM mesa GROUP BY sucursal_id
)
SELECT s.sucursal_id, s.nombre_sucursal,
       COALESCE(k.mesas, 0)       AS mesas,
       COALESCE(k.asientos, 0)    AS asientos,
       COALESCE(r.reservas, 0)    AS reservas,
       COALESCE(r.cumplidas, 0)   AS reservas_cumplidas,
       COALESCE(r.canceladas, 0)  AS reservas_canceladas,
       round(100.0 * COALESCE(r.canceladas,0) / NULLIF(r.reservas,0), 1)
                                  AS pct_cancelacion,
       COALESCE(r.comensales, 0)  AS comensales_atendidos,
       COALESCE(v.ordenes, 0)     AS ordenes,
       COALESCE(v.ingresos, 0)    AS ingresos,
       round(COALESCE(v.ingresos,0) / NULLIF(v.ordenes,0), 2) AS ticket_promedio,
       round(COALESCE(v.ingresos,0) / NULLIF(k.asientos,0), 2) AS ingreso_por_asiento,
       rank() OVER (ORDER BY COALESCE(r.reservas,0) DESC) AS puesto_reservas,
       rank() OVER (ORDER BY COALESCE(v.ingresos,0) DESC) AS puesto_ventas
  FROM sucursal s
  LEFT JOIN reservas  r USING (sucursal_id)
  LEFT JOIN ventas    v USING (sucursal_id)
  LEFT JOIN capacidad k USING (sucursal_id)
 ORDER BY COALESCE(v.ingresos,0) DESC, COALESCE(r.reservas,0) DESC;
