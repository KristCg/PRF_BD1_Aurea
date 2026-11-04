--Correcciones de ciertas variables en tablas y version inicial de funcionalidad de Log in y Sign in, y bitacora 

CREATE TABLE cliente(
	cliente_id SERIAL PRIMARY KEY,
	nit VARCHAR(13) NOT NULL DEFAULT 'CF',
	nombre VARCHAR(30),
	apellido VARCHAR(30),
	telefono VARCHAR(15)
);

CREATE TABLE sucursal(
	sucursal_id SERIAL PRIMARY KEY,
	nombre_sucursal VARCHAR(15) NOT NULL,
	telefono VARCHAR(15) NOT NULL,
	direccion VARCHAR(100) NOT NULL,
	capacidad SMALLINT NOT NULL	
);

INSERT INTO sucursal(nombre_sucursal, telefono, direccion, capacidad) VALUES
	('Áurea Cayala', '2222-0001', 'Cayala Zona 15', 60),
	('Áurea Naranjo', '2222-0002', 'Condado Naranjo, Zona 4 de Mixco', 40),
	('Áurea Roosevelt', '2222-0003', 'Calzada Roosevelt, Zona 7', 80);

SELECT * FROM sucursal;

CREATE TABLE rol(
	rol_id SERIAL PRIMARY KEY,
	rol VARCHAR(30) NOT NULL
);

INSERT INTO rol(rol) VALUES
	('Gerente'),
	('Mesero'),
	('Administrador'),
	('Encargado de Inventario');

SELECT * FROM rol;

CREATE TABLE empleado(
	empleado_id SERIAL PRIMARY KEY,
	nombre_empleado VARCHAR(30) NOT NULL,
	apellido VARCHAR(30) NOT NULL,
	fecha_contratacion DATE NOT NULL DEFAULT CURRENT_DATE,
	rol_id INT NOT NULL,
	sucursal_id INT NOT NULL,
	estado TEXT DEFAULT 'Activo' CHECK(estado IN('Activo', 'Inactivo')),
	FOREIGN KEY (rol_id) REFERENCES rol(rol_id),
	FOREIGN KEY (sucursal_id) REFERENCES sucursal(sucursal_id)
);

INSERT INTO empleado(nombre_empleado, apellido, rol_id, sucursal_id) VALUES
	('Maya','Salazar',1,1),
	('Diego', 'Reyes', 2, 1),
	('Kristel', 'Castillo', 3, 1),
	('Carlos','Cifuentes', 4, 1);

SELECT * FROM empleado;

CREATE TABLE reserva(
	reserva_id SERIAL PRIMARY KEY,
	cliente_id INT NOT NULL,
	sucursal_id INT NOT NULL,
	fecha_reserva DATE DEFAULT CURRENT_DATE,
	hora_reserva TIME NOT NULL,
	estado TEXT NOT NULL DEFAULT 'Pendiente' CHECK (estado IN ('Pendiente','Confirmada','Cancelada','Completada')),
	personas SMALLINT NOT NULL CHECK (personas > 0),
    UNIQUE (reserva_id, sucursal_id),
    FOREIGN KEY (cliente_id) REFERENCES cliente(cliente_id),
    FOREIGN KEY (sucursal_id) REFERENCES sucursal(sucursal_id)
);

CREATE TABLE mesa(
	mesa_id SMALLINT,
	sucursal_id INT,
	capacidad SMALLINT NOT NULL,
	estado TEXT NOT NULL DEFAULT 'Disponible' CHECK(estado IN('Disponible','Ocupada', 'Reservada')),
	PRIMARY KEY (mesa_id, sucursal_id),
	FOREIGN KEY (sucursal_id) REFERENCES sucursal(sucursal_id)
);

INSERT INTO mesa(mesa_id, sucursal_id,capacidad) VALUES
	(1, 1, 2),
	(2, 1, 2),
	(3, 1, 2),
	(4, 1, 2),
	(5, 1, 4),
	(6, 1, 4),
	(7, 1, 4),
	(8, 1, 4),
	(9, 1, 6),
	(10, 1, 6),
	(11, 1, 6),
	(12, 1, 6),
	(13, 1, 6),
	(14, 1, 6);

SELECT * FROM mesa;

CREATE TABLE reserva_mesa (
    reserva_id INT NOT NULL,
    mesa_id INT NOT NULL,
    sucursal_id INT NOT NULL,
    PRIMARY KEY (reserva_id, mesa_id, sucursal_id),
    FOREIGN KEY (reserva_id, sucursal_id) REFERENCES reserva(reserva_id, sucursal_id),
	FOREIGN KEY (mesa_id, sucursal_id) REFERENCES mesa(mesa_id, sucursal_id)
);

CREATE TABLE platillo(
	platillo_id SERIAL PRIMARY KEY,
	nombre_platillo VARCHAR(50) NOT NULL,
	precio NUMERIC(5, 2) NOT NULL,
	categoria VARCHAR(15) NOT NULL
);

INSERT INTO platillo(nombre_platillo, precio, categoria) VALUES
	('Pollo a la parilla', 75.00, 'Plato Fuerte'),
	('Pasta Alfredo con Pollo', 80.00, 'Plato Fuerte'),
	('Risotto de Hongos', 88.00, 'Plato Fuerte' ),
	('Lomo en salsa de Pimienta', 115.00, 'Plato Fuerte'),
	('Pollo en salsa de champiñones', 105.00, 'Plato Fuerte'),
	('Ravioles de Ricota', 105.00, 'Plato Fuerte'),
	('Cheesecake de Frutos Rojos', 42.00,'Postre'),
	('Pastel de Chocolate', 40.00,'Postre'),
	('Croissant de Mantequilla', 28.00,'Postre'),
	('Espresso', 20.00,'Bebida'),
	('Americano', 25.00, 'Bebida'),
	('Cappuccino', 30.00, 'Bebida'),
	('Latte', 32.00, 'Bebida'),
	('Mocca', 35.00,'Bebida'),
	('Chocolate Caliente', 30.00,'Bebida'),
	('Té o infusión', 25.00,'Bebida'),
	('Americano Frio', 27.00, 'Bebida'),
	('Cappuccino Frio', 32.00, 'Bebida'),
	('Latte Frio', 34.00, 'Bebida'),
	('Mocca Frio', 37.00,'Bebida'),
	('Té Frio ', 27.00,'Bebida');
	
	
SELECT * FROM platillo;

CREATE TABLE ingrediente(
	ingrediente_id SERIAL PRIMARY KEY,
	nombre_ingrediente VARCHAR(30) NOT NULL,
	unidad_medida VARCHAR(4) NOT NULL,
	stock_minimo NUMERIC(7, 3) DEFAULT NULL
);

INSERT INTO ingrediente(nombre_ingrediente, unidad_medida) VALUES
	('Pechuga de Pollo', 'kg'),
	('Lomo de Res', 'kg'),
	('Leche', 'L'),
	('Crema', 'L'),
	('Mantequilla','kg'),
	('Queso Parmesano', 'kg'),
	('Arroz blanco','kg'),
	('Pasta seca','kg'),
	('Pan Artesanal','P'),
	('Ravioles de ricotta','kg'),
	('Croissant de mantequilla','ud'),
	('Tortillas de maíz','ud'),
	('Cheesecake', 'ud'),
	('Pastel de Chocolate', 'ud'),
	('Papa', 'kg'),
	('Brócoli','kg'),
	('Zanahoria','kg'),
	('Champiñones','kg'),
	('Cebolla','kg'),
	('Ajo','kg'),
	('Tomate triturado','kg'),
	('Aceite de oliva','L'),
	('Sal','kg'),
	('Pimienta negra','kg'),
	('Azucar','kg'),
	('Cacao en Polvo','kg'),
	('Caldo de vegetales','L'),
	('Café molido','kg'),
	('Bolsitas de té','ud'),
	('Agua potable','L'),
	('Hielo','P');

SELECT * FROM ingrediente;

CREATE TABLE lote_inventario(
	lote_id VARCHAR(13) PRIMARY KEY,
	ingrediente_id INT NOT NULL,
	sucursal_id INT NOT NULL,
	fecha_ingreso DATE NOT NULL DEFAULT CURRENT_DATE,
	fecha_vencimiento DATE NOT NULL,
	cantidad_disponible NUMERIC(10, 2),
	FOREIGN KEY (ingrediente_id) REFERENCES ingrediente(ingrediente_id),
	FOREIGN KEY (sucursal_id) REFERENCES sucursal(sucursal_id)
);


CREATE TABLE movimiento_inventario(
	 movimiento_id SERIAL PRIMARY KEY,
	 lote_id VARCHAR(13) NOT NULL,
	 empleado_id INT NOT NULL,
	 fecha_hora TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
	 tipo_movimiento TEXT DEFAULT 'Entrada' CHECK(tipo_movimiento IN('Entrada', 'Salida','Merma', 'Ajuste')),
	 cantidad NUMERIC(10, 2) CHECK (cantidad > 0),
	 motivo VARCHAR(50),
	 FOREIGN KEY (lote_id) REFERENCES lote_inventario(lote_id),
	 FOREIGN KEY (empleado_id) REFERENCES empleado(empleado_id)
);

CREATE TABLE detalle_receta(
	platillo_id INT NOT NULL,
	ingrediente_id INT NOT NULL,
	cantidad NUMERIC(6,3) NOT NULL  CHECK (cantidad > 0),
	unidad_medida VARCHAR(4) NOT NULL,
	PRIMARY KEY (platillo_id, ingrediente_id),
	FOREIGN KEY (platillo_id) REFERENCES platillo(platillo_id),
	FOREIGN KEY (ingrediente_id) REFERENCES ingrediente(ingrediente_id)
);

INSERT INTO detalle_receta(platillo_id, ingrediente_id, cantidad, unidad_medida) VALUES
	(1,1,180,'g'),
	(1,15,200,'g'),
	(1,3,40,'ml'),
	(1,5,15,'g'),
	(1,16,60,'g'),
	(1,17,50,'g'),
	(1,22,10,'ml'),
	(1,20,5,'g'),
	(1,23,2,'g'),
	(1,24,2,'g'),
	(2,8,120,'g'),
	(2,1,120,'g'),
	(2,4,100, 'ml'),
	(2,6,25, 'g'),
	(2,20,5, 'g'),
	(2,5,10, 'g'),
	(2,22,5, 'ml'),
	(2,23,3, 'g'),
	(2,24,1, 'g'),
	(3,7,100, 'g'),
	(3,18,100, 'g'),
	(3,27,300, 'ml'),
	(3,19,30 ,'g'),
	(3,20,5, 'g'),
	(3,5,15, 'g'),
	(3,6,25, 'g'),
	(3,22,10, 'ml'),
	(3,23,1.5 ,'g'),
	(3,24,1.5 ,'g'),
	(4,2,200, 'g'),
	(4,15,180, 'g'),
	(4,3,40,'ml'),
	(4,5,15,'g'),
	(4,4,60,'ml'),
	(4,27,50,'ml'),
	(4,24,3,'g'),
	(4,16,60,'g'),
	(4,17,50,'g'),
	(4,22,10,'ml'),
	(4,23,3,'g'),
	(5,1,180,'g'),
	(5,7,70,'g'),
	(5,18,80,'g'),
	(5,4,60,'ml'),
	(5,19,25,'g'),
	(5,20,5,'g'),
	(5,27,50,'ml'),
	(5,16,50,'g'),
	(5,17,50,'g'),
	(5,22,10,'ml'),
	(5,23,2,'g'),
	(5,24,2,'g'),
	(6,10,200,'g'),
	(6,21,150,'g'),
	(6,19,25,'g'),
	(6,20,5,'g'),
	(6,22,10,'ml'),
	(6,6,20,'g'),
	(6,23,3,'g'),
	(6,24,1,'g'),
	(7,13,1,'ud'),
	(8,14,1,'ud'),
	(9,11,1,'ud'),
	(10,28,18,'g'),
	(10,30,36,'ml'),
	(11,28,18,'g'),
	(11,30,156,'ml'),
	(12,28,18,'g'),
	(12,30,36,'ml'),
	(12,3,120,'ml'),
	(13,28,18,'g'),
	(13,30,36,'ml'),
	(13,3,180,'ml'),
	(14,28,18,'g'),
	(14,30,36,'ml'),
	(14,3,120,'ml'),
	(14,26,10,'g'),
	(15,3,200,'ml'),
	(15,26,25,'g'),
	(15,25,5,'g'),
	(16,30,250,'ml'),
	(16,29,1,'ud'),
	(16,25,5,'g'),
	(17,28,18,'g'),
	(17,30,156,'ml'),
	(17,31,5,'g'),
	(18,28,18,'g'),
	(18,30,36,'ml'),
	(18,3,120,'ml'),
	(18,31,5,'g'),
	(19,28,18,'g'),
	(19,30,36,'ml'),
	(19,3,180,'ml'),
	(19,31,5,'g'),
	(20,28,18,'g'),
	(20,30,36,'ml'),
	(20,3,120,'ml'),
	(20,26,10,'g'),
	(20,31,5,'g'),
	(21,30,250,'ml'),
	(21,29,1,'ud'),
	(21,25,5,'g'),
	(21,31,5,'g');

SELECT * FROM detalle_receta;

CREATE TABLE orden(
	orden_id SERIAL PRIMARY KEY,
	fecha_hora TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
	empleado_id INT NOT NULL,
	sucursal_id INT NOT NULL,
	estado TEXT NOT NULL DEFAULT 'Pendiente' CHECK (estado IN('Pendiente','Completada','Cancelada')),
	FOREIGN KEY (empleado_id) REFERENCES empleado(empleado_id),
	FOREIGN KEY (sucursal_id) REFERENCES sucursal(sucursal_id)
);

CREATE TABLE detalle_orden(
	orden_id INT NOT NULL,
	platillo_id INT NOT NULL,
	cantidad SMALLINT NOT NULL  CHECK (cantidad > 0),
	precio_unitario NUMERIC(10, 2) NOT NULL,
	PRIMARY KEY (orden_id, platillo_id),
	FOREIGN KEY (orden_id) REFERENCES orden(orden_id),
	FOREIGN KEY (platillo_id) REFERENCES platillo(platillo_id)
);

CREATE TABLE factura(
	factura_id SERIAL PRIMARY KEY,
	orden_id INT NOT NULL,
	cliente_id INT NOT NULL,
	fecha_hora_emision TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
	nit VARCHAR(13) DEFAULT 'CF',
	nombre_facturacion VARCHAR(50),
	total NUMERIC(10, 2) NOT NULL,
	FOREIGN KEY (orden_id) REFERENCES orden(orden_id),
	FOREIGN KEY (cliente_id) REFERENCES cliente(cliente_id)
);

CREATE TABLE detalle_factura(
	factura_id SMALLINT NOT NULL,
	numero_linea SMALLINT NOT NULL,
	platillo_id INT NOT NULL,
	descripcion VARCHAR(30) NOT NULL,
	cantidad SMALLINT NOT NULL CHECK (cantidad > 0),
	precio_unitario NUMERIC(10, 2) NOT NULL,
	subtotal NUMERIC(10, 2) NOT NULL,
	PRIMARY KEY(factura_id, numero_linea),
	FOREIGN KEY (factura_id) REFERENCES factura(factura_id),
	FOREIGN KEY (platillo_id) REFERENCES platillo(platillo_id)
);

--  INICIO FUNCIONALIDAD DE REGISTRO E INICIO DE SESIÓN
--- Nueva tabla de Usuario para poder realizar la funcionalidad
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE usuario(
	usuario_id SERIAL PRIMARY KEY,
	empleado_id INT NOT NULL UNIQUE,
	nombre_usuario TEXT NOT NULL UNIQUE,
	password_hash TEXT NOT NULL,
	estado TEXT NOT NULL DEFAULT 'Activo' CHECK(estado IN('Activo', 'Inactivo')),
	creado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ultimo_login TIMESTAMPTZ,
	FOREIGN KEY (empleado_id) REFERENCES empleado(empleado_id),
	CONSTRAINT nombreusuario_formato CHECK (nombre_usuario ~ '^[a-z0-9._]{4,30}$')
);

-- sign in - registrarse
CREATE OR REPLACE FUNCTION registrar_usuario(p_nombre_usuario TEXT, p_empleado_id INT, p_password TEXT) 
RETURNS INT
LANGUAGE sql 
AS $$
    INSERT INTO usuario (empleado_id, nombre_usuario, password_hash)
    VALUES (p_empleado_id, lower(p_nombre_usuario), crypt(p_password, gen_salt('bf', 10)))
    RETURNING usuario_id
$$;

--- log in / iniciar sesión
CREATE OR REPLACE VIEW v_usuario_sesion AS
SELECT u.usuario_id, u.nombre_usuario, u.estado, e.empleado_id, e.sucursal_id, r.rol
FROM usuario u
JOIN empleado e ON e.empleado_id = u.empleado_id
JOIN rol r ON r.rol_id = e.rol_id;

CREATE OR REPLACE FUNCTION login_usuario(p_nombre TEXT, p_password TEXT)
RETURNS TABLE (usuario_id INT, nombre_usuario TEXT, rol VARCHAR, sucursal_id INT)
LANGUAGE plpgsql 
AS $$
BEGIN
    RETURN QUERY
    WITH ok AS (
        UPDATE usuario u SET ultimo_login = now()
        WHERE u.nombre_usuario = lower(p_nombre)
    	AND u.estado = 'Activo'
        AND u.password_hash = crypt(p_password, u.password_hash)
        AND EXISTS (
			SELECT 1 FROM empleado e
            WHERE e.empleado_id = u.empleado_id AND e.estado = 'Activo')
        RETURNING u.usuario_id
    )
    SELECT v.usuario_id, v.nombre_usuario, v.rol, v.sucursal_id
    FROM v_usuario_sesion v
    JOIN ok ON ok.usuario_id = v.usuario_id;
END;
$$;

SELECT registrar_usuario('kristel.admin', 3, 'Prueba123');

SELECT * FROM login_usuario('kristel.admin', 'Prueba123');

SELECT * FROM usuario;


--- Control de cambios (bitácora)
--nueva tabla bitacora
CREATE TABLE bitacora (
    bitacora_id      BIGSERIAL PRIMARY KEY,
    fecha_hora       TIMESTAMPTZ NOT NULL DEFAULT now(),
    usuario_id       INT REFERENCES usuario(usuario_id),
    tabla            TEXT NOT NULL,
    operacion        TEXT NOT NULL CHECK (operacion IN ('INSERT','UPDATE','DELETE')),
    datos_anteriores JSONB,
    datos_nuevos     JSONB
);

CREATE INDEX idx_bitacora_tabla_fecha ON bitacora (tabla, fecha_hora DESC);
CREATE INDEX idx_bitacora_usuario     ON bitacora (usuario_id);


CREATE OR REPLACE FUNCTION fn_bitacora()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_usuario INT := NULLIF(current_setting('app.usuario_id', true), '')::INT;
    v_old JSONB;
    v_new JSONB;
BEGIN
    IF TG_OP IN ('UPDATE','DELETE') THEN v_old := to_jsonb(OLD); END IF;
    IF TG_OP IN ('INSERT','UPDATE') THEN v_new := to_jsonb(NEW); END IF;

    IF TG_TABLE_NAME = 'usuario' THEN
        v_old := v_old - 'password_hash';
        v_new := v_new - 'password_hash';
    END IF;

    INSERT INTO bitacora (usuario_id, tabla, operacion, datos_anteriores, datos_nuevos)
    VALUES (v_usuario, TG_TABLE_NAME, TG_OP, v_old, v_new);

    RETURN NULL;  
END;
$$;

DO $$
DECLARE t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'cliente','empleado','reserva','reserva_mesa','mesa',
        'ingrediente','lote_inventario','movimiento_inventario',
        'platillo','detalle_receta','orden','detalle_orden',
        'factura','detalle_factura'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER trg_bitacora
            AFTER INSERT OR UPDATE OR DELETE ON %I
            FOR EACH ROW EXECUTE FUNCTION fn_bitacora()', t);
    END LOOP;
END $$;

CREATE TRIGGER trg_bitacora
AFTER INSERT OR DELETE OR UPDATE OF empleado_id, nombre_usuario, password_hash, estado
ON usuario
FOR EACH ROW EXECUTE FUNCTION fn_bitacora();


BEGIN;
SELECT set_config('app.usuario_id', '1', true);
UPDATE empleado SET estado = 'Inactivo' WHERE empleado_id = 2;
COMMIT;

SELECT bitacora_id, usuario_id, tabla, operacion, datos_anteriores->>'estado' AS antes, datos_nuevos->>'estado' AS despues
FROM bitacora ORDER BY bitacora_id DESC;