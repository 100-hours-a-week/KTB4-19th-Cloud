"""SSM Automation handler: staging-only graceful nightly shutdown; no start/delete APIs."""
import time

import boto3
from botocore.config import Config


def shutdown(event, context):
    config = Config(retries={"mode": "standard", "max_attempts": 4},
                    connect_timeout=5, read_timeout=15)
    ec2 = boto3.client("ec2", region_name=event["region"], config=config)
    ecs = boto3.client("ecs", region_name=event["region"], config=config)
    ids = event["instance_ids"]
    cluster = event["cluster"]
    services = event["services"]
    if event["environment"] != "staging" or len(set(ids)) != 5:
        raise ValueError("Refusing unexpected environment or host count")
    if cluster.split("/")[-1] != "zipsai-staging-cluster":
        raise ValueError("Refusing non-staging ECS cluster")
    if set(services) != {"zipsai-staging-api", "zipsai-staging-worker"}:
        raise ValueError("Refusing non-staging ECS service")

    hosts = [i for r in ec2.describe_instances(InstanceIds=ids)["Reservations"]
             for i in r["Instances"]]
    expected_names = {"zipsai-staging-" + role for role in
                      ["mysql-primary", "redis", "ai-api", "embedding", "qdrant"]}
    if {i["InstanceId"] for i in hosts} != set(ids):
        raise ValueError("Missing expected staging host")
    names = set()
    for host in hosts:
        tags = {t["Key"]: t["Value"] for t in host.get("Tags", [])}
        if tags.get("Project") != "zipsai" or tags.get("Environment") != "staging":
            raise ValueError("Refusing non-staging instance")
        names.add(tags.get("Name"))
        if host["State"]["Name"] not in {"running", "stopped", "stopping"}:
            raise ValueError("Host lifecycle transition; abort and inspect")
    if names != expected_names:
        raise ValueError("Refusing unexpected staging host roles")

    def describe_services():
        response = ecs.describe_services(cluster=cluster, services=services)
        if response.get("failures") or len(response["services"]) != 2:
            raise RuntimeError("Cannot verify staging ECS services")
        return response["services"]

    describe_services()
    # Default is validation only. The schedule explicitly supplies false.
    if event.get("dry_run", "true") == "true":
        return {"dry_run": True, "validated_instances": sorted(ids), "services": services}
    if event.get("dry_run") != "false":
        raise ValueError("Invalid dry-run selection")

    tracked = set()
    for service in services:
        for page in ecs.get_paginator("list_tasks").paginate(cluster=cluster, serviceName=service):
            tracked.update(page["taskArns"])
        ecs.update_service(cluster=cluster, service=service, desiredCount=0)

    deadline = time.monotonic() + 300
    while True:
        status = describe_services()
        if any(s["desiredCount"] != 0 for s in status):
            raise RuntimeError("Concurrent restart/deploy detected; EC2 stop aborted")
        for service in services:
            for page in ecs.get_paginator("list_tasks").paginate(cluster=cluster, serviceName=service):
                tracked.update(page["taskArns"])
        stopped = True
        arns = sorted(tracked)
        for offset in range(0, len(arns), 100):
            response = ecs.describe_tasks(cluster=cluster, tasks=arns[offset:offset + 100])
            if response.get("failures"):
                raise RuntimeError("Cannot verify task stop; EC2 stop aborted")
            stopped = stopped and all(t["lastStatus"] == "STOPPED" for t in response["tasks"])
        if stopped and all(s["runningCount"] == 0 and s["pendingCount"] == 0 for s in status):
            break
        if time.monotonic() >= deadline:
            raise TimeoutError("ECS did not drain; dependencies remain powered on")
        time.sleep(10)

    # Recheck desired count immediately before stopping dependencies.
    if any(s["desiredCount"] != 0 for s in describe_services()):
        raise RuntimeError("Concurrent restart detected; EC2 stop aborted")
    running = [i["InstanceId"] for r in ec2.describe_instances(InstanceIds=ids)["Reservations"]
               for i in r["Instances"] if i["State"]["Name"] == "running"]
    if running:
        ec2.stop_instances(InstanceIds=running)  # Normal shutdown, never Force/SkipOsShutdown.
    ec2.get_waiter("instance_stopped").wait(
        InstanceIds=ids, WaiterConfig={"Delay": 10, "MaxAttempts": 18})
    return {"dry_run": False, "stopped_instances": sorted(ids), "services_desired_count": 0}
