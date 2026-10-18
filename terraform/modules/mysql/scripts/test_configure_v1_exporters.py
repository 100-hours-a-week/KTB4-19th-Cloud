import importlib.util
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch, MagicMock

sys.path.insert(0, str(Path(__file__).parent))
import configure_v1_exporters as v1


class V1ExporterTests(unittest.TestCase):
    def test_password_round_trip(self):
        for password in ['example-not-secret', "quote'and\"double", r'back\slash', 'a #; b']:
            text = v1.common.render_config(password).replace('host=127.0.0.1', 'host=mysql')
            self.assertEqual(v1.parse_config(text), password)

    def test_wrong_host_rejected(self):
        with self.assertRaises(v1.SafeError):
            v1.parse_config(v1.common.render_config('example'))

    def test_account_preserved(self):
        with patch.object(v1, 'mysql', return_value='%') as query, patch.object(v1, 'verify_account'):
            self.assertFalse(v1.ensure_account('example'))
            query.assert_called_once()

    def test_other_host_rejected(self):
        with patch.object(v1, 'mysql', return_value='localhost') as query:
            with self.assertRaises(v1.SafeError):
                v1.ensure_account('example')
            query.assert_called_once()

    def test_readonly_rejected(self):
        with patch.object(v1, 'mysql', side_effect=['', '1\t1']) as query:
            with self.assertRaises(v1.SafeError):
                v1.ensure_account('example')
            self.assertEqual(query.call_count, 2)

    def test_exact_grants(self):
        with patch.object(v1, 'mysql', side_effect=['mysqld_exporter@%', 'N\t3',
                'GRANT SELECT, PROCESS, REPLICATION CLIENT ON *.* TO `mysqld_exporter`@`%`']):
            v1.verify_account('example')

    def test_extra_grants_rejected(self):
        with patch.object(v1, 'mysql', side_effect=['mysqld_exporter@%', 'N\t3',
                'GRANT ALL PRIVILEGES ON *.* TO `mysqld_exporter`@`%`']):
            with self.assertRaises(v1.SafeError):
                v1.verify_account('example')

    def test_compose_scope(self):
        config = v1.compose_config('10.0.1.239')
        self.assertEqual(set(config['services']), {'mysql-exporter', 'node-exporter'})
        self.assertTrue(config['networks']['service-tier']['external'])
        for service in config['services'].values():
            self.assertNotIn('depends_on', service)
        self.assertEqual(config['services']['mysql-exporter']['ports'], ['10.0.1.239:9104:9104'])

    def test_existing_file_not_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory, 'config')
            target.write_text('original')
            with self.assertRaises(v1.SafeError):
                v1.exclusive_file(target, 'new', 0o600)
            self.assertEqual(target.read_text(), 'original')

    def test_symlink_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory, 'link')
            target.symlink_to(Path(directory, 'missing'))
            with self.assertRaises(v1.SafeError):
                v1.exclusive_file(target, 'new', 0o600)

    def test_existing_exporters_no_compose_up(self):
        with patch.object(v1, 'exclusive_file'), patch.object(v1.common, 'command') as command:
            self.assertEqual(v1.ensure_exporters('10.0.1.124', dict.fromkeys(v1.IMAGES)), [])
            self.assertEqual(command.call_count, 1)
            self.assertEqual(command.call_args.args[0][-2:], ['config', '--quiet'])

    def test_missing_exporters_only(self):
        with patch.object(v1, 'exclusive_file'), patch.object(v1.common, 'command') as command:
            self.assertEqual(v1.ensure_exporters('10.0.1.239', {'mysql-exporter': 'id'}), ['node-exporter'])
            args = command.call_args.args[0]
            self.assertIn('--no-deps', args)
            self.assertIn('--no-recreate', args)
            self.assertEqual(args[-1], 'node-exporter')

    def test_root_password_not_in_args(self):
        with patch.object(v1, 'inspect', return_value={'Config': {'Env': ['MYSQL_ROOT_PASSWORD=example']}}), \
                patch.object(v1.common, 'command') as command:
            v1.mysql('SELECT 1;')
            self.assertNotIn('example', ' '.join(command.call_args.args[0]))
            self.assertEqual(command.call_args.kwargs['env']['MYSQL_PWD'], 'example')


if __name__ == '__main__':
    unittest.main()
