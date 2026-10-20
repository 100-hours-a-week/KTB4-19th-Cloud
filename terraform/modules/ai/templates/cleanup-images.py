"""Remove only unused images of one dedicated AI repository; never prune globally."""
import fcntl
import json
from pathlib import Path
import re
import shlex
import subprocess
import sys


def docker(*args, optional=False):
    result = subprocess.run(['docker', *args], capture_output=True, text=True)
    if result.returncode:
        if optional:
            return None
        raise RuntimeError('Docker inspection failed; cleanup aborted')
    return result.stdout


def inspect_images(refs):
    return json.loads(docker('image', 'inspect', *refs)) if refs else []


def select_candidates(images, protected, repository):
    candidates = []
    for image in images:
        refs = (image.get('RepoTags') or []) + (image.get('RepoDigests') or [])
        # Unidentified dangling images and images shared with another repository are retained.
        if not refs or not all(ref.startswith(repository + '@') or ref.startswith(repository + ':') for ref in refs):
            continue
        if image['Id'] not in protected:
            candidates.append(image['Id'])
    return sorted(set(candidates))


def cleanup(repository, service, mode):
    if service not in {'ai-api', 'embedding'} or mode not in {'audit', 'apply'}:
        raise ValueError('Invalid cleanup scope')
    if not re.fullmatch(r'929368845727\.dkr\.ecr\.ap-northeast-2\.amazonaws\.com/zipsai-(ai-api|embedding)', repository):
        raise ValueError('Unexpected image repository')
    expected = 'zipsai-ai-api' if service == 'ai-api' else 'zipsai-embedding'
    if repository.rsplit('/', 1)[-1] != expected:
        raise ValueError('Repository and service mismatch')
    base = Path('/opt/zipsai/ai-v2')
    current = base / 'current'
    if not current.is_symlink():
        print(json.dumps({'skipped': 'no_verified_release'}))
        return
    # Use the same lock as AI-owned CD. A concurrent deployment makes this run skip.
    with (base / 'deploy.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print(json.dumps({'skipped': 'deployment_in_progress'}))
            return
        release = current.resolve(strict=True)
        if release.parent != base or not re.fullmatch(r'release-[0-9a-f]{32}', release.name):
            raise RuntimeError('Unexpected release path; cleanup aborted')
        # Do not print runtime.env; only resolve its non-secret image reference.
        image_refs = []
        for line in (release / 'runtime.env').read_text().splitlines():
            if line.startswith('IMAGE_URI='):
                values = shlex.split(line[len('IMAGE_URI='):])
                if len(values) != 1:
                    raise RuntimeError('Invalid current image reference')
                image_refs.append(values[0])
        if len(image_refs) != 1:
            raise RuntimeError('Missing current image reference')
        protected = {image['Id'] for image in inspect_images(image_refs)}
        container_ids = docker('ps', '-aq', '--no-trunc').split()
        containers = json.loads(docker('inspect', *container_ids)) if container_ids else []
        container_refs = [container['Image'] for container in containers]
        protected.update(image['Id'] for image in inspect_images(sorted(set(container_refs))))
        healthy = any(
            (container.get('Config', {}).get('Labels') or {}).get('com.docker.compose.project') == f'zipsai-ai-v2-{service}'
            and (container.get('Config', {}).get('Labels') or {}).get('com.docker.compose.service') == service
            and container.get('State', {}).get('Running') is True
            and container.get('State', {}).get('Health', {}).get('Status') == 'healthy'
            for container in containers)
        if not healthy:
            print(json.dumps({'skipped': 'service_not_healthy'}))
            return
        ids = sorted(set(docker('image', 'ls', '-aq', '--no-trunc').split()))
        candidates = select_candidates(inspect_images(ids), protected, repository)
        print(json.dumps({'mode': mode, 'service': service, 'candidate_ids': candidates,
                          'protected_image_count': len(protected)}), flush=True)
        if mode == 'audit':
            return
        failed = 0
        for image_id in candidates:
            # No --force: Docker must reject an image referenced by any container.
            result = docker('image', 'rm', image_id, optional=True)
            if result is None:
                failed += 1
            else:
                print(json.dumps({'deleted_image_id': image_id}), flush=True)
        print(json.dumps({'cleanup_failed_count': failed}))
        if failed:
            raise RuntimeError('Some images were retained; inspect Docker state')


if __name__ == '__main__':
    try:
        cleanup(*sys.argv[1:])
    except Exception:
        print('Scoped image cleanup failed; raw process output and runtime values suppressed', file=sys.stderr)
        sys.exit(1)
