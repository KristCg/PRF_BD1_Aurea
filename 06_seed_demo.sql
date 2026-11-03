-- =====================================================================
-- Cafeteria AUREA · CC3088 Base de Datos 1 · Proyecto No. 2
-- 06 · SEED DE DEMOSTRACION
--
-- Clientes, reservas, inventario y ventas.
--
-- TODAS las fechas son relativas a CURRENT_DATE. Nunca escribir una
-- fecha fija aqui: el dia de la presentacion las reservas tienen que
-- seguir cayendo en pasado y futuro por si solas, y las caducidades
-- tienen que seguir disparando alertas.
--
-- Requiere 01, 02, 03, 04 y 05.
-- =====================================================================

SET client_encoding = 'UTF8';

-- La bitacora registra quien hizo cada cambio. Durante la carga el
-- responsable es el proceso de carga, no una persona.
SET aurea.usuario = 'carga_inicial';


-- ---------------------------------------------------------------------
-- 1. Clientes
-- ---------------------------------------------------------------------
INSERT INTO cliente (nit, nombre, apellido, telefono) VALUES
 ('CF',        'Mariana',  'Gudiel',     '4512-8830'),
 ('2345678-9', 'Rodrigo',  'Castillo',   '5588-1204'),
 ('CF',        'Alejandra','Mejía',      '4120-7765'),
 ('8765432-1', 'Luis',     'Barrientos', '5903-4412'),
 ('CF',        'Sofía',    'Ramírez',    '4477-9015'),
 ('CF',        'Diego',    'Paz',        '5612-3387'),
 ('1122334-5', 'Valeria',  'Ortiz',      '4890-2256'),
 ('CF',        'Andrés',   'Villagrán',  '5234-6671'),
 ('CF',        'Camila',   'Solares',    '4765-1193'),
 ('9988776-6', 'Javier',   'Monzón',     '5098-7724'),
 ('CF',        'Daniela',  'Recinos',    '4331-5580'),
 ('CF',        'Pablo',    'Arriaga',    '5471-2298'),
 ('5544332-2', 'Gabriela', 'Noriega',    '4009-8836'),
 ('CF',        'Emilio',   'Cabrera',    '5827-4410'),
 ('CF',        'Renata',   'Figueroa',   '4654-3302'),
 ('3366998-8', 'Sergio',   'Aguilar',    '5190-6648'),
 ('CF',        'Paula',    'Estrada',    '4283-7791'),
 ('CF',        'Marco',    'Lemus',      '5736-0059'),
 ('7788994-4', 'Isabel',   'Quintana',   '4915-2264'),
 ('CF',        'Tomás',    'Herrera',    '5340-8817'),
 ('CF',        'Lucía',    'Jiménez',    '4562-9903'),
 ('CF',        'Fernando', 'Alvarado',   '5071-3345'),
 ('6677889-9', 'Natalia',  'Contreras',  '4798-5521'),
 ('CF',        'Ricardo',  'Osorio',     '5425-1178'),
 ('CF',        'Andrea',   'Morales',    '4136-6692');

-- Clientes que no quisieron dar todos sus datos. Son normales en una
-- cafeteria y el modelo los admite: lo unico obligatorio es que quede
-- alguna forma de identificarlos.
INSERT INTO cliente (nit, nombre, apellido, telefono, correo) VALUES
 (NULL, 'Mónica',  NULL,    NULL,        NULL),          -- solo nombre de pila
 (NULL, NULL,      NULL,    '5512-4408', NULL),          -- solo telefono
 (NULL, NULL,      NULL,    NULL,        'jp@correo.gt'),-- solo correo
 ('CF', 'Esteban', NULL,    '4471-9926', NULL),          -- nombre y telefono
 (NULL, 'Karla',   'Duarte',NULL,        NULL);          -- nombre completo, sin contacto


-- ---------------------------------------------------------------------
-- 2. Preferencias declaradas  (requisito 4, alimenta el reporte iii)
-- ---------------------------------------------------------------------
INSERT INTO preferencia_cliente (cliente_id, platillo_id, nota)
SELECT c.cliente_id, p.platillo_id, n.nota
  FROM (VALUES
    (1, 13, 'Siempre pide el latte sin azúcar'),
    (1,  7, NULL),
    (2,  4, 'Término medio'),
    (3,  3, 'Vegetariana'),
    (3, 16, NULL),
    (4, 11, NULL),
    (5, 12, 'Con leche deslactosada'),
    (6,  1, NULL),
    (7,  8, 'Sin crema encima'),
    (8, 10, NULL),
    (9,  6, 'Vegetariana'),
   (10, 14, NULL),
   (11, 19, 'Con hielo extra'),
   (12,  2, NULL),
   (13,  9, NULL),
   (14, 13, NULL),
   (15,  7, 'Le celebran el cumpleaños en noviembre'),
   (16,  5, NULL),
   (17, 15, NULL),
   (18, 12, NULL),
   (19, 13, 'Cliente de la mañana'),
   (20,  1, NULL)
  ) AS n(cliente_id, platillo_id, nota)
  JOIN cliente  c ON c.cliente_id  = n.cliente_id
  JOIN platillo p ON p.platillo_id = n.platillo_id;


-- Una mesa fuera de servicio, para la demo de disponibilidad.
UPDATE mesa SET estado = 'Mantenimiento' WHERE mesa_id = 14 AND sucursal_id = 1;


-- ---------------------------------------------------------------------
-- 3. Reservas
--
-- De hace 21 dias hasta dentro de 14. Las pasadas quedan Completadas o
-- Canceladas, las futuras Pendientes o Confirmadas. Las horas se
-- concentran en desayuno, almuerzo y cena, que es lo que hace que la
-- alerta de disponibilidad llegue a Critico y Lleno en la demo.
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_dia      integer;
    v_i        integer;
    v_por_dia  integer;
    v_fecha    date;
    v_hora     time;
    v_suc      record;
    v_cliente  integer;
    v_personas smallint;
    v_duracion smallint;
    v_id       integer;
    v_estado   text;
    v_obs      varchar(200);
    v_dado     numeric;
    v_franja   numeric;
    v_min      integer;
    v_max      integer;
    v_ok       integer := 0;
    v_no       integer := 0;
BEGIN
    PERFORM setseed(0.42);
    SELECT min(cliente_id), max(cliente_id) INTO v_min, v_max FROM cliente;

    FOR v_dia IN -21..14 LOOP
        v_fecha := CURRENT_DATE + v_dia;

        FOR v_suc IN SELECT sucursal_id FROM sucursal ORDER BY 1 LOOP
            v_por_dia := CASE WHEN extract(isodow FROM v_fecha) >= 5
                              THEN 5 + floor(random()*3)::int
                              ELSE 3 + floor(random()*3)::int END;

            FOR v_i IN 1..v_por_dia LOOP
                v_franja := random();
                v_hora := CASE
                    WHEN v_franja < 0.30 THEN '08:00'::time + make_interval(mins => floor(random()*5)::int * 30)
                    WHEN v_franja < 0.65 THEN '12:00'::time + make_interval(mins => floor(random()*5)::int * 30)
                    WHEN v_franja < 0.90 THEN '18:30'::time + make_interval(mins => floor(random()*6)::int * 30)
                    ELSE                      '15:00'::time + make_interval(mins => floor(random()*6)::int * 30)
                END;

                v_cliente  := v_min + floor(random() * (v_max - v_min + 1))::int;
                v_personas := CASE WHEN random() < 0.15
                                   THEN (8 + floor(random()*7))::smallint
                                   ELSE (2 + floor(random()*5))::smallint END;
                v_duracion := (CASE WHEN v_personas >= 8 THEN 120
                                    WHEN random() < 0.7  THEN 90 ELSE 120 END)::smallint;
                v_dado := random();

                IF v_dia < 0 THEN
                    v_estado := CASE WHEN v_dado < 0.78 THEN 'Completada' ELSE 'Cancelada' END;
                    v_obs := CASE
                        WHEN v_dado < 0.10 THEN 'Pidió mesa junto a la ventana'
                        WHEN v_dado < 0.19 THEN 'Celebración de cumpleaños'
                        WHEN v_dado < 0.25 THEN 'Se quejó de la espera en barra'
                        WHEN v_dado < 0.34 THEN 'Cliente frecuente, pidió su latte de siempre'
                        WHEN v_dado < 0.41 THEN 'Reunión de trabajo, pidió zona tranquila'
                        WHEN v_dado < 0.47 THEN 'Solicitó opción vegetariana'
                        WHEN v_dado < 0.52 THEN 'No se presentó, se liberó la mesa a los 20 minutos'
                        ELSE NULL END;
                ELSE
                    v_estado := CASE WHEN v_dado < 0.6 THEN 'Confirmada' ELSE 'Pendiente' END;
                    v_obs := CASE
                        WHEN v_dado < 0.10 THEN 'Pidió mesa alejada de la entrada'
                        WHEN v_dado < 0.19 THEN 'Llega con niño pequeño, necesita silla alta'
                        WHEN v_dado < 0.26 THEN 'Avisa que puede llegar 15 minutos tarde'
                        WHEN v_dado < 0.33 THEN 'Solicitó opción sin lactosa'
                        ELSE NULL END;
                END IF;

                BEGIN
                    v_id := crear_reserva(v_cliente, v_suc.sucursal_id, v_fecha,
                                          v_hora, v_personas, v_duracion, v_obs, false);
                    IF v_estado <> 'Pendiente' THEN
                        UPDATE reserva SET estado = v_estado WHERE reserva_id = v_id;
                    END IF;
                    v_ok := v_ok + 1;
                EXCEPTION WHEN OTHERS THEN
                    v_no := v_no + 1;   -- franja sin mesa libre
                END;
            END LOOP;
        END LOOP;
    END LOOP;

    RAISE NOTICE 'Reservas creadas: %  ·  omitidas por falta de mesa: %', v_ok, v_no;
END $$;


-- Hora pico de fin de semana: llena el almuerzo de sabados y domingos
-- para que disponibilidad_dia llegue a 'Lleno'. Los rechazos de aqui
-- son la prueba de que el trigger de choque esta trabajando.
DO $$
DECLARE
    v_dia integer; v_i integer; v_fecha date; v_hora time;
    v_suc record; v_cliente integer; v_id integer;
    v_min integer; v_max integer; v_ok integer := 0; v_no integer := 0;
BEGIN
    PERFORM setseed(0.77);
    SELECT min(cliente_id), max(cliente_id) INTO v_min, v_max FROM cliente;

    FOR v_dia IN -21..14 LOOP
        v_fecha := CURRENT_DATE + v_dia;
        CONTINUE WHEN extract(isodow FROM v_fecha) < 6;

        FOR v_suc IN SELECT sucursal_id FROM sucursal ORDER BY 1 LOOP
            FOR v_i IN 1..14 LOOP
                v_hora := '12:30'::time + make_interval(mins => floor(random()*3)::int * 30);
                v_cliente := v_min + floor(random() * (v_max - v_min + 1))::int;
                BEGIN
                    v_id := crear_reserva(v_cliente, v_suc.sucursal_id, v_fecha, v_hora,
                                          (2 + floor(random()*3))::smallint,
                                          90::smallint, NULL, false);
                    UPDATE reserva
                       SET estado = CASE WHEN v_dia < 0 THEN 'Completada' ELSE 'Confirmada' END
                     WHERE reserva_id = v_id;
                    v_ok := v_ok + 1;
                EXCEPTION WHEN OTHERS THEN
                    v_no := v_no + 1;
                END;
            END LOOP;
        END LOOP;
    END LOOP;

    RAISE NOTICE 'Hora pico fin de semana: % reservas  ·  % rechazadas por falta de mesa', v_ok, v_no;
END $$;


-- ---------------------------------------------------------------------
-- 4. Ordenes, en estado Pendiente
--
-- Cada reserva completada genera una orden con su detalle. Todavia no
-- se completan: primero hay que surtir la bodega con lo que van a
-- consumir, igual que en un negocio real.
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_r      record;
    v_emp    integer;
    v_orden  integer;
    v_plat   record;
    v_lineas integer;
    v_n      integer := 0;
BEGIN
    PERFORM setseed(0.55);

    FOR v_r IN SELECT reserva_id, cliente_id, sucursal_id, personas,
                      fecha_reserva, hora_reserva
                 FROM reserva WHERE estado = 'Completada'
                ORDER BY fecha_reserva, reserva_id
    LOOP
        SELECT empleado_id INTO v_emp FROM empleado
         WHERE sucursal_id = v_r.sucursal_id AND rol_id = 2 LIMIT 1;
        IF v_emp IS NULL THEN
            SELECT empleado_id INTO v_emp FROM empleado
             WHERE sucursal_id = v_r.sucursal_id LIMIT 1;
        END IF;

        INSERT INTO orden (fecha_hora, empleado_id, sucursal_id, cliente_id, reserva_id, estado)
        VALUES (v_r.fecha_reserva + v_r.hora_reserva, v_emp, v_r.sucursal_id,
                v_r.cliente_id, v_r.reserva_id, 'Pendiente')
        RETURNING orden_id INTO v_orden;

        v_lineas := least(5, greatest(2, ceil(v_r.personas * 0.8)::int));

        FOR v_plat IN SELECT platillo_id, precio FROM platillo
                       WHERE disponible ORDER BY random() LIMIT v_lineas
        LOOP
            INSERT INTO detalle_orden (orden_id, platillo_id, cantidad, precio_unitario)
            VALUES (v_orden, v_plat.platillo_id,
                    (1 + floor(random()*2))::smallint, v_plat.precio);
        END LOOP;

        v_n := v_n + 1;
    END LOOP;

    RAISE NOTICE 'Ordenes registradas (pendientes): %', v_n;
END $$;


-- Ordenes de barra: el cliente no dio ningun dato y no se le creo
-- ficha. orden.cliente_id queda nulo y la venta se registra igual.
-- Entran al reporte de platos mas vendidos pero no al de clientes
-- frecuentes, que es justo lo correcto.
DO $$
DECLARE
    v_dia   integer;
    v_suc   record;
    v_emp   integer;
    v_orden integer;
    v_plat  record;
    v_i     integer;
    v_n     integer := 0;
BEGIN
    PERFORM setseed(0.63);

    FOR v_dia IN -21..-1 LOOP
        FOR v_suc IN SELECT sucursal_id FROM sucursal ORDER BY 1 LOOP
            CONTINUE WHEN random() < 0.45;

            SELECT empleado_id INTO v_emp FROM empleado
             WHERE sucursal_id = v_suc.sucursal_id AND rol_id = 2 LIMIT 1;
            IF v_emp IS NULL THEN
                SELECT empleado_id INTO v_emp FROM empleado
                 WHERE sucursal_id = v_suc.sucursal_id LIMIT 1;
            END IF;

            INSERT INTO orden (fecha_hora, empleado_id, sucursal_id, cliente_id, estado)
            VALUES ((CURRENT_DATE + v_dia) + '09:30'::time
                        + make_interval(mins => floor(random()*600)::int),
                    v_emp, v_suc.sucursal_id, NULL, 'Pendiente')
            RETURNING orden_id INTO v_orden;

            v_i := 1 + floor(random()*2)::int;
            FOR v_plat IN SELECT platillo_id, precio FROM platillo
                           WHERE categoria IN ('Bebida','Postre') AND disponible
                           ORDER BY random() LIMIT v_i
            LOOP
                INSERT INTO detalle_orden (orden_id, platillo_id, cantidad, precio_unitario)
                VALUES (v_orden, v_plat.platillo_id,
                        (1 + floor(random()*2))::smallint, v_plat.precio);
            END LOOP;

            v_n := v_n + 1;
        END LOOP;
    END LOOP;

    RAISE NOTICE 'Ordenes de barra sin cliente: %', v_n;
END $$;


-- ---------------------------------------------------------------------
-- 5. Inventario, dimensionado contra la demanda real
--
-- En vez de inventar cantidades al azar, se calcula cuanto va a
-- consumir cada sucursal segun las ordenes ya registradas y sus
-- recetas, y se surte eso mas un sobrante.
--
-- El sobrante es lo que decide la demo: un 20% de los insumos recibe
-- poco de mas y termina bajo el umbral del 15%, que es justo lo que
-- debe aparecer en la alerta y en el reporte iv.
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_d       record;
    v_emp     integer;
    v_dias    integer;
    v_cant    numeric(12,3);
    v_sobra   numeric;
    v_umbral  numeric;
    v_n       integer := 0;
BEGIN
    PERFORM setseed(0.31);

    FOR v_d IN
        WITH demanda AS (
            SELECT o.sucursal_id, dr.ingrediente_id,
                   sum(convertir(dr.cantidad, dr.unidad_medida, i.unidad_medida)
                       * dor.cantidad) AS necesario
              FROM orden o
              JOIN detalle_orden  dor USING (orden_id)
              JOIN detalle_receta dr  USING (platillo_id)
              JOIN ingrediente    i   ON i.ingrediente_id = dr.ingrediente_id
             GROUP BY o.sucursal_id, dr.ingrediente_id
        )
        -- CROSS JOIN para que cada sede tenga TODOS los insumos, haya
        -- o no demanda: el catalogo debe verse completo en la pantalla.
        SELECT s.sucursal_id, i.ingrediente_id, i.categoria,
               i.stock_minimo, i.stock_referencia,
               COALESCE(d.necesario, 0) AS necesario
          FROM sucursal s
         CROSS JOIN ingrediente i
          LEFT JOIN demanda d ON d.sucursal_id = s.sucursal_id
                             AND d.ingrediente_id = i.ingrediente_id
         ORDER BY s.sucursal_id, i.ingrediente_id
    LOOP
        SELECT empleado_id INTO v_emp FROM empleado
         WHERE sucursal_id = v_d.sucursal_id AND rol_id = 4 LIMIT 1;
        IF v_emp IS NULL THEN
            SELECT empleado_id INTO v_emp FROM empleado
             WHERE sucursal_id = v_d.sucursal_id LIMIT 1;
        END IF;

        v_umbral := greatest(v_d.stock_minimo, v_d.stock_referencia * 0.15);

        -- 20% de los insumos quedan bajo el umbral despues de vender
        v_sobra := CASE WHEN random() < 0.20
                        THEN v_umbral * (0.25 + random() * 0.6)
                        ELSE v_d.stock_referencia * (0.4 + random() * 0.8)
                   END;

        v_cant := round((v_d.necesario + v_sobra)::numeric, 3);
        IF v_cant <= 0 THEN v_cant := 1; END IF;

        -- Vida util por tipo de insumo. El minimo de 3 dias evita que
        -- un lote caduque antes de que las ordenes lo consuman.
        v_dias := CASE v_d.categoria
            WHEN 'Lácteos'           THEN 3  + floor(random()*7)::int
            WHEN 'Panadería'         THEN 3  + floor(random()*5)::int
            WHEN 'Frutas y verduras' THEN 4  + floor(random()*8)::int
            WHEN 'Carnes'            THEN 3  + floor(random()*6)::int
            WHEN 'Café y té'         THEN 25 + floor(random()*40)::int
            WHEN 'Bebidas'           THEN 20 + floor(random()*60)::int
            ELSE                          60 + floor(random()*180)::int
        END;

        PERFORM recibir_lote(
            'AUR-' || lpad(v_d.ingrediente_id::text,3,'0') || '-S' || v_d.sucursal_id,
            v_d.ingrediente_id, v_d.sucursal_id, v_cant,
            CURRENT_DATE + v_dias, v_emp, 'Abastecimiento de proveedor');
        v_n := v_n + 1;
    END LOOP;

    RAISE NOTICE 'Lotes recibidos: %', v_n;
END $$;


-- Un segundo lote pequeño de leche en cada sede, que caduca manana.
-- Sirve para demostrar FEFO: el descuento por venta consume PRIMERO
-- este y no el lote grande.
INSERT INTO lote_inventario
    (lote_id, ingrediente_id, sucursal_id, fecha_ingreso, fecha_vencimiento, cantidad_disponible)
SELECT 'AUR-003-S' || sucursal_id || '-URG', 3, sucursal_id,
       CURRENT_DATE - 4, CURRENT_DATE + 1, 4.000
  FROM sucursal;

-- Un lote ya vencido en Cayalá: el sistema debe excluirlo del stock
-- utilizable y aceptar solo mermas sobre el.
INSERT INTO lote_inventario
    (lote_id, ingrediente_id, sucursal_id, fecha_ingreso, fecha_vencimiento, cantidad_disponible)
VALUES ('AUR-VENCIDO-S1', 4, 1, CURRENT_DATE - 12, CURRENT_DATE - 2, 6.500);


-- ---------------------------------------------------------------------
-- 6. Completar las ordenes y facturar
--
-- Aqui es donde el sistema se conecta entero: al pasar a Completada,
-- el trigger lee la receta de cada platillo, convierte g a kg y ml a L,
-- y descuenta de los lotes de esa sucursal empezando por el que vence
-- antes. Si un insumo no alcanza, la orden se queda Pendiente.
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_o         record;
    v_completas integer := 0;
    v_sin_stock integer := 0;
    v_facturas  integer := 0;
BEGIN
    FOR v_o IN SELECT orden_id, cliente_id FROM orden
                WHERE estado = 'Pendiente' ORDER BY fecha_hora, orden_id
    LOOP
        BEGIN
            UPDATE orden SET estado = 'Completada' WHERE orden_id = v_o.orden_id;
            v_completas := v_completas + 1;

            -- Con NIT real la factura lleva el nombre registrado; sin
            -- el, se emite a Consumidor Final, que es lo normal cuando
            -- el cliente no dio sus datos. Una orden de barra sin ficha
            -- de cliente se factura igual, con cliente_id nulo.
            IF v_o.cliente_id IS NULL THEN
                INSERT INTO factura (orden_id, cliente_id, nit, nombre_facturacion)
                VALUES (v_o.orden_id, NULL, 'CF', 'Consumidor Final');
            ELSE
                INSERT INTO factura (orden_id, cliente_id, nit, nombre_facturacion)
                SELECT v_o.orden_id, c.cliente_id, COALESCE(c.nit, 'CF'),
                       CASE WHEN COALESCE(c.nit,'CF') = 'CF'
                            THEN 'Consumidor Final'
                            ELSE nombre_cliente(c.cliente_id, c.nombre, c.apellido) END
                  FROM cliente c WHERE c.cliente_id = v_o.cliente_id;
            END IF;
            v_facturas := v_facturas + 1;
        EXCEPTION WHEN OTHERS THEN
            v_sin_stock := v_sin_stock + 1;
        END;
    END LOOP;

    RAISE NOTICE 'Ordenes completadas: %  ·  facturas: %  ·  sin insumos: %',
        v_completas, v_facturas, v_sin_stock;
END $$;


-- ---------------------------------------------------------------------
-- 7. Mermas, para que el historial de inventario tenga de todo
-- ---------------------------------------------------------------------
DO $$
DECLARE v_l record; v_emp integer; v_n integer := 0;
BEGIN
    PERFORM setseed(0.19);
    FOR v_l IN SELECT l.lote_id, l.sucursal_id, l.cantidad_disponible
                 FROM lote_inventario l
                WHERE l.cantidad_disponible > 1 AND l.fecha_vencimiento >= CURRENT_DATE
                ORDER BY random() LIMIT 12
    LOOP
        SELECT empleado_id INTO v_emp FROM empleado
         WHERE sucursal_id = v_l.sucursal_id ORDER BY rol_id DESC LIMIT 1;
        BEGIN
            INSERT INTO movimiento_inventario (lote_id, tipo_movimiento, cantidad, empleado_id, motivo)
            VALUES (v_l.lote_id, 'Merma', round(v_l.cantidad_disponible * 0.05, 3),
                    v_emp, 'Producto dañado en bodega');
            v_n := v_n + 1;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END LOOP;
    RAISE NOTICE 'Mermas registradas: %', v_n;
END $$;


-- =====================================================================
-- 7. VERIFICACION
-- =====================================================================

\echo ''
\echo '--- filas por tabla ---'
SELECT 'cliente' AS tabla, count(*) FROM cliente
UNION ALL SELECT 'reserva',               count(*) FROM reserva
UNION ALL SELECT 'reserva_mesa',          count(*) FROM reserva_mesa
UNION ALL SELECT 'orden',                 count(*) FROM orden
UNION ALL SELECT 'detalle_orden',         count(*) FROM detalle_orden
UNION ALL SELECT 'factura',               count(*) FROM factura
UNION ALL SELECT 'detalle_factura',       count(*) FROM detalle_factura
UNION ALL SELECT 'lote_inventario',       count(*) FROM lote_inventario
UNION ALL SELECT 'movimiento_inventario', count(*) FROM movimiento_inventario
UNION ALL SELECT 'bitacora',              count(*) FROM bitacora
ORDER BY 1;

\echo ''
\echo '--- integridad: ninguna mesa puede estar doble reservada (debe dar 0) ---'
SELECT count(*) AS mesas_doble_reservadas
  FROM reserva_mesa a
  JOIN reserva ra ON ra.reserva_id = a.reserva_id
  JOIN reserva_mesa b ON b.mesa_id = a.mesa_id AND b.sucursal_id = a.sucursal_id
                     AND b.reserva_id > a.reserva_id
  JOIN reserva rb ON rb.reserva_id = b.reserva_id
 WHERE ra.estado <> 'Cancelada' AND rb.estado <> 'Cancelada'
   AND ra.fecha_reserva = rb.fecha_reserva
   AND ra.hora_reserva < rb.hora_reserva + make_interval(mins => rb.duracion_min)
   AND rb.hora_reserva < ra.hora_reserva + make_interval(mins => ra.duracion_min);

\echo ''
\echo '--- integridad: la factura debe cuadrar con la orden (debe dar 0) ---'
SELECT count(*) AS facturas_descuadradas FROM (
  SELECT f.factura_id
    FROM factura f JOIN detalle_orden d ON d.orden_id = f.orden_id
   GROUP BY f.factura_id, f.total
  HAVING f.total <> sum(d.cantidad * d.precio_unitario)) t;

\echo ''
\echo '--- insumos en alerta por sucursal ---'
SELECT sucursal_id, count(*) FILTER (WHERE stock_bajo) AS bajo_umbral,
       count(*) FILTER (WHERE lotes_por_vencer > 0)    AS por_vencer,
       count(*) FILTER (WHERE stock_vencido > 0)       AS con_vencido
  FROM existencias GROUP BY 1 ORDER BY 1;
