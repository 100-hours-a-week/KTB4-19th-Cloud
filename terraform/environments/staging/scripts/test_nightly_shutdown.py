"""Offline safety tests; no AWS calls and no third-party test dependencies."""
import importlib.util
from pathlib import Path
import sys
import types
import unittest
from unittest.mock import MagicMock, patch

sys.modules.setdefault("boto3", types.SimpleNamespace(client=None))
sys.modules.setdefault("botocore", types.ModuleType("botocore"))
sys.modules.setdefault("botocore.config", types.SimpleNamespace(Config=lambda **kw: kw))
spec = importlib.util.spec_from_file_location("nightly_shutdown", Path(__file__).with_name("nightly_shutdown.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ShutdownTests(unittest.TestCase):
    def setUp(self):
        self.roles = ["mysql-primary", "redis", "ai-api", "embedding", "qdrant"]
        self.ids = ["i-" + str(n) for n in range(5)]
        self.hosts = [{"InstanceId": id, "State": {"Name": "running"}, "Tags": [
            {"Key": "Project", "Value": "zipsai"},
            {"Key": "Environment", "Value": "staging"},
            {"Key": "Name", "Value": "zipsai-staging-" + role}]} for id, role in zip(self.ids, self.roles)]
        self.ec2, self.ecs = MagicMock(), MagicMock()
        self.ec2.describe_instances.return_value = {"Reservations": [{"Instances": self.hosts}]}
        self.ecs.describe_services.return_value = {"services": [
            {"desiredCount": 0, "runningCount": 0, "pendingCount": 0} for _ in range(2)]}
        self.ecs.get_paginator.return_value.paginate.return_value = [{"taskArns": []}]
        self.event = {"region": "ap-northeast-2", "environment": "staging",
                      "instance_ids": self.ids, "cluster": "arn:aws:ecs:region:account:cluster/zipsai-staging-cluster",
                      "services": ["zipsai-staging-api", "zipsai-staging-worker"], "dry_run": "false"}
        self.client = patch.object(module.boto3, "client", side_effect=lambda service, **kw: self.ec2 if service == "ec2" else self.ecs)
        self.client.start()
        self.addCleanup(self.client.stop)

    def test_default_dry_run_does_not_modify(self):
        self.event.pop("dry_run")
        self.assertTrue(module.shutdown(self.event, None)["dry_run"])
        self.ec2.stop_instances.assert_not_called()
        self.ecs.update_service.assert_not_called()

    def test_reject_prod_host_before_any_modification(self):
        self.hosts[0]["Tags"][1]["Value"] = "prod"
        with self.assertRaises(ValueError):
            module.shutdown(self.event, None)
        self.ecs.update_service.assert_not_called()
        self.ec2.stop_instances.assert_not_called()

    def test_reject_wrong_cluster(self):
        self.event["cluster"] = "zipsai-prod-cluster"
        with self.assertRaises(ValueError):
            module.shutdown(self.event, None)
        self.ec2.stop_instances.assert_not_called()

    def test_success_scales_two_services_and_stops_exact_hosts(self):
        self.assertFalse(module.shutdown(self.event, None)["dry_run"])
        self.assertEqual(self.ecs.update_service.call_count, 2)
        for call in self.ecs.update_service.call_args_list:
            self.assertEqual(call.kwargs["desiredCount"], 0)
        self.ec2.stop_instances.assert_called_once_with(InstanceIds=self.ids)
        self.ec2.get_waiter.return_value.wait.assert_called_once()

    def test_concurrent_restart_does_not_stop_dependencies(self):
        self.ecs.describe_services.return_value["services"][0]["desiredCount"] = 1
        with self.assertRaises(RuntimeError):
            module.shutdown(self.event, None)
        self.ec2.stop_instances.assert_not_called()

    def test_drain_timeout_does_not_stop_dependencies(self):
        self.ecs.describe_services.return_value["services"][0]["runningCount"] = 1
        with patch.object(module.time, "monotonic", side_effect=[0, 301]):
            with self.assertRaises(TimeoutError):
                module.shutdown(self.event, None)
        self.ec2.stop_instances.assert_not_called()

    def test_stopping_task_blocks_ec2_stop_until_stopped(self):
        self.ecs.get_paginator.return_value.paginate.return_value = [{"taskArns": ["task"]}]
        self.ecs.describe_tasks.side_effect = [
            {"tasks": [{"lastStatus": "STOPPING"}]}, {"tasks": [{"lastStatus": "STOPPED"}]}]
        with patch.object(module.time, "sleep") as sleep:
            module.shutdown(self.event, None)
        sleep.assert_called_once_with(10)
        self.ec2.stop_instances.assert_called_once()


if __name__ == "__main__":
    unittest.main()
