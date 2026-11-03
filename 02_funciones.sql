-- =====================================================================
-- Cafeteria AUREA · CC3088 Base de Datos 1 · Proyecto No. 2
-- 02 · FUNCIONES Y TRIGGERS
--
-- Requiere 01_schema.sql
-- =====================================================================


-- =====================================================================
-- A · BITACORA  (requisito 5)
--
-- Una sola funcion generica para todas las tablas. to_jsonb(OLD) y
-- to_jsonb(NEW) guardan la fila completa sin tener que nombrar una
-- sola columna, asi que agregar una tabla a la bitacora es una linea.
-- =====================================================================

CREATE OR REPLACE FUNCTION fn_bitacora() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO bitacora (tabla, operacion, usuario, anterior, nuevo)
    VALUES (TG_TABLE_NAME,
            TG_OP,
            COALESCE(NULLIF(current_setting('aurea.usuario', true), ''), session_user),
            CASE WHEN TG_OP <> 'INSERT' THEN to_jsonb(OLD) END,
            CASE WHEN TG_OP <> 'DELETE' THEN to_jsonb(NEW) END);
    RETURN NULL;
END $$;

COMMENT ON FUNCTION fn_bitacora IS
'Trigger generico de auditoria. La aplicacion identifica al usuario con
 SET LOCAL aurea.usuario = ''<nombre_usuario>'' despues del login.';

-- Se audita todo lo que el enunciado menciona: inventario, reservas,
-- y ademas el menu, los clientes y las ventas.
CREATE TRIGGER aud_ingrediente     AFTER INSERT OR UPDATE OR DELETE ON ingrediente
    FOR EACH ROW EXECUTE FUNCTION fn_bitacora();
CREATE TRIGGER aud_lote            AFTER INSERT OR UPDATE OR DELETE ON lote_inventario
    FOR EACH ROW EXECUTE FUNCTION fn_bitacora();
CREATE TRIGGER aud_movimiento      AFTER INSERT OR UPDATE OR DELETE ON movimiento_inventario
    FOR EACH ROW EXECUTE FUNCTION fn_bitacora();
CREATE TRIGGER aud_reserva         AFTER INSERT OR UPDATE OR DELETE ON reserva
    FOR EACH ROW EXECUTE FUNCTION fn_bitacora();
CREATE TRIGGER aud_reserva_mesa    AFTER INSERT OR UPDATE OR DELETE ON reserva_mesa
    FOR EACH ROW EXECUTE FUNCTION fn_bitacora();
CREATE TRIGGER aud_platillo        AFTER INSERT OR UPDATE OR DELETE ON platillo
    FOR EACH ROW EXECUTE FUNCTION fn_bitacora();
CREATE TRIGGER aud_detalle_receta  AFTER INSERT OR UPDATE OR DELETE ON detalle_receta
    FOR EACH ROW EXECUTE FUNCTION fn_bitacora();
CREATE TRIGGER aud_cliente         AFTER INSERT OR UPDATE OR DELETE ON cliente
    FOR EACH ROW EXECUTE FUNCTION fn_bitacora();
CREATE TRIGGER aud_orden           AFTER INSERT OR UPDATE OR DELETE ON orden
    FOR EACH ROW EXECUTE FUNCTION fn_bitacora();
CREATE TRIGGER aud_detalle_orden   AFTER INSERT OR UPDATE OR DELETE ON detalle_orden
    FOR EACH ROW EXECUTE FUNCTION fn_bitacora();
CREATE TRIGGER aud_factura         AFTER INSERT OR UPDATE OR DELETE ON factura
    FOR EACH ROW EXECUTE FUNCTION fn_bitacora();
CREATE TRIGGER aud_empleado        AFTER INSERT OR UPDATE OR DELETE ON empleado
    FOR EACH ROW EXECUTE FUNCTION fn_bitacora();


-- =====================================================================
-- B · AUTENTICACION  (requisito 1)
-- =====================================================================

CREATE OR REPLACE FUNCTION registrar_usuario(
    p_nombre_usuario text, p_empleado_id integer, p_password text)
RETURNS integer
LANGUAGE sql AS $$
    INSERT INTO usuario (empleado_id, nombre_usuario, password_hash)
    VALUES (p_empleado_id, lower(p_nombre_usuario),
            crypt(p_password, gen_salt('bf', 10)))
    RETURNING usuario_id;
$$;

CREATE OR REPLACE FUNCTION login_usuario(p_nombre text, p_password text)
RETURNS TABLE (usuario_id integer, nombre_usuario text,
               rol varchar, sucursal_id integer, empleado_id integer)
LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    WITH ok AS (
        UPDATE usuario u SET ultimo_login = now()
         WHERE u.nombre_usuario = lower(p_nombre)
           AND u.estado = 'Activo'
           AND u.password_hash = crypt(p_password, u.password_hash)
           AND EXISTS (SELECT 1 FROM empleado e
                        WHERE e.empleado_id = u.empleado_id AND e.estado = 'Activo')
        RETURNING u.usuario_id
    )
    SELECT v.usuario_id, v.nombre_usuario, v.rol, v.sucursal_id, v.empleado_id
      FROM v_usuario_sesion v JOIN ok ON ok.usuario_id = v.usuario_id;
END $$;


-- =====================================================================
-- C · NOMBRE DEL CLIENTE PARA MOSTRAR
--
-- Los datos del cliente son opcionales, asi que nombre y apellido
-- pueden venir nulos. Concatenarlos directo con || devuelve NULL en
-- cuanto uno de los dos falta, y la pantalla queda en blanco.
--
-- Esta funcion es el unico lugar donde se decide como se ve un cliente
-- sin datos. Todas las vistas la usan.
-- =====================================================================

CREATE OR REPLACE FUNCTION nombre_cliente(
    p_cliente_id integer, p_nombre varchar, p_apellido varchar)
RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT COALESCE(
        NULLIF(btrim(COALESCE(p_nombre,'') || ' ' || COALESCE(p_apellido,'')), ''),
        'Cliente #' || p_cliente_id);
$$;

COMMENT ON FUNCTION nombre_cliente IS
'Nombre para mostrar. Si el cliente no dio nombre ni apellido devuelve
 "Cliente #<id>", para que las pantallas y los reportes no salgan vacios.';


-- =====================================================================
-- D · CONVERSION DE UNIDADES
-- =====================================================================

CREATE OR REPLACE FUNCTION convertir(
    p_cantidad numeric, p_origen varchar, p_destino varchar)
RETURNS numeric
LANGUAGE plpgsql STABLE AS $$
DECLARE v_factor numeric;
BEGIN
    IF p_origen = p_destino THEN
        RETURN p_cantidad;
    END IF;

    SELECT factor INTO v_factor FROM unidad_conversion
     WHERE unidad_origen = p_origen AND unidad_destino = p_destino;

    IF v_factor IS NULL THEN
        RAISE EXCEPTION 'No hay conversion definida de % a %', p_origen, p_destino
            USING ERRCODE = 'P0001';
    END IF;

    RETURN p_cantidad * v_factor;
END $$;


-- =====================================================================
-- E · MOVIMIENTOS DE INVENTARIO  (requisito 3)
--
-- El saldo del lote lo mantiene el trigger, nunca la aplicacion.
-- El SELECT ... FOR UPDATE bloquea la fila, asi que dos salidas
-- simultaneas del mismo lote no pueden consumir el mismo saldo.
-- =====================================================================

CREATE OR REPLACE FUNCTION fn_aplicar_movimiento() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_saldo numeric(12,3);
    v_vence date;
BEGIN
    SELECT cantidad_disponible, fecha_vencimiento INTO v_saldo, v_vence
      FROM lote_inventario WHERE lote_id = NEW.lote_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El lote % no existe.', NEW.lote_id USING ERRCODE = 'P0001';
    END IF;

    IF NEW.tipo_movimiento <> 'Ajuste' AND NEW.cantidad <= 0 THEN
        RAISE EXCEPTION 'La cantidad debe ser mayor que cero.' USING ERRCODE = 'P0001';
    END IF;

    NEW.stock_anterior := v_saldo;

    -- Un Ajuste recibe el CONTEO FISICO final, no una cantidad a sumar.
    NEW.variacion := CASE NEW.tipo_movimiento
        WHEN 'Entrada' THEN  NEW.cantidad
        WHEN 'Ajuste'  THEN  NEW.cantidad - v_saldo
        ELSE                -NEW.cantidad
    END;

    IF NEW.variacion = 0 THEN
        RAISE EXCEPTION 'El conteo coincide con el saldo actual, no hay nada que registrar.'
            USING ERRCODE = 'P0001';
    END IF;

    -- Un lote vencido solo acepta mermas o ajustes que reduzcan.
    IF v_vence < CURRENT_DATE
       AND (NEW.tipo_movimiento IN ('Entrada','Salida') OR NEW.variacion > 0) THEN
        RAISE EXCEPTION 'El lote % esta vencido. Registra una merma o un ajuste de reduccion.',
            NEW.lote_id USING ERRCODE = 'P0001';
    END IF;

    NEW.stock_resultante := v_saldo + NEW.variacion;

    IF NEW.stock_resultante < 0 THEN
        RAISE EXCEPTION 'Existencias insuficientes en el lote %: hay %, se piden %.',
            NEW.lote_id, v_saldo, NEW.cantidad USING ERRCODE = 'P0001';
    END IF;

    UPDATE lote_inventario SET cantidad_disponible = NEW.stock_resultante
     WHERE lote_id = NEW.lote_id;

    RETURN NEW;
END $$;

CREATE TRIGGER trg_aplicar_movimiento
    BEFORE INSERT ON movimiento_inventario
    FOR EACH ROW EXECUTE FUNCTION fn_aplicar_movimiento();


-- Recepcion de lote: crea el lote y su Entrada en una sola operacion.
CREATE OR REPLACE FUNCTION recibir_lote(
    p_lote_id        varchar,
    p_ingrediente_id integer,
    p_sucursal_id    integer,
    p_cantidad       numeric,
    p_vencimiento    date,
    p_empleado_id    integer,
    p_motivo         varchar DEFAULT 'Recepcion de proveedor')
RETURNS varchar
LANGUAGE plpgsql AS $$
BEGIN
    IF p_vencimiento < CURRENT_DATE THEN
        RAISE EXCEPTION 'No se pueden recibir lotes vencidos.' USING ERRCODE = 'P0001';
    END IF;

    INSERT INTO lote_inventario
        (lote_id, ingrediente_id, sucursal_id, fecha_vencimiento)
    VALUES (p_lote_id, p_ingrediente_id, p_sucursal_id, p_vencimiento);

    INSERT INTO movimiento_inventario
        (lote_id, tipo_movimiento, cantidad, empleado_id, motivo)
    VALUES (p_lote_id, 'Entrada', p_cantidad, p_empleado_id, p_motivo);

    RETURN p_lote_id;
END $$;


-- =====================================================================
-- F · DESCUENTO DE INVENTARIO POR VENTA
--
-- Esto es lo que conecta las tres mitades del sistema: al completar
-- una orden, cada platillo consume sus ingredientes segun la receta,
-- convertidos a la unidad del inventario, y se descuentan de los lotes
-- de esa sucursal con criterio FEFO (primero el que vence antes).
-- =====================================================================

CREATE OR REPLACE FUNCTION fn_descontar_inventario() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_req      record;
    v_lote     record;
    v_falta    numeric(12,3);
    v_toma     numeric(12,3);
BEGIN
    -- Solo al pasar a Completada, y solo una vez.
    IF NEW.estado <> 'Completada' OR OLD.estado = 'Completada' THEN
        RETURN NEW;
    END IF;

    FOR v_req IN
        WITH necesidad AS (
            SELECT dr.ingrediente_id,
                   sum(convertir(dr.cantidad, dr.unidad_medida, i.unidad_medida)
                       * dor.cantidad) AS cantidad
              FROM detalle_orden   dor
              JOIN detalle_receta  dr USING (platillo_id)
              JOIN ingrediente     i  ON i.ingrediente_id = dr.ingrediente_id
             WHERE dor.orden_id = NEW.orden_id
             GROUP BY dr.ingrediente_id
        )
        SELECT n.ingrediente_id, n.cantidad, i.nombre_ingrediente, i.unidad_medida
          FROM necesidad n JOIN ingrediente i USING (ingrediente_id)
         ORDER BY n.ingrediente_id
    LOOP
        v_falta := v_req.cantidad;

        -- FEFO: se consume primero el lote que vence antes.
        FOR v_lote IN
            SELECT lote_id, cantidad_disponible
              FROM lote_inventario
             WHERE ingrediente_id    = v_req.ingrediente_id
               AND sucursal_id       = NEW.sucursal_id
               AND cantidad_disponible > 0
               AND fecha_vencimiento >= CURRENT_DATE
             ORDER BY fecha_vencimiento, lote_id
             FOR UPDATE
        LOOP
            EXIT WHEN v_falta <= 0;

            v_toma := least(v_falta, v_lote.cantidad_disponible);

            INSERT INTO movimiento_inventario
                (lote_id, tipo_movimiento, cantidad, empleado_id, motivo)
            VALUES (v_lote.lote_id, 'Salida', v_toma, NEW.empleado_id,
                    'Consumo por orden #' || NEW.orden_id);

            v_falta := v_falta - v_toma;
        END LOOP;

        IF v_falta > 0 THEN
            RAISE EXCEPTION
                'No hay suficiente % en la sucursal %: faltan % %.',
                v_req.nombre_ingrediente, NEW.sucursal_id,
                round(v_falta, 3), v_req.unidad_medida
                USING ERRCODE = 'P0001';
        END IF;
    END LOOP;

    RETURN NEW;
END $$;

CREATE TRIGGER trg_descontar_inventario
    AFTER UPDATE OF estado ON orden
    FOR EACH ROW EXECUTE FUNCTION fn_descontar_inventario();


-- =====================================================================
-- G · FACTURACION
--
-- detalle_factura no se escribe a mano. Este trigger la copia desde
-- detalle_orden al emitir la factura, para que la copia fiscal no
-- pueda discrepar de la venta real.
-- =====================================================================

CREATE OR REPLACE FUNCTION fn_llenar_detalle_factura() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE v_total numeric(10,2);
BEGIN
    INSERT INTO detalle_factura
        (factura_id, numero_linea, platillo_id, descripcion,
         cantidad, precio_unitario, subtotal)
    SELECT NEW.factura_id,
           row_number() OVER (ORDER BY d.platillo_id),
           d.platillo_id,
           p.nombre_platillo,
           d.cantidad,
           d.precio_unitario,
           d.cantidad * d.precio_unitario
      FROM detalle_orden d JOIN platillo p USING (platillo_id)
     WHERE d.orden_id = NEW.orden_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La orden #% no tiene lineas que facturar.', NEW.orden_id
            USING ERRCODE = 'P0001';
    END IF;

    SELECT sum(subtotal) INTO v_total
      FROM detalle_factura WHERE factura_id = NEW.factura_id;

    UPDATE factura SET total = v_total WHERE factura_id = NEW.factura_id;

    RETURN NULL;
END $$;

CREATE TRIGGER trg_llenar_detalle_factura
    AFTER INSERT ON factura
    FOR EACH ROW EXECUTE FUNCTION fn_llenar_detalle_factura();


-- =====================================================================
-- H · RESERVAS  (requisito 2)
-- =====================================================================

-- Devuelve la reserva que ya ocupa esa mesa en la franja dada, o NULL.
-- Dos reservas chocan si comparten mesa, sucursal y fecha, ninguna esta
-- cancelada, y sus franjas se traslapan: A.ini < B.fin AND B.ini < A.fin
CREATE OR REPLACE FUNCTION fn_choque_mesa(
    p_reserva_id integer, p_mesa_id smallint, p_sucursal_id integer)
RETURNS integer
LANGUAGE sql STABLE AS $$
    SELECT otra.reserva_id
      FROM reserva      esta
      JOIN reserva_mesa rm   ON rm.mesa_id = p_mesa_id AND rm.sucursal_id = p_sucursal_id
      JOIN reserva      otra ON otra.reserva_id = rm.reserva_id
     WHERE esta.reserva_id   = p_reserva_id
       AND esta.estado      <> 'Cancelada'
       AND otra.reserva_id  <> p_reserva_id
       AND otra.estado      <> 'Cancelada'
       AND otra.fecha_reserva = esta.fecha_reserva
       AND otra.hora_reserva  < esta.hora_reserva + make_interval(mins => esta.duracion_min)
       AND esta.hora_reserva  < otra.hora_reserva + make_interval(mins => otra.duracion_min)
     ORDER BY otra.reserva_id
     LIMIT 1;
$$;

-- La PK de reserva_mesa solo impide repetir la mesa DENTRO de una
-- reserva. Nada impedia que dos reservas distintas tomaran la mesa 3
-- el mismo jueves a las 19:00. Esto si.
CREATE OR REPLACE FUNCTION fn_reserva_mesa_sin_choque() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE v_otra integer;
BEGIN
    v_otra := fn_choque_mesa(NEW.reserva_id, NEW.mesa_id, NEW.sucursal_id);
    IF v_otra IS NOT NULL THEN
        RAISE EXCEPTION
            'La mesa % de la sucursal % ya esta tomada por la reserva #% en esa franja.',
            NEW.mesa_id, NEW.sucursal_id, v_otra USING ERRCODE = '23505';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_reserva_mesa_sin_choque
    BEFORE INSERT OR UPDATE ON reserva_mesa
    FOR EACH ROW EXECUTE FUNCTION fn_reserva_mesa_sin_choque();


-- Sin esto bastaria con crear la reserva a las 15:00 y luego moverla
-- a las 19:00 para pasarse el trigger anterior por encima.
CREATE OR REPLACE FUNCTION fn_reserva_revalida() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE v_rm record; v_otra integer;
BEGIN
    IF NEW.estado = 'Cancelada' THEN RETURN NEW; END IF;

    FOR v_rm IN SELECT mesa_id, sucursal_id FROM reserva_mesa
                 WHERE reserva_id = NEW.reserva_id
    LOOP
        v_otra := fn_choque_mesa(NEW.reserva_id, v_rm.mesa_id, v_rm.sucursal_id);
        IF v_otra IS NOT NULL THEN
            RAISE EXCEPTION
                'Al mover la reserva #% choca con la reserva #% en la mesa %.',
                NEW.reserva_id, v_otra, v_rm.mesa_id USING ERRCODE = '23505';
        END IF;
    END LOOP;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_reserva_revalida
    AFTER UPDATE OF fecha_reserva, hora_reserva, duracion_min, estado ON reserva
    FOR EACH ROW EXECUTE FUNCTION fn_reserva_revalida();


-- Mesas libres en una franja, de la mas chica a la mas grande, para que
-- la asignacion no queme una mesa de 8 con 2 personas.
CREATE OR REPLACE FUNCTION mesas_disponibles(
    p_sucursal_id integer, p_fecha date, p_hora time,
    p_duracion smallint DEFAULT 90)
RETURNS TABLE (mesa_id smallint, capacidad smallint)
LANGUAGE sql STABLE AS $$
    SELECT m.mesa_id, m.capacidad
      FROM mesa m
     WHERE m.sucursal_id = p_sucursal_id
       AND m.estado <> 'Mantenimiento'
       AND NOT EXISTS (
           SELECT 1 FROM reserva_mesa rm JOIN reserva r USING (reserva_id)
            WHERE rm.mesa_id = m.mesa_id AND rm.sucursal_id = m.sucursal_id
              AND r.fecha_reserva = p_fecha
              AND r.estado <> 'Cancelada'
              AND r.hora_reserva < p_hora + make_interval(mins => p_duracion)
              AND p_hora < r.hora_reserva + make_interval(mins => r.duracion_min))
     ORDER BY m.capacidad, m.mesa_id;
$$;


-- La ALERTA de disponibilidad que pide el requisito 2: franja por
-- franja de 30 minutos, cuantas mesas quedan libres ese dia.
CREATE OR REPLACE FUNCTION disponibilidad_dia(
    p_sucursal_id integer, p_fecha date,
    p_apertura time DEFAULT '08:00', p_cierre time DEFAULT '21:00')
RETURNS TABLE (franja time, mesas_totales bigint, mesas_libres bigint, nivel text)
LANGUAGE sql STABLE AS $$
    WITH franjas AS (
        SELECT g::time AS franja
          FROM generate_series(p_fecha + p_apertura, p_fecha + p_cierre,
                               interval '30 minutes') g
    ),
    totales AS (
        SELECT count(*) AS n FROM mesa
         WHERE sucursal_id = p_sucursal_id AND estado <> 'Mantenimiento'
    ),
    libres AS (
        SELECT f.franja,
               (SELECT count(*) FROM mesas_disponibles(
                    p_sucursal_id, p_fecha, f.franja, 90::smallint)) AS n
          FROM franjas f
    )
    SELECT l.franja, t.n, l.n,
           CASE WHEN l.n = 0                    THEN 'Lleno'
                WHEN l.n::numeric / t.n <= 0.20 THEN 'Critico'
                ELSE 'Holgado' END
      FROM libres l CROSS JOIN totales t
     ORDER BY l.franja;
$$;


-- Registra la reserva y le asigna mesas en una sola transaccion.
-- Busca primero la mesa individual mas chica que alcance; si no hay,
-- combina mesas de mayor a menor. Si no alcanza, levanta excepcion y
-- no queda nada a medias.
CREATE OR REPLACE FUNCTION crear_reserva(
    p_cliente_id     integer,
    p_sucursal_id    integer,
    p_fecha          date,
    p_hora           time,
    p_personas       smallint,
    p_duracion       smallint DEFAULT 90,
    p_observaciones  varchar  DEFAULT NULL,
    p_validar_pasado boolean  DEFAULT true)
RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE
    v_reserva_id integer;
    v_mesa_id    smallint;
    v_mesa       record;
    v_acumulado  smallint := 0;
BEGIN
    IF p_validar_pasado AND (p_fecha + p_hora) < now() THEN
        RAISE EXCEPTION 'No se puede reservar en el pasado (% a las %).', p_fecha, p_hora
            USING ERRCODE = '22007';
    END IF;

    INSERT INTO reserva (cliente_id, sucursal_id, fecha_reserva, hora_reserva,
                         estado, personas, duracion_min, observaciones)
    VALUES (p_cliente_id, p_sucursal_id, p_fecha, p_hora,
            'Pendiente', p_personas, p_duracion, p_observaciones)
    RETURNING reserva_id INTO v_reserva_id;

    SELECT d.mesa_id INTO v_mesa_id
      FROM mesas_disponibles(p_sucursal_id, p_fecha, p_hora, p_duracion) d
     WHERE d.capacidad >= p_personas
     ORDER BY d.capacidad LIMIT 1;

    IF v_mesa_id IS NOT NULL THEN
        INSERT INTO reserva_mesa (reserva_id, mesa_id, sucursal_id)
        VALUES (v_reserva_id, v_mesa_id, p_sucursal_id);
        RETURN v_reserva_id;
    END IF;

    FOR v_mesa IN SELECT d.mesa_id, d.capacidad
                    FROM mesas_disponibles(p_sucursal_id, p_fecha, p_hora, p_duracion) d
                   ORDER BY d.capacidad DESC
    LOOP
        EXIT WHEN v_acumulado >= p_personas;
        INSERT INTO reserva_mesa (reserva_id, mesa_id, sucursal_id)
        VALUES (v_reserva_id, v_mesa.mesa_id, p_sucursal_id);
        v_acumulado := v_acumulado + v_mesa.capacidad;
    END LOOP;

    IF v_acumulado < p_personas THEN
        RAISE EXCEPTION
            'No hay mesas suficientes en la sucursal % para % personas el % a las %.',
            p_sucursal_id, p_personas, p_fecha, p_hora USING ERRCODE = '23514';
    END IF;

    RETURN v_reserva_id;
END $$;


CREATE OR REPLACE FUNCTION asignar_mesa(p_reserva_id integer, p_mesa_id smallint)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_sucursal_id integer;
BEGIN
    SELECT sucursal_id INTO v_sucursal_id FROM reserva WHERE reserva_id = p_reserva_id;
    IF v_sucursal_id IS NULL THEN
        RAISE EXCEPTION 'No existe la reserva #%.', p_reserva_id USING ERRCODE = 'P0001';
    END IF;
    INSERT INTO reserva_mesa (reserva_id, mesa_id, sucursal_id)
    VALUES (p_reserva_id, p_mesa_id, v_sucursal_id);
END $$;


CREATE OR REPLACE FUNCTION liberar_mesa(p_reserva_id integer, p_mesa_id smallint)
RETURNS void
LANGUAGE sql AS $$
    DELETE FROM reserva_mesa WHERE reserva_id = p_reserva_id AND mesa_id = p_mesa_id;
$$;


-- Pendiente -> Confirmada -> Completada, o Cancelada desde cualquiera.
-- No se vuelve atras desde Completada ni Cancelada.
CREATE OR REPLACE FUNCTION cambiar_estado_reserva(p_reserva_id integer, p_estado text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_actual text;
BEGIN
    SELECT estado INTO v_actual FROM reserva WHERE reserva_id = p_reserva_id;
    IF v_actual IS NULL THEN
        RAISE EXCEPTION 'No existe la reserva #%.', p_reserva_id USING ERRCODE = 'P0001';
    END IF;
    IF v_actual IN ('Completada','Cancelada') THEN
        RAISE EXCEPTION 'La reserva #% ya esta % y no se puede cambiar.',
            p_reserva_id, v_actual USING ERRCODE = 'P0001';
    END IF;
    UPDATE reserva SET estado = p_estado WHERE reserva_id = p_reserva_id;
END $$;
