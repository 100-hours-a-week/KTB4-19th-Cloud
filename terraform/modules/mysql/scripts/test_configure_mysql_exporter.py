import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("exporter", Path(__file__).with_name("configure_mysql_exporter.py"))
exporter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(exporter)


class ExporterTests(unittest.TestCase):
    def test_config_round_trip(self):
        for password in ["safe-Example123!", "quote'and\"double", r"back\slash", "white space #;"]:
            self.assertEqual(exporter.config_password(exporter.render_config(password)), password)

    def test_sql_literal_no_backslash_mode(self):
        self.assertEqual(exporter.sql_literal("a'b\\c"), "'a''b\\c'")

    def test_reject_bad_password(self):
        for password in ["", "x\ny", "x\ry", "x\x00y"]:
            with self.assertRaises(exporter.SafeError):
                exporter.render_config(password)

    def test_accept_exact_grants(self):
        with patch.object(exporter, "mysql", side_effect=[
            "1", "N\t3",
            "GRANT SELECT, PROCESS, REPLICATION CLIENT ON *.* TO `mysqld_exporter`@`127.0.0.1`"
        ]):
            exporter.verify_account("not-a-real-secret")

    def test_reject_extra_privileges(self):
        with patch.object(exporter, "mysql", side_effect=[
            "1", "N\t3", "GRANT ALL PRIVILEGES ON *.* TO `mysqld_exporter`@`127.0.0.1`"
        ]):
            with self.assertRaises(exporter.SafeError):
                exporter.verify_account("not-a-real-secret")

    def test_existing_account_no_mutation(self):
        with patch.object(exporter, "mysql", return_value="1") as query, \
             patch.object(exporter, "verify_account") as verify:
            self.assertFalse(exporter.ensure_account("not-a-real-secret"))
            query.assert_called_once()
            verify.assert_called_once()

    def test_readonly_creation_rejected(self):
        with patch.object(exporter, "mysql", side_effect=["0", "1\t1"]) as query:
            with self.assertRaises(exporter.SafeError):
                exporter.ensure_account("not-a-real-secret")
            self.assertEqual(query.call_count, 2)


if __name__ == "__main__":
    unittest.main()
