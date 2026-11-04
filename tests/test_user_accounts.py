"""Flujo de cuentas y permisos HTTP contra una base PostgreSQL de pruebas."""
import http.cookiejar
import json
import os
import threading
import unittest
import urllib.error
import urllib.request
import uuid

import server


class QuietHandler(server.Handler):
    def log_message(self, *args):
        pass


@unittest.skipUnless(os.getenv('AUREA_TEST_DATABASE_URL'), 'Requiere una base PostgreSQL aislada de pruebas.')
class UserAccountTests(unittest.TestCase):
    def setUp(self):
        os.environ['DATABASE_URL'] = os.environ['AUREA_TEST_DATABASE_URL']
        self.created = []
        with server.connection() as conn:
            identity = conn.execute(f"SELECT {server.USER_FIELDS} FROM usuario WHERE rol='Administrador' ORDER BY usuario_id LIMIT 1").fetchone()
            server.actor(conn, identity)
            self.admin = server.save_user(conn, {
                'nombre': 'Administrador de prueba', 'correo': uuid.uuid4().hex+'@test.local',
                'rol': 'Administrador', 'password': '1234',
            }, identity)
            self.created.append(self.admin['usuario_id'])
        self.http = server.ThreadingHTTPServer(('127.0.0.1', 0), QuietHandler)
        self.thread = threading.Thread(target=self.http.serve_forever, daemon=True)
        self.thread.start()
        self.base = f'http://127.0.0.1:{self.http.server_port}/api/'
        self.admin_client = self.client()
        self.call(self.admin_client, 'login', {'correo': self.admin['correo'], 'password': '1234'})

    def tearDown(self):
        self.http.shutdown()
        self.http.server_close()
        self.thread.join()
        with server.connection() as conn:
            conn.execute('DELETE FROM usuario WHERE usuario_id=ANY(%s)', (self.created,))
        with server.LOCK:
            for token, record in list(server.SESSIONS.items()):
                if record['user']['usuario_id'] in self.created:
                    server.SESSIONS.pop(token, None)

    def client(self):
        return urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))

    def call(self, client, path, payload=None, status=200):
        req = urllib.request.Request(self.base+path,
            data=json.dumps(payload).encode() if payload is not None else None,
            headers={'Content-Type': 'application/json'} if payload is not None else {})
        try:
            with client.open(req, timeout=10) as response:
                actual, body = response.status, json.load(response)
        except urllib.error.HTTPError as error:
            actual, body = error.code, json.load(error)
        self.assertEqual(actual, status, (path, body))
        return body

    def create_account(self, role='Gerente'):
        row = self.call(self.admin_client, 'users', {
            'nombre': 'Personal de prueba', 'correo': uuid.uuid4().hex+'@test.local',
            'rol': role, 'password': '1234',
        })
        self.created.append(row['usuario_id'])
        return row

    def changes(self, account, **changes):
        payload = {key: account[key] for key in ('usuario_id', 'nombre', 'correo', 'rol', 'empleado_id')}
        payload.update(changes)
        return payload

    def test_public_registration_is_disabled(self):
        self.call(self.client(), 'register', {
            'nombre': 'Sin permiso', 'correo': 'public@test.local', 'password': '1234', 'rol': 'Administrador',
        }, status=403)
        self.call(self.client(), 'users', {'nombre': 'Sin permiso'}, status=401)

    def test_only_admin_assigns_roles_and_changes_take_effect_immediately(self):
        account = self.create_account()
        self.assertEqual(account['rol'], 'Gerente')
        self.assertNotIn('password_hash', account)
        client = self.client()
        self.call(client, 'login', {'correo': account['correo'], 'password': '1234'})
        self.assertEqual(self.call(client, 'data')['usuarios'], [])
        self.call(client, 'users', self.changes(account, rol='Administrador'), status=403)
        account = self.call(self.admin_client, 'users', self.changes(account, rol='Mesero'))
        self.assertEqual(self.call(client, 'session')['user']['rol'], 'Mesero')
        self.call(client, 'users', self.changes(account), status=403)
        self.call(self.admin_client, 'users', self.changes(account, rol='Administrador'))
        # The same cookie now receives the current privileges, without a new login.
        users = self.call(client, 'data')['usuarios']
        self.assertTrue(users)
        self.assertTrue(all('password_hash' not in row for row in users))

    def test_password_reset_ends_other_sessions_and_empty_password_preserves_it(self):
        account = self.create_account('Mesero')
        client = self.client()
        self.call(client, 'login', {'correo': account['correo'], 'password': '1234'})
        account = self.call(self.admin_client, 'users', self.changes(account, nombre='Nombre cambiado', password=''))
        self.assertEqual(self.call(client, 'session')['user']['nombre'], 'Nombre cambiado')
        self.call(self.client(), 'login', {'correo': account['correo'], 'password': '1234'})
        self.call(self.admin_client, 'users', self.changes(account, password='5678'))
        self.call(client, 'data', status=401)
        self.call(self.client(), 'login', {'correo': account['correo'], 'password': '1234'}, status=400)
        self.call(self.client(), 'login', {'correo': account['correo'], 'password': '5678'})
        with server.connection() as conn:
            audit = conn.execute("SELECT nuevo FROM bitacora WHERE tabla='usuario' AND nuevo->>'usuario_id'=%s ORDER BY bitacora_id DESC LIMIT 1", (str(account['usuario_id']),)).fetchone()
            self.assertNotIn('password_hash', audit['nuevo'])

    def test_admin_cannot_remove_own_admin_role_or_assign_invalid_roles(self):
        self.call(self.admin_client, 'users', self.changes(self.admin, rol='Mesero'), status=400)
        self.assertEqual(self.call(self.admin_client, 'session')['user']['rol'], 'Administrador')
        account = self.create_account()
        self.call(self.admin_client, 'users', self.changes(account, rol='Superusuario'), status=400)
        self.call(self.admin_client, 'users', self.changes(account, password='123'), status=400)
        self.call(self.admin_client, 'users', self.changes(account, correo=self.admin['correo']), status=409)

    def test_startup_preserves_existing_administrators(self):
        with server.connection() as conn:
            before = conn.execute('SELECT usuario_id,password_hash FROM usuario ORDER BY usuario_id').fetchall()
        server.ensure_initial_admin()
        with server.connection() as conn:
            after = conn.execute('SELECT usuario_id,password_hash FROM usuario ORDER BY usuario_id').fetchall()
        self.assertEqual(before, after)


if __name__ == '__main__':
    unittest.main()
