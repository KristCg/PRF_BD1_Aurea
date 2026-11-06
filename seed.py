"""Carga los scripts oficiales del catálogo y la demostración de Áurea."""
import argparse
import datetime as dt

import server


def execute_script(conn, filename):
    source = (server.ROOT / 'db' / filename).read_text(encoding='utf-8')
    # Las instrucciones de psql no forman parte del SQL.
    source = '\n'.join(line for line in source.splitlines() if not line.lstrip().startswith('\\'))
    conn.execute(source, prepare=False)


def create_schema(conn):
    for filename in ('01_schema.sql', '02_funciones.sql', '03_vistas.sql', '04_indices.sql'):
        execute_script(conn, filename)


def seed_data():
    with server.connection() as conn:
        conn.execute('SELECT pg_advisory_xact_lock(731805)')
        for table in ('cliente', 'usuario', 'sucursal', 'rol', 'ingrediente', 'platillo'):
            populated = conn.execute(f'SELECT EXISTS (SELECT 1 FROM {table}) AS populated').fetchone()['populated']
            server.require(not populated, f'La carga exige tablas vacías: {table} contiene datos.')
        for filename in ('05_seed_catalogo.sql', '06_seed_demo.sql', '07_historial_clientes.sql'):
            execute_script(conn, filename)
        server.initialize_ui(conn)
    print('Catálogo y demostración cargados desde los scripts 05, 06 y 07.', flush=True)


def replace_demo():
    """Archiva el esquema anterior y activa la carga completa en una transacción."""
    from psycopg import sql

    backup = 'respaldo_ui_' + dt.datetime.now(dt.timezone.utc).strftime('%Y%m%d_%H%M%S')
    with server.connection() as conn:
        conn.execute('SELECT pg_advisory_xact_lock(731805)')
        conn.execute(sql.SQL('ALTER SCHEMA public RENAME TO {}').format(sql.Identifier(backup)))
        conn.execute('CREATE SCHEMA public')
        conn.execute('SET search_path TO public')
        if conn.execute("SELECT 1 FROM pg_extension WHERE extname='pgcrypto'").fetchone():
            conn.execute('ALTER EXTENSION pgcrypto SET SCHEMA public')
        create_schema(conn)
        for filename in ('05_seed_catalogo.sql', '06_seed_demo.sql', '07_historial_clientes.sql'):
            execute_script(conn, filename)
        server.initialize_ui(conn)
    server.ensure_initial_admin()
    print(f'Carga completa activada. Datos anteriores conservados en el esquema {backup}.', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--replace-demo', action='store_true')
    args = parser.parse_args()
    from docker.entrypoint import configure_database
    configure_database()
    if args.replace_demo:
        replace_demo()
    else:
        server.initialize(seed=True)
        server.ensure_initial_admin()
