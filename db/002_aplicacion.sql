BEGIN;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='cliente' AND column_name='telefono' AND data_type='smallint') THEN
  ALTER TABLE cliente ALTER COLUMN telefono TYPE varchar(15);
 END IF;
 IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='lote_inventario' AND column_name='cantidad_disponible' AND data_type='smallint') THEN
  ALTER TABLE lote_inventario ALTER COLUMN cantidad_disponible TYPE numeric(10,3);
 END IF;
 IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='movimiento_inventario' AND column_name='cantidad' AND data_type='smallint') THEN
  ALTER TABLE movimiento_inventario ALTER COLUMN cantidad TYPE numeric(10,3);
 END IF;
END; $$;
ALTER TABLE reserva ADD COLUMN IF NOT EXISTS duracion_minutos integer NOT NULL DEFAULT 90 CHECK (duracion_minutos BETWEEN 15 AND 480);
ALTER TABLE reserva ADD COLUMN IF NOT EXISTS observaciones text NOT NULL DEFAULT '';
CREATE TABLE IF NOT EXISTS usuario (
 usuario_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 nombre varchar(80) NOT NULL, correo varchar(120) UNIQUE NOT NULL,
 password_hash text NOT NULL, rol text NOT NULL CHECK (rol IN ('Administrador','Gerente','Mesero')),
 empleado_id integer REFERENCES empleado, creado_en timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS preferencia (
 cliente_id integer REFERENCES cliente, platillo_id integer REFERENCES platillo,
 PRIMARY KEY(cliente_id,platillo_id)
);
CREATE TABLE IF NOT EXISTS visita (
 visita_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 cliente_id integer NOT NULL REFERENCES cliente, sucursal_id integer NOT NULL REFERENCES sucursal,
 fecha date NOT NULL DEFAULT CURRENT_DATE, observaciones text NOT NULL DEFAULT ''
);
CREATE TABLE IF NOT EXISTS venta (
 venta_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 visita_id integer NOT NULL REFERENCES visita, platillo_id integer NOT NULL REFERENCES platillo,
 cantidad integer NOT NULL CHECK(cantidad>0), precio_unitario numeric(10,2) NOT NULL CHECK(precio_unitario>=0)
);
CREATE TABLE IF NOT EXISTS bitacora (
 bitacora_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 fecha_hora timestamptz NOT NULL DEFAULT now(), usuario text NOT NULL,
 tabla text NOT NULL, operacion text NOT NULL, anterior jsonb, nuevo jsonb
);
CREATE OR REPLACE FUNCTION registrar_cambio() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 INSERT INTO bitacora(usuario,tabla,operacion,anterior,nuevo)
 VALUES(COALESCE(NULLIF(current_setting('aurea.usuario',true),''),session_user),TG_TABLE_NAME,TG_OP,
 CASE WHEN TG_OP IN ('UPDATE','DELETE') THEN to_jsonb(OLD) - 'password_hash' ELSE NULL END,
 CASE WHEN TG_OP IN ('INSERT','UPDATE') THEN to_jsonb(NEW) - 'password_hash' ELSE NULL END);
 RETURN COALESCE(NEW,OLD);
END; $$;
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['cliente','empleado','ingrediente','lote_inventario','mesa','movimiento_inventario','platillo','reserva','reserva_mesa','sucursal','usuario','preferencia','visita','venta','detalle_receta'] LOOP
 EXECUTE format('DROP TRIGGER IF EXISTS auditar ON %I',t);
 EXECUTE format('CREATE TRIGGER auditar AFTER INSERT OR UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION registrar_cambio()',t);
 END LOOP;
END; $$;
CREATE INDEX IF NOT EXISTS idx_reserva_fecha_sucursal ON reserva(sucursal_id,fecha_reserva,hora_reserva);
CREATE INDEX IF NOT EXISTS idx_reserva_cliente ON reserva(cliente_id);
CREATE INDEX IF NOT EXISTS idx_lote_sucursal_vencimiento ON lote_inventario(sucursal_id,fecha_vencimiento);
CREATE INDEX IF NOT EXISTS idx_visita_cliente_fecha ON visita(cliente_id,fecha);
CREATE INDEX IF NOT EXISTS idx_bitacora_fecha ON bitacora(fecha_hora DESC);
CREATE OR REPLACE VIEW v_alertas_inventario AS
 WITH stock AS (
 SELECT ingrediente_id,sucursal_id,sum(cantidad_disponible) AS stock_actual,
 min(fecha_vencimiento) FILTER(WHERE cantidad_disponible>0) AS proximo_vencimiento
 FROM lote_inventario GROUP BY ingrediente_id,sucursal_id
 ) SELECT i.*,s.sucursal_id,COALESCE(s.stock_actual,0) stock_actual,s.proximo_vencimiento,
 COALESCE(s.stock_actual,0)<=COALESCE(i.stock_minimo,0) stock_bajo,
 s.proximo_vencimiento<=CURRENT_DATE+7 por_caducar
 FROM ingrediente i JOIN stock s USING(ingrediente_id);
CREATE OR REPLACE VIEW v_ventas AS
 SELECT v.venta_id,vi.cliente_id,vi.sucursal_id,vi.fecha,v.platillo_id,p.nombre_platillo,
 v.cantidad,v.precio_unitario,v.cantidad*v.precio_unitario AS total
 FROM venta v JOIN visita vi USING(visita_id) JOIN platillo p USING(platillo_id);
COMMIT;
