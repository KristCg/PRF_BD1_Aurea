SET search_path TO inventario, public;
INSERT INTO sucursal(nombre_sucursal) VALUES ('Áurea Cayalá'), ('Áurea Naranjo');
INSERT INTO ingrediente(nombre_ingrediente,categoria,unidad_medida,stock_minimo,stock_referencia) VALUES
('Café de especialidad','Café y té','kg',3,20),
('Leche entera','Lácteos','L',5,40),
('Harina de trigo','Panadería','kg',3,25),
('Chocolate oscuro','Despensa','kg',1,8),
('Mantequilla','Lácteos','kg',1,10),
('Azúcar morena','Despensa','kg',2,15),
('Fresas frescas','Frutas y frescos','kg',1,8),
('Té matcha','Café y té','g',100,1000),
('Crema para batir','Lácteos','L',2,12),
('Huevos','Panadería','ud',12,100);
INSERT INTO lote_inventario(lote_id,ingrediente_id,sucursal_id,fecha_vencimiento)
SELECT 'AUR-' || lpad(i.ingrediente_id::text,3,'0') || '-' || s.sucursal_id,
    i.ingrediente_id, s.sucursal_id,
    CURRENT_DATE + CASE i.ingrediente_id WHEN 2 THEN 4 WHEN 5 THEN 6 WHEN 7 THEN 2 WHEN 9 THEN 5 ELSE 45 END
FROM ingrediente i CROSS JOIN sucursal s;
INSERT INTO movimiento_inventario(lote_id,tipo_movimiento,cantidad,responsable,motivo)
SELECT l.lote_id,'Entrada',
    CASE l.ingrediente_id WHEN 1 THEN 16 WHEN 2 THEN 4 WHEN 3 THEN 18 WHEN 4 THEN 5.5
    WHEN 5 THEN 3 WHEN 6 THEN 10 WHEN 7 THEN 0.8 WHEN 8 THEN 650 WHEN 9 THEN 1.5 WHEN 10 THEN 72 END,
    'Carga inicial','Existencias de demostración'
FROM lote_inventario l;
