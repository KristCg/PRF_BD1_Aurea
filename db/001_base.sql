--
-- PostgreSQL database dump
--

\restrict UvFIw2RfrI5TQhIGJUArIiRXMOyHd3XzoqvTex5rbjbdMerTw046iejeTIWtQYR

-- Dumped from database version 17.10
-- Dumped by pg_dump version 17.10

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: cliente; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cliente (
    cliente_id integer NOT NULL,
    nit character varying(13) DEFAULT 'CF'::character varying,
    nombre character varying(30),
    apellido character varying(30),
    telefono smallint
);


--
-- Name: cliente_cliente_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.cliente_cliente_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cliente_cliente_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.cliente_cliente_id_seq OWNED BY public.cliente.cliente_id;


--
-- Name: detalle_receta; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.detalle_receta (
    platillo_id integer NOT NULL,
    ingrediente_id integer NOT NULL,
    cantidad numeric(6,3) NOT NULL,
    unidad_medida character varying(4) NOT NULL,
    CONSTRAINT detalle_receta_cantidad_check CHECK ((cantidad > (0)::numeric))
);


--
-- Name: empleado; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.empleado (
    empleado_id integer NOT NULL,
    nombre_empleado character varying(30) NOT NULL,
    apellido character varying(30) NOT NULL,
    fecha_contratacion date DEFAULT CURRENT_DATE NOT NULL,
    rol_id integer NOT NULL,
    sucursal_id integer NOT NULL,
    estado text DEFAULT 'Activo'::text,
    CONSTRAINT empleado_estado_check CHECK ((estado = ANY (ARRAY['Activo'::text, 'Inactivo'::text])))
);


--
-- Name: empleado_empleado_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.empleado_empleado_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: empleado_empleado_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.empleado_empleado_id_seq OWNED BY public.empleado.empleado_id;


--
-- Name: ingrediente; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ingrediente (
    ingrediente_id integer NOT NULL,
    nombre_ingrediente character varying(30) NOT NULL,
    unidad_medida character varying(4) NOT NULL,
    stock_minimo numeric(7,3) DEFAULT NULL::numeric
);


--
-- Name: ingrediente_ingrediente_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ingrediente_ingrediente_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ingrediente_ingrediente_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ingrediente_ingrediente_id_seq OWNED BY public.ingrediente.ingrediente_id;


--
-- Name: lote_inventario; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lote_inventario (
    lote_id character varying(13) NOT NULL,
    ingrediente_id integer NOT NULL,
    sucursal_id integer NOT NULL,
    fecha_ingreso date DEFAULT CURRENT_DATE NOT NULL,
    fecha_vencimiento date NOT NULL,
    cantidad_disponible smallint
);


--
-- Name: mesa; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mesa (
    mesa_id smallint NOT NULL,
    sucursal_id integer NOT NULL,
    capacidad smallint NOT NULL,
    estado text DEFAULT 'Disponible'::text NOT NULL,
    CONSTRAINT mesa_estado_check CHECK ((estado = ANY (ARRAY['Disponible'::text, 'Ocupada'::text, 'Reservada'::text])))
);


--
-- Name: movimiento_inventario; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.movimiento_inventario (
    movimiento_id integer NOT NULL,
    lote_id character varying(13) NOT NULL,
    empleado_id integer NOT NULL,
    fecha_hora timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    tipo_movimiento text DEFAULT 'Entrada'::text,
    cantidad smallint,
    motivo character varying(50),
    CONSTRAINT movimiento_inventario_cantidad_check CHECK ((cantidad > 0)),
    CONSTRAINT movimiento_inventario_tipo_movimiento_check CHECK ((tipo_movimiento = ANY (ARRAY['Entrada'::text, 'Salida'::text, 'Merma'::text, 'Ajuste'::text])))
);


--
-- Name: movimiento_inventario_movimiento_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.movimiento_inventario_movimiento_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: movimiento_inventario_movimiento_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.movimiento_inventario_movimiento_id_seq OWNED BY public.movimiento_inventario.movimiento_id;


--
-- Name: platillo; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.platillo (
    platillo_id integer NOT NULL,
    nombre_platillo character varying(50) NOT NULL,
    precio numeric(5,2) NOT NULL,
    categoria character varying(15) NOT NULL
);


--
-- Name: platillo_platillo_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.platillo_platillo_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: platillo_platillo_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.platillo_platillo_id_seq OWNED BY public.platillo.platillo_id;


--
-- Name: reserva; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reserva (
    reserva_id integer NOT NULL,
    cliente_id integer NOT NULL,
    sucursal_id integer NOT NULL,
    fecha_reserva date DEFAULT CURRENT_DATE,
    hora_reserva time without time zone NOT NULL,
    estado text DEFAULT 'Pendiente'::text,
    personas smallint NOT NULL,
    CONSTRAINT reserva_estado_check CHECK ((estado = ANY (ARRAY['Pendiente'::text, 'Confirmada'::text, 'Cancelada'::text, 'Completada'::text]))),
    CONSTRAINT reserva_personas_check CHECK ((personas > 0))
);


--
-- Name: reserva_mesa; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reserva_mesa (
    reserva_id integer NOT NULL,
    mesa_id integer NOT NULL,
    sucursal_id integer NOT NULL
);


--
-- Name: reserva_reserva_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.reserva_reserva_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: reserva_reserva_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.reserva_reserva_id_seq OWNED BY public.reserva.reserva_id;


--
-- Name: rol; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rol (
    rol_id integer NOT NULL,
    rol character varying(30) NOT NULL
);


--
-- Name: rol_rol_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.rol_rol_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: rol_rol_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.rol_rol_id_seq OWNED BY public.rol.rol_id;


--
-- Name: sucursal; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sucursal (
    sucursal_id integer NOT NULL,
    nombre_sucursal character varying(15) NOT NULL,
    telefono character varying(15) NOT NULL,
    dirreccion character varying(100) NOT NULL,
    capacidad smallint NOT NULL
);


--
-- Name: sucursal_sucursal_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sucursal_sucursal_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sucursal_sucursal_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sucursal_sucursal_id_seq OWNED BY public.sucursal.sucursal_id;


--
-- Name: cliente cliente_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cliente ALTER COLUMN cliente_id SET DEFAULT nextval('public.cliente_cliente_id_seq'::regclass);


--
-- Name: empleado empleado_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.empleado ALTER COLUMN empleado_id SET DEFAULT nextval('public.empleado_empleado_id_seq'::regclass);


--
-- Name: ingrediente ingrediente_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingrediente ALTER COLUMN ingrediente_id SET DEFAULT nextval('public.ingrediente_ingrediente_id_seq'::regclass);


--
-- Name: movimiento_inventario movimiento_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimiento_inventario ALTER COLUMN movimiento_id SET DEFAULT nextval('public.movimiento_inventario_movimiento_id_seq'::regclass);


--
-- Name: platillo platillo_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platillo ALTER COLUMN platillo_id SET DEFAULT nextval('public.platillo_platillo_id_seq'::regclass);


--
-- Name: reserva reserva_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserva ALTER COLUMN reserva_id SET DEFAULT nextval('public.reserva_reserva_id_seq'::regclass);


--
-- Name: rol rol_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rol ALTER COLUMN rol_id SET DEFAULT nextval('public.rol_rol_id_seq'::regclass);


--
-- Name: sucursal sucursal_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sucursal ALTER COLUMN sucursal_id SET DEFAULT nextval('public.sucursal_sucursal_id_seq'::regclass);


--
-- Name: cliente cliente_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cliente
    ADD CONSTRAINT cliente_pkey PRIMARY KEY (cliente_id);


--
-- Name: detalle_receta detalle_receta_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.detalle_receta
    ADD CONSTRAINT detalle_receta_pkey PRIMARY KEY (platillo_id, ingrediente_id);


--
-- Name: empleado empleado_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.empleado
    ADD CONSTRAINT empleado_pkey PRIMARY KEY (empleado_id);


--
-- Name: ingrediente ingrediente_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingrediente
    ADD CONSTRAINT ingrediente_pkey PRIMARY KEY (ingrediente_id);


--
-- Name: lote_inventario lote_inventario_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lote_inventario
    ADD CONSTRAINT lote_inventario_pkey PRIMARY KEY (lote_id);


--
-- Name: mesa mesa_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mesa
    ADD CONSTRAINT mesa_pkey PRIMARY KEY (mesa_id, sucursal_id);


--
-- Name: movimiento_inventario movimiento_inventario_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimiento_inventario
    ADD CONSTRAINT movimiento_inventario_pkey PRIMARY KEY (movimiento_id);


--
-- Name: platillo platillo_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platillo
    ADD CONSTRAINT platillo_pkey PRIMARY KEY (platillo_id);


--
-- Name: reserva_mesa reserva_mesa_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserva_mesa
    ADD CONSTRAINT reserva_mesa_pkey PRIMARY KEY (reserva_id, mesa_id, sucursal_id);


--
-- Name: reserva reserva_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserva
    ADD CONSTRAINT reserva_pkey PRIMARY KEY (reserva_id);


--
-- Name: reserva reserva_reserva_id_sucursal_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserva
    ADD CONSTRAINT reserva_reserva_id_sucursal_id_key UNIQUE (reserva_id, sucursal_id);


--
-- Name: rol rol_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rol
    ADD CONSTRAINT rol_pkey PRIMARY KEY (rol_id);


--
-- Name: sucursal sucursal_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sucursal
    ADD CONSTRAINT sucursal_pkey PRIMARY KEY (sucursal_id);


--
-- Name: detalle_receta detalle_receta_ingrediente_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.detalle_receta
    ADD CONSTRAINT detalle_receta_ingrediente_id_fkey FOREIGN KEY (ingrediente_id) REFERENCES public.ingrediente(ingrediente_id);


--
-- Name: detalle_receta detalle_receta_platillo_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.detalle_receta
    ADD CONSTRAINT detalle_receta_platillo_id_fkey FOREIGN KEY (platillo_id) REFERENCES public.platillo(platillo_id);


--
-- Name: empleado empleado_rol_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.empleado
    ADD CONSTRAINT empleado_rol_id_fkey FOREIGN KEY (rol_id) REFERENCES public.rol(rol_id);


--
-- Name: empleado empleado_sucursal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.empleado
    ADD CONSTRAINT empleado_sucursal_id_fkey FOREIGN KEY (sucursal_id) REFERENCES public.sucursal(sucursal_id);


--
-- Name: lote_inventario lote_inventario_ingrediente_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lote_inventario
    ADD CONSTRAINT lote_inventario_ingrediente_id_fkey FOREIGN KEY (ingrediente_id) REFERENCES public.ingrediente(ingrediente_id);


--
-- Name: lote_inventario lote_inventario_sucursal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lote_inventario
    ADD CONSTRAINT lote_inventario_sucursal_id_fkey FOREIGN KEY (sucursal_id) REFERENCES public.sucursal(sucursal_id);


--
-- Name: mesa mesa_sucursal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mesa
    ADD CONSTRAINT mesa_sucursal_id_fkey FOREIGN KEY (sucursal_id) REFERENCES public.sucursal(sucursal_id);


--
-- Name: movimiento_inventario movimiento_inventario_empleado_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimiento_inventario
    ADD CONSTRAINT movimiento_inventario_empleado_id_fkey FOREIGN KEY (empleado_id) REFERENCES public.empleado(empleado_id);


--
-- Name: movimiento_inventario movimiento_inventario_lote_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimiento_inventario
    ADD CONSTRAINT movimiento_inventario_lote_id_fkey FOREIGN KEY (lote_id) REFERENCES public.lote_inventario(lote_id);


--
-- Name: reserva reserva_cliente_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserva
    ADD CONSTRAINT reserva_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES public.cliente(cliente_id);


--
-- Name: reserva_mesa reserva_mesa_mesa_id_sucursal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserva_mesa
    ADD CONSTRAINT reserva_mesa_mesa_id_sucursal_id_fkey FOREIGN KEY (mesa_id, sucursal_id) REFERENCES public.mesa(mesa_id, sucursal_id);


--
-- Name: reserva_mesa reserva_mesa_reserva_id_sucursal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserva_mesa
    ADD CONSTRAINT reserva_mesa_reserva_id_sucursal_id_fkey FOREIGN KEY (reserva_id, sucursal_id) REFERENCES public.reserva(reserva_id, sucursal_id);


--
-- Name: reserva reserva_sucursal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserva
    ADD CONSTRAINT reserva_sucursal_id_fkey FOREIGN KEY (sucursal_id) REFERENCES public.sucursal(sucursal_id);


--
-- PostgreSQL database dump complete
--

\unrestrict UvFIw2RfrI5TQhIGJUArIiRXMOyHd3XzoqvTex5rbjbdMerTw046iejeTIWtQYR

