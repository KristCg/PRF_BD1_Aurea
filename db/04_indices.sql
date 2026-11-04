

-- --- Reservas: busqueda por fecha, sede, cliente y estado ------------
CREATE INDEX idx_reserva_fecha          ON reserva (fecha_reserva, hora_reserva);
CREATE INDEX idx_reserva_sucursal_fecha ON reserva (sucursal_id, fecha_reserva);
CREATE INDEX idx_reserva_cliente        ON reserva (cliente_id);
CREATE INDEX idx_reserva_estado         ON reserva (estado);
CREATE INDEX idx_reserva_mesa_mesa      ON reserva_mesa (mesa_id, sucursal_id);
CREATE INDEX idx_mesa_sucursal          ON mesa (sucursal_id);

-- --- Inventario -------------------------------------------------------
CREATE INDEX idx_lote_sucursal_ingrediente ON lote_inventario (sucursal_id, ingrediente_id);
-- Parcial: al buscar lo que esta por caducar solo importan los lotes
-- con saldo, y en una base real esos son la minoria.
CREATE INDEX idx_lote_vencimiento ON lote_inventario (fecha_vencimiento)
    WHERE cantidad_disponible > 0;
-- FEFO: el orden en que el descuento por venta consume los lotes.
CREATE INDEX idx_lote_fefo ON lote_inventario
    (ingrediente_id, sucursal_id, fecha_vencimiento)
    WHERE cantidad_disponible > 0;
CREATE INDEX idx_movimiento_lote     ON movimiento_inventario (lote_id);
CREATE INDEX idx_movimiento_fecha    ON movimiento_inventario (fecha_hora DESC, movimiento_id DESC);
CREATE INDEX idx_movimiento_empleado ON movimiento_inventario (empleado_id);

-- --- Ventas -----------------------------------------------------------
CREATE INDEX idx_orden_sucursal_fecha ON orden (sucursal_id, fecha_hora);
CREATE INDEX idx_orden_cliente        ON orden (cliente_id) WHERE cliente_id IS NOT NULL;
CREATE INDEX idx_orden_empleado       ON orden (empleado_id);
CREATE INDEX idx_orden_estado         ON orden (estado);
-- El top 10 de platillos agrupa por platillo_id, que es la SEGUNDA
-- columna de la PK, asi que la PK no le sirve.
CREATE INDEX idx_detalle_orden_platillo ON detalle_orden (platillo_id);
CREATE INDEX idx_factura_cliente        ON factura (cliente_id);
CREATE INDEX idx_factura_fecha          ON factura (fecha_hora_emision DESC);
CREATE INDEX idx_detalle_factura_platillo ON detalle_factura (platillo_id);

-- --- Recetas y catalogo ----------------------------------------------
CREATE INDEX idx_detalle_receta_ingrediente ON detalle_receta (ingrediente_id);
CREATE INDEX idx_platillo_categoria         ON platillo (categoria);
CREATE INDEX idx_empleado_sucursal          ON empleado (sucursal_id);
CREATE INDEX idx_empleado_rol               ON empleado (rol_id);
CREATE INDEX idx_preferencia_platillo       ON preferencia_cliente (platillo_id);

-- --- Bitacora ---------------------------------------------------------
CREATE INDEX idx_bitacora_fecha  ON bitacora (fecha_hora DESC);
CREATE INDEX idx_bitacora_tabla  ON bitacora (tabla, operacion);
CREATE INDEX idx_bitacora_usuario ON bitacora (usuario);
