"""Instala el esquema y, opcionalmente, los ejemplos antes de servir la UI."""
import os

import server

SEED_TABLES = ('cliente', 'usuario', 'sucursal', 'rol', 'ingrediente', 'platillo')


def configure_database():
    if not os.getenv('DATABASE_URL'):
        from psycopg.conninfo import make_conninfo
        # conninfo escapa contraseñas con espacios, comillas, @ o : correctamente.
        os.environ['DATABASE_URL'] = make_conninfo(
            host=os.getenv('PGHOST', 'db'),
            port=os.getenv('PGPORT', '5432'),
            dbname=os.getenv('PGDATABASE', 'PRF_Aurea'),
            user=os.getenv('PGUSER', 'aurea'),
            password=os.environ['PGPASSWORD'],
        )


def prepare_database():
    setting = os.getenv('AUREA_SEED', 'true').lower()
    server.require(setting in ('true', 'false'), 'AUREA_SEED debe ser true o false.')
    server.initialize()
    if setting == 'false':
        print('Esquema listo. Carga de ejemplo desactivada.', flush=True)
        return
    with server.connection() as conn:
        populated = any(
            conn.execute(f'SELECT EXISTS (SELECT 1 FROM {table}) AS populated').fetchone()['populated']
            for table in SEED_TABLES
        )
    if populated:
        print('Base con datos existentes: se conserva la información, sin repetir la carga.', flush=True)
    else:
        from seed import seed_data
        seed_data()


def main():
    configure_database()
    prepare_database()
    server.ensure_initial_admin()
    server.serve()


if __name__ == '__main__':
    main()
