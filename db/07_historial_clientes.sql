

-- Si alguien ya cargo la version anterior de estas funciones, CREATE OR
-- REPLACE no puede cambiarles el tipo de retorno: hay que borrarlas antes.
-- Asi el script se puede correr las veces que haga falta.
DROP FUNCTION IF EXISTS obtener_historial_resumen(integer);
DROP FUNCTION IF EXISTS obtener_historial_reservas(integer);
DROP FUNCTION IF EXISTS obtener_historial_compras(integer);
DROP FUNCTION IF EXISTS obtener_historial_mas_consumidos(integer);
DROP FUNCTION IF EXISTS obtener_historial_preferencias(integer);


-- Una fila por linea de factura. Sirve de base para "mas consumidos".
-- factura.cliente_id es NULL en las ventas a Consumidor Final, que
-- simplemente no coinciden con ningun cliente.
CREATE OR REPLACE VIEW v_historial_compras AS
SELECT f.cliente_id, f.factura_id, f.orden_id, f.fecha_hora_emision,
      o.sucursal_id, s.nombre_sucursal,
      df.numero_linea, df.platillo_id, p.nombre_platillo,
      df.descripcion AS descripcion_facturada,
      df.cantidad, df.precio_unitario, df.subtotal
  FROM factura f
  JOIN orden o           ON o.orden_id     = f.orden_id
  JOIN sucursal s        ON s.sucursal_id  = o.sucursal_id
  JOIN detalle_factura df ON df.factura_id = f.factura_id
  JOIN platillo p        ON p.platillo_id  = df.platillo_id;


-- Resumen de un cliente. Reservas y facturas se cuentan por separado
-- para que los totales no se multipliquen entre si.
CREATE OR REPLACE FUNCTION obtener_historial_resumen(p_cliente_id integer)
RETURNS TABLE (
    cliente_id           integer,
    nombre               varchar,
    apellido             varchar,
    total_reservas       bigint,
    reservas_completadas bigint,
    reservas_canceladas  bigint,
    compras_facturadas   bigint,
    total_facturado      numeric
)
LANGUAGE plpgsql STABLE AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM cliente c WHERE c.cliente_id = p_cliente_id) THEN
        RAISE EXCEPTION 'El cliente % no existe', p_cliente_id;
    END IF;

    RETURN QUERY
    SELECT c.cliente_id, c.nombre, c.apellido,
            (SELECT count(*) FROM reserva r
              WHERE r.cliente_id = c.cliente_id),
            (SELECT count(*) FROM reserva r
              WHERE r.cliente_id = c.cliente_id AND r.estado = 'Completada'),
            (SELECT count(*) FROM reserva r
              WHERE r.cliente_id = c.cliente_id AND r.estado = 'Cancelada'),
            (SELECT count(*) FROM factura f
              WHERE f.cliente_id = c.cliente_id),
            (SELECT COALESCE(sum(f.total), 0) FROM factura f
              WHERE f.cliente_id = c.cliente_id)
        FROM cliente c
      WHERE c.cliente_id = p_cliente_id;
  END $$;


-- Todas las reservas del cliente, de la mas reciente a la mas antigua,
-- en cualquier estado.
CREATE OR REPLACE FUNCTION obtener_historial_reservas(p_cliente_id integer)
RETURNS TABLE (
    reserva_id      integer,
    fecha_reserva   date,
    hora_reserva    time,
    sucursal_id     integer,
    nombre_sucursal varchar,
    personas        smallint,
    estado          text,
    observaciones   varchar
)
LANGUAGE sql STABLE AS $$
    SELECT r.reserva_id, r.fecha_reserva, r.hora_reserva,
          r.sucursal_id, s.nombre_sucursal, r.personas, r.estado,
          r.observaciones
      FROM reserva r
      JOIN sucursal s ON s.sucursal_id = r.sucursal_id
    WHERE r.cliente_id = p_cliente_id
    ORDER BY r.fecha_reserva DESC, r.hora_reserva DESC, r.reserva_id DESC;
$$;


-- Una fila por factura. El detalle de cada una sale de v_historial_compras.
CREATE OR REPLACE FUNCTION obtener_historial_compras(p_cliente_id integer)
RETURNS TABLE (
    factura_id         integer,
    orden_id           integer,
    fecha_hora_emision timestamptz,
    sucursal_id        integer,
    nombre_sucursal    varchar,
    total              numeric
)
LANGUAGE sql STABLE AS $$
    SELECT f.factura_id, f.orden_id, f.fecha_hora_emision,
          o.sucursal_id, s.nombre_sucursal, f.total
      FROM factura f
      JOIN orden o    ON o.orden_id    = f.orden_id
      JOIN sucursal s ON s.sucursal_id = o.sucursal_id
    WHERE f.cliente_id = p_cliente_id
    ORDER BY f.fecha_hora_emision DESC, f.factura_id DESC;
$$;


-- Lo que el cliente ha consumido en la practica (unidades facturadas).
-- No son sus favoritos declarados: esos estan en obtener_historial_preferencias.
CREATE OR REPLACE FUNCTION obtener_historial_mas_consumidos(p_cliente_id integer)
RETURNS TABLE (platillo_id integer, nombre_platillo varchar, unidades bigint)
LANGUAGE sql STABLE AS $$
    WITH consumo_cliente AS (
        SELECT v.platillo_id, v.nombre_platillo, sum(v.cantidad) AS cantidad_total
        FROM v_historial_compras v
        WHERE v.cliente_id = p_cliente_id
        GROUP BY v.platillo_id, v.nombre_platillo
    )
    SELECT c.platillo_id, c.nombre_platillo, c.cantidad_total::bigint
      FROM consumo_cliente c
      ORDER BY c.cantidad_total DESC, c.nombre_platillo, c.platillo_id;
$$;


-- Preferencias que el cliente declaro (tabla preferencia_cliente).
CREATE OR REPLACE FUNCTION obtener_historial_preferencias(p_cliente_id integer)
RETURNS TABLE (platillo_id integer, nombre_platillo varchar, nota varchar)
LANGUAGE sql STABLE AS $$
    SELECT pc.platillo_id, p.nombre_platillo, pc.nota
      FROM preferencia_cliente pc
      JOIN platillo p ON p.platillo_id = pc.platillo_id
    WHERE pc.cliente_id = p_cliente_id
    ORDER BY p.nombre_platillo;
$$;
