"""Arranque seguro y repetible de la alternativa Docker."""
import os
import unittest
from unittest.mock import MagicMock, patch

import server
from docker import entrypoint


class DockerStartupTests(unittest.TestCase):
    def prepare(self, populated=False, seed='true'):
        conn = MagicMock()
        conn.execute.return_value.fetchone.return_value = {'populated': populated}
        with patch.dict(os.environ, {'AUREA_SEED': seed}), \
                patch('server.initialize') as initialize, \
                patch('server.connection') as connection, \
                patch('seed.seed_data') as load:
            connection.return_value.__enter__.return_value = conn
            entrypoint.prepare_database()
            return initialize.call_count, load.call_count, connection.call_count

    def test_empty_database_loads_examples(self):
        self.assertEqual(self.prepare(), (1, 1, 1))

    def test_restart_preserves_existing_data(self):
        self.assertEqual(self.prepare(populated=True), (1, 0, 1))

    def test_seed_can_be_disabled(self):
        self.assertEqual(self.prepare(seed='false'), (1, 0, 0))

    def test_invalid_setting_does_not_modify_database(self):
        with self.assertRaises(server.ValidationError):
            self.prepare(seed='invalid')

    def test_initialized_database_starts_without_removed_migration(self):
        conn = MagicMock()
        conn.execute.return_value.fetchone.side_effect = [{'name': 'cliente'}, {'ready': True}]
        with patch('server.connection') as connection, patch.object(server.Path, 'is_file', return_value=False):
            connection.return_value.__enter__.return_value = conn
            server.initialize()
        self.assertEqual(conn.execute.call_count, 4)

    def test_missing_migration_rejects_incomplete_database(self):
        conn = MagicMock()
        conn.execute.return_value.fetchone.side_effect = [{'name': 'cliente'}, {'ready': False}]
        with patch('server.connection') as connection, patch.object(server.Path, 'is_file', return_value=False):
            connection.return_value.__enter__.return_value = conn
            with self.assertRaisesRegex(server.ValidationError, '002_aplicacion.sql'):
                server.initialize()

    def test_available_migration_is_still_applied(self):
        conn = MagicMock()
        conn.execute.return_value.fetchone.return_value = {'name': 'cliente'}
        with patch('server.connection') as connection, \
                patch.object(server.Path, 'is_file', return_value=True), \
                patch.object(server.Path, 'read_text', return_value='SELECT 1'):
            connection.return_value.__enter__.return_value = conn
            server.initialize()
        conn.execute.assert_any_call('SELECT 1', prepare=False)

    def test_explicit_database_connection_is_preserved(self):
        with patch.dict(os.environ, {'DATABASE_URL': 'existing-connection'}):
            entrypoint.configure_database()
            self.assertEqual(os.environ['DATABASE_URL'], 'existing-connection')

    def test_connection_handles_password_special_characters(self):
        try:
            from psycopg.conninfo import conninfo_to_dict
        except ImportError:
            self.skipTest('Requiere el controlador de requirements.txt.')
        with patch.dict(os.environ, {
            'PGHOST': 'db', 'PGPORT': '5432', 'PGDATABASE': 'PRF_Aurea',
            'PGUSER': 'aurea', 'PGPASSWORD': "prueba @:/' clave",
        }, clear=True):
            entrypoint.configure_database()
            parsed = conninfo_to_dict(os.environ['DATABASE_URL'])
            self.assertEqual(parsed['password'], "prueba @:/' clave")
            self.assertEqual(parsed['host'], 'db')

    def test_docker_listens_on_container_interface(self):
        with patch.dict(os.environ, {'HOST': '0.0.0.0', 'PORT': '8123'}), \
                patch('server.ThreadingHTTPServer') as http:
            server.serve()
            http.assert_called_once_with(('0.0.0.0', 8123), server.Handler)
            http.return_value.serve_forever.assert_called_once()

    def test_local_default_remains_loopback(self):
        with patch.dict(os.environ, {}, clear=True), patch('server.ThreadingHTTPServer') as http:
            server.serve()
            http.assert_called_once_with(('127.0.0.1', 8000), server.Handler)

    def test_health_reports_database_unavailable(self):
        handler = object.__new__(server.Handler)
        handler.path = '/api/health'
        handler.send_json = MagicMock()
        with patch.dict(os.environ, {'DATABASE_URL': 'test'}), \
                patch('server.connection', side_effect=OSError('Not available')):
            handler.do_GET()
        handler.send_json.assert_called_once_with(
            {'status': 'error', 'error': 'database_unavailable'}, 503)


if __name__ == '__main__':
    unittest.main()
