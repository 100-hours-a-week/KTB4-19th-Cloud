import copy
import unittest
from unittest.mock import patch
import configure_migration_accounts as m

ACCOUNT = {'kind':'app','user':'zipsai_app','host':'%','parameter':'/zipsai/prod/mysql-v2/password'}
PLAN = {'schema_version':1,'engine':'native','instance_id':'i-0123456789abcdef0','server_id':101,'accounts':[ACCOUNT]}

class Tests(unittest.TestCase):
    def test_native_plan(self):
        self.assertEqual(m.validate_plan(copy.deepcopy(PLAN)), PLAN)

    def test_reject_other_environment_secret(self):
        plan = copy.deepcopy(PLAN)
        plan['accounts'][0]['parameter'] = '/zipsai/staging/mysql/password'
        with self.assertRaises(m.SafeError): m.validate_plan(plan)

    def test_reject_root_account(self):
        plan = copy.deepcopy(PLAN)
        plan['accounts'][0]['user'] = 'root'
        with self.assertRaises(m.SafeError): m.validate_plan(plan)

    def test_reject_app_on_source(self):
        plan = copy.deepcopy(PLAN)
        plan['engine'] = 'docker'
        with self.assertRaises(m.SafeError): m.validate_plan(plan)

    def test_replication_host_cannot_be_wildcard(self):
        plan = copy.deepcopy(PLAN)
        plan['accounts'][0].update(kind='replication',user='zipsai_repl',parameter='/zipsai/prod/mysql-v2/replication-password')
        with self.assertRaises(m.SafeError): m.validate_plan(plan)

    def test_existing_account_not_modified(self):
        with patch.object(m,'existing_account',return_value=True), patch.object(m,'verify_grants') as verify, patch.object(m,'mysql') as sql:
            self.assertFalse(m.ensure_account(PLAN,ACCOUNT,'not-a-real-secret'))
            sql.assert_not_called()
            verify.assert_called_once()

    def test_readonly_creation_rejected(self):
        with patch.object(m,'existing_account',return_value=False), patch.object(m,'mysql',return_value='1\t1') as sql:
            with self.assertRaises(m.SafeError): m.ensure_account(PLAN,ACCOUNT,'not-a-real-secret')
            self.assertEqual(sql.call_count,1)

    def test_create_locally_without_rotation(self):
        with patch.object(m,'existing_account',return_value=False), patch.object(m,'mysql',side_effect=['0\t0','']) as sql, patch.object(m,'verify_grants'):
            self.assertTrue(m.ensure_account(PLAN,ACCOUNT,"quote'back\\slash"))
            query = sql.call_args_list[1].args[1]
            self.assertIn('SET SESSION sql_log_bin=0',query)
            self.assertIn("quote''back\\slash",query)
            self.assertNotIn('ALTER USER',query)
            self.assertNotIn('SET GLOBAL',query)

    def test_grants_match(self):
        grants = 'GRANT USAGE ON *.* TO `zipsai_app`@`%`\nGRANT ' + ', '.join(sorted(m.APP_PRIVILEGES)) + ' ON `zipsai`.* TO `zipsai_app`@`%`'
        with patch.object(m,'mysql',side_effect=['N',grants]):m.verify_grants(PLAN,ACCOUNT)

    def test_global_privileges_rejected(self):
        with patch.object(m,'mysql',side_effect=['N','GRANT ALL PRIVILEGES ON *.* TO `zipsai_app`@`%`']):
            with self.assertRaises(m.SafeError):m.verify_grants(PLAN,ACCOUNT)

    def test_locked_account_rejected(self):
        with patch.object(m,'mysql',return_value='Y'):
            with self.assertRaises(m.SafeError):m.verify_grants(PLAN,ACCOUNT)

if __name__ == '__main__':unittest.main()
