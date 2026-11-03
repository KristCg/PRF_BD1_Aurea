BEGIN;

-- Reune las compras y sus platillos. Cada fila es una linea de factura.
CREATE OR REPLACE VIEW public.v_historial_compras AS
SELECT f.cliente_id, f.factura_id, f.orden_id, f.fecha_hora_emision,
       o.sucursal_id, s.nombre_sucursal,
       df.numero_linea, df.platillo_id, p.nombre_platillo,
       df.descripcion AS descripcion_facturada,
       df.cantidad, df.precio_unitario, df.subtotal
FROM public.factura f
JOIN public.orden o ON o.orden_id = f.orden_id
JOIN public.sucursal s ON s.sucursal_id = o.sucursal_id
JOIN public.detalle_factura df ON df.factura_id = f.factura_id
JOIN public.platillo p ON p.platillo_id = df.platillo_id;

-- Cuenta reservas y facturas por separado para no duplicar los totales.
CREATE OR REPLACE FUNCTION public.obtener_historial_resumen(p_cliente_id INTEGER)
RETURNS TABLE (
    cliente_id INTEGER,
    nombre VARCHAR(30),
    apellido VARCHAR(30),
    total_reservas BIGINT,
    reservas_completadas BIGINT,
    reservas_canceladas BIGINT,
    compras_facturadas BIGINT,
    total_facturado NUMERIC
)

LANGUAGE plpgsql AS $$
DECLARE
    v_total_reservas BIGINT;
    v_completadas BIGINT;
    v_canceladas BIGINT;
    v_compras BIGINT;
    v_total NUMERIC;
BEGIN
    PERFORM 1 FROM public.cliente c WHERE c.cliente_id = p_cliente_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'El cliente % no existe', p_cliente_id;
    END IF;

    SELECT COUNT(*) INTO v_total_reservas
    FROM public.reserva r WHERE r.cliente_id = p_cliente_id;

    SELECT COUNT(*) INTO v_completadas
    FROM public.reserva r
    WHERE r.cliente_id = p_cliente_id AND r.estado = 'Completada';

    SELECT COUNT(*) INTO v_canceladas
    FROM public.reserva r
    WHERE r.cliente_id = p_cliente_id AND r.estado = 'Cancelada';

    SELECT COUNT(*), SUM(f.total) INTO v_compras, v_total
    FROM public.factura f WHERE f.cliente_id = p_cliente_id;

    IF v_total IS NULL THEN
        v_total := 0;
    END IF;

    RETURN QUERY
    SELECT c.cliente_id, c.nombre, c.apellido,
           v_total_reservas, v_completadas, v_canceladas, v_compras, v_total
    FROM public.cliente c WHERE c.cliente_id = p_cliente_id;
END;
$$;

-- Muestra todos los estados; las reservas sin fecha se agregan al final.
CREATE OR REPLACE FUNCTION public.obtener_historial_reservas(p_cliente_id INTEGER)
RETURNS TABLE (
    reserva_id INTEGER, fecha_reserva DATE, hora_reserva TIME,
    sucursal_id INTEGER, nombre_sucursal VARCHAR(15),
    personas SMALLINT, estado TEXT
)
LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT r.reserva_id, r.fecha_reserva, r.hora_reserva,
           r.sucursal_id, s.nombre_sucursal, r.personas, r.estado
    FROM public.reserva r
    JOIN public.sucursal s ON s.sucursal_id = r.sucursal_id
    WHERE r.cliente_id = p_cliente_id AND r.fecha_reserva IS NOT NULL
    ORDER BY r.fecha_reserva DESC, r.hora_reserva DESC, r.reserva_id DESC;

    RETURN QUERY
    SELECT r.reserva_id, r.fecha_reserva, r.hora_reserva,
           r.sucursal_id, s.nombre_sucursal, r.personas, r.estado
    FROM public.reserva r
    JOIN public.sucursal s ON s.sucursal_id = r.sucursal_id
    WHERE r.cliente_id = p_cliente_id AND r.fecha_reserva IS NULL
    ORDER BY r.hora_reserva DESC, r.reserva_id DESC;
END;
$$;

-- Una fila por factura. Los detalles se consultan desde la vista.
CREATE OR REPLACE FUNCTION public.obtener_historial_compras(p_cliente_id INTEGER)
RETURNS TABLE (
    factura_id INTEGER, orden_id INTEGER, fecha_hora_emision TIMESTAMP,
    sucursal_id INTEGER, nombre_sucursal VARCHAR(15), total NUMERIC
)
LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT f.factura_id, f.orden_id, f.fecha_hora_emision,
           o.sucursal_id, s.nombre_sucursal, f.total
    FROM public.factura f
    JOIN public.orden o ON o.orden_id = f.orden_id
    JOIN public.sucursal s ON s.sucursal_id = o.sucursal_id
    WHERE f.cliente_id = p_cliente_id
    ORDER BY f.fecha_hora_emision DESC, f.factura_id DESC;
END;
$$;

-- Suma unidades facturadas; no son favoritos declarados por el cliente.
CREATE OR REPLACE FUNCTION public.obtener_historial_mas_consumidos(p_cliente_id INTEGER)
RETURNS TABLE (platillo_id INTEGER, nombre_platillo VARCHAR(50), unidades BIGINT)
LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    WITH consumo_cliente AS (
        SELECT v.platillo_id, v.nombre_platillo,
               SUM(v.cantidad) AS cantidad_total
        FROM public.v_historial_compras v
        WHERE v.cliente_id = p_cliente_id
        GROUP BY v.platillo_id, v.nombre_platillo
    )
    SELECT c.platillo_id, c.nombre_platillo, c.cantidad_total
    FROM consumo_cliente c
    ORDER BY c.cantidad_total DESC, c.nombre_platillo, c.platillo_id;
END;
$$;

COMMIT;



