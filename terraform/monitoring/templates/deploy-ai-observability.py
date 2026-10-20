import base64
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import urllib.request

BASE = Path('/opt/zipsai-ai-observability')
IMAGE = 'grafana/alloy:v1.21.0'


def command(*args):
    subprocess.run(args, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def compose(*args):
    command('docker','compose','--project-name','zipsai-ai-observability',
            '-f',str(BASE / 'compose.yaml'),*args)


def deploy(config, compose_source):
    os.umask(0o077)
    if os.geteuid() != 0:
        raise RuntimeError('Root required')
    BASE.mkdir(mode=0o700,exist_ok=True)
    (BASE / 'data').mkdir(mode=0o700,exist_ok=True)
    command('docker','pull',IMAGE)
    with tempfile.TemporaryDirectory(prefix='validate-',dir=BASE) as temp:
        staged = Path(temp) / 'config.alloy'
        staged.write_bytes(config)
        staged.chmod(0o644)
        command('docker','run','--rm','--entrypoint','/bin/alloy',
                '-v',f'{staged}:/etc/alloy/config.alloy:ro',IMAGE,'validate','/etc/alloy/config.alloy')
    paths = [BASE / 'config.alloy',BASE / 'compose.yaml']
    old = [path.read_bytes() if path.exists() else None for path in paths]
    previous_ready = False
    try:
        with urllib.request.urlopen('http://127.0.0.1:12345/-/ready',timeout=3) as response:
            previous_ready = response.status == 200
    except Exception:
        pass
    try:
        for path, content in zip(paths,[config,compose_source]):
            path.write_bytes(content)
            path.chmod(0o600)
        compose('config','-q')
        compose('up','-d','--no-deps','--force-recreate','alloy')
        for _ in range(30):
            try:
                with urllib.request.urlopen('http://127.0.0.1:12345/-/ready',timeout=3) as response:
                    if response.status == 200:
                        print(json.dumps({'alloy_ready':True,'cloudwatch_unchanged':True}))
                        return
            except Exception:
                pass
            time.sleep(2)
        raise RuntimeError('Collector readiness failed')
    except Exception:
        if previous_ready and all(content is not None for content in old):
            for path,content in zip(paths,old):
                path.write_bytes(content)
            compose('up','-d','--no-deps','--force-recreate','alloy')
        else:
            # Only the new collector, never the AI application project or its data.
            compose('stop','alloy')
        raise


if __name__ == '__main__':
    try:
        deploy(base64.b64decode(sys.argv[1]),base64.b64decode(sys.argv[2]))
    except Exception:
        print('AI log collector deployment failed; raw output suppressed',file=sys.stderr)
        sys.exit(1)
