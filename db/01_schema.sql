-- Módulo aislado: no modifica las tablas del respaldo original del equipo.
CREATE SCHEMA inventario;
SET search_path TO inventario, public;

CREATE TABLE sucursal (
    sucursal_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre_sucursal varchar(40) NOT NULL UNIQUE
);
CREATE TABLE ingrediente (
    ingrediente_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre_ingrediente varchar(60) NOT NULL CHECK (btrim(nombre_ingrediente) <> ''),
    categoria varchar(25) NOT NULL CHECK (categoria IN ('Café y té','Lácteos','Panadería','Despensa','Frutas y frescos')),
    unidad_medida varchar(4) NOT NULL CHECK (unidad_medida IN ('kg','g','L','ml','ud')),
    stock_minimo numeric(12,3) NOT NULL CHECK (stock_minimo >= 0),
    stock_referencia numeric(12,3) NOT NULL CHECK (stock_referencia > 0 AND stock_referencia >= stock_minimo)
);
CREATE UNIQUE INDEX ingrediente_nombre_unico ON ingrediente (lower(btrim(nombre_ingrediente)));
CREATE TABLE lote_inventario (
    lote_id varchar(30) PRIMARY KEY CHECK (btrim(lote_id) <> ''),
    ingrediente_id integer NOT NULL REFERENCES ingrediente,
    sucursal_id integer NOT NULL REFERENCES sucursal,
    fecha_ingreso date NOT NULL DEFAULT CURRENT_DATE,
    fecha_vencimiento date NOT NULL CHECK (fecha_vencimiento >= fecha_ingreso),
    cantidad_disponible numeric(12,3) NOT NULL DEFAULT 0 CHECK (cantidad_disponible >= 0)
);
CREATE INDEX lote_sucursal_ingrediente ON lote_inventario (sucursal_id, ingrediente_id);
CREATE INDEX lote_vencimiento ON lote_inventario (fecha_vencimiento) WHERE cantidad_disponible > 0;
CREATE TABLE movimiento_inventario (
    movimiento_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    lote_id varchar(30) NOT NULL REFERENCES lote_inventario,
    fecha_hora timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    tipo_movimiento varchar(10) NOT NULL CHECK (tipo_movimiento IN ('Entrada','Salida','Merma','Ajuste')),
    cantidad numeric(12,3) NOT NULL CHECK (cantidad >= 0),
    variacion numeric(12,3) NOT NULL,
    stock_anterior numeric(12,3) NOT NULL,
    stock_resultante numeric(12,3) NOT NULL CHECK (stock_resultante >= 0),
    responsable varchar(60) NOT NULL CHECK (btrim(responsable) <> ''),
    motivo varchar(200) NOT NULL CHECK (btrim(motivo) <> '')
);
CREATE INDEX movimiento_fecha ON movimiento_inventario (fecha_hora DESC, movimiento_id DESC);
CREATE TABLE cambio_inventario (
    cambio_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fecha_hora timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    tabla text NOT NULL,
    operacion text NOT NULL,
    anterior jsonb,
    nuevo jsonb
);

-- Bloqueo de fila: dos salidas simultáneas no pueden consumir el mismo saldo.
CREATE FUNCTION aplicar_movimiento() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE saldo numeric(12,3); vence date;
BEGIN
    SELECT cantidad_disponible, fecha_vencimiento INTO saldo, vence
    FROM inventario.lote_inventario WHERE lote_id = NEW.lote_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'El lote no existe.' USING ERRCODE = 'P0001'; END IF;
    IF NEW.tipo_movimiento <> 'Ajuste' AND NEW.cantidad <= 0 THEN
        RAISE EXCEPTION 'La cantidad debe ser mayor que cero.' USING ERRCODE = 'P0001';
    END IF;
    NEW.stock_anterior := saldo;
    NEW.variacion := CASE NEW.tipo_movimiento
        WHEN 'Entrada' THEN NEW.cantidad
        WHEN 'Ajuste' THEN NEW.cantidad - saldo
        ELSE -NEW.cantidad END;
    IF NEW.variacion = 0 THEN RAISE EXCEPTION 'El conteo coincide con el saldo actual.' USING ERRCODE = 'P0001'; END IF;
    IF vence < CURRENT_DATE AND (NEW.tipo_movimiento IN ('Entrada','Salida') OR NEW.variacion > 0) THEN
        RAISE EXCEPTION 'El lote está vencido. Registra una merma o un ajuste de reducción.' USING ERRCODE = 'P0001';
    END IF;
    NEW.stock_resultante := saldo + NEW.variacion;
    IF NEW.stock_resultante < 0 THEN
        RAISE EXCEPTION 'Existencias insuficientes en el lote.' USING ERRCODE = 'P0001';
    END IF;
    UPDATE inventario.lote_inventario SET cantidad_disponible = NEW.stock_resultante WHERE lote_id = NEW.lote_id;
    RETURN NEW;
END $$;
CREATE TRIGGER movimiento_aplica_stock BEFORE INSERT ON movimiento_inventario
FOR EACH ROW EXECUTE FUNCTION aplicar_movimiento();

CREATE FUNCTION registrar_cambio() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO inventario.cambio_inventario(tabla, operacion, anterior, nuevo)
    VALUES (TG_TABLE_NAME, TG_OP,
        CASE WHEN TG_OP <> 'INSERT' THEN to_jsonb(OLD) END,
        CASE WHEN TG_OP <> 'DELETE' THEN to_jsonb(NEW) END);
    RETURN NULL;
END $$;
CREATE TRIGGER auditar_ingrediente AFTER INSERT OR UPDATE OR DELETE ON ingrediente
FOR EACH ROW EXECUTE FUNCTION registrar_cambio();
CREATE TRIGGER auditar_lote AFTER INSERT OR UPDATE OR DELETE ON lote_inventario
FOR EACH ROW EXECUTE FUNCTION registrar_cambio();
CREATE TRIGGER auditar_movimiento AFTER INSERT OR UPDATE OR DELETE ON movimiento_inventario
FOR EACH ROW EXECUTE FUNCTION registrar_cambio();

-- El stock utilizable excluye lotes vencidos; las alertas son por insumo y sede.
CREATE VIEW existencias AS
WITH saldos AS (
    SELECT i.ingrediente_id, s.sucursal_id,
      COALESCE(sum(l.cantidad_disponible) FILTER (WHERE l.fecha_vencimiento >= CURRENT_DATE), 0) AS stock_actual,
      COALESCE(sum(l.cantidad_disponible) FILTER (WHERE l.fecha_vencimiento < CURRENT_DATE), 0) AS stock_vencido,
      count(l.lote_id) FILTER (WHERE l.cantidad_disponible > 0 AND l.fecha_vencimiento BETWEEN CURRENT_DATE AND CURRENT_DATE + 7) AS lotes_por_vencer,
      min(l.fecha_vencimiento) FILTER (WHERE l.cantidad_disponible > 0 AND l.fecha_vencimiento >= CURRENT_DATE) AS proximo_vencimiento
    FROM ingrediente i CROSS JOIN sucursal s
    LEFT JOIN lote_inventario l ON l.ingrediente_id = i.ingrediente_id AND l.sucursal_id = s.sucursal_id
    GROUP BY i.ingrediente_id, s.sucursal_id
)
SELECT i.*, s.sucursal_id, s.stock_actual, s.stock_vencido, s.lotes_por_vencer, s.proximo_vencimiento,
    greatest(i.stock_minimo, i.stock_referencia * 0.15) AS umbral_alerta,
    s.stock_actual <= greatest(i.stock_minimo, i.stock_referencia * 0.15) AS stock_bajo
FROM saldos s JOIN ingrediente i USING (ingrediente_id);
