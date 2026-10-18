#!/usr/bin/env bash
set -Eeuo pipefail
set +x
umask 077
cd /opt/zipsai
if [[ "${ZIPSAI_AI_LOCK_HELD:-}" != 1 ]]; then
  exec 9>/run/zipsai-ai-deploy.lock
  flock -w 900 9
fi
python3 prepare-env.py "${1:-}"
role="$(python3 -c 'import json; print(json.load(open("deployment.json"))["service"])')"
if [[ "$role" == qdrant ]]; then
  mountpoint -q /data || { echo 'Qdrant storage is not mounted' >&2; exit 1; }
else
  region="$(python3 -c 'import json; print(json.load(open("deployment.json"))["region"])')"
  registry="$(python3 -c 'import json; print(json.load(open("deployment.json"))["repository_url"].split("/")[0])')"
  aws ecr get-login-password --region "$region" | docker login --username AWS --password-stdin "$registry" >/dev/null
fi
docker compose --env-file runtime.env.next config -q
docker compose --env-file runtime.env.next pull
had_previous=false
if [[ -f runtime.env ]]; then cp -p runtime.env runtime.env.previous; had_previous=true; fi
restore_previous() {
  if [[ "$had_previous" == true ]]; then
    cp -p runtime.env.previous runtime.env
    docker compose --env-file runtime.env up -d --no-build || true
    echo 'Previous configuration reapplied; inspect its health before proceeding.' >&2
  fi
}
mv runtime.env.next runtime.env
if ! docker compose --env-file runtime.env up -d --no-build; then restore_previous; exit 1; fi
for attempt in $(seq 1 90); do
  container_id="$(docker compose --env-file runtime.env ps -q "$role")"
  health=""
  if [[ -n "$container_id" ]]; then
    health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$container_id")"
  fi
  if [[ "$health" == healthy ]]; then
    if [[ "$role" != qdrant ]]; then
      previous_tag=""
      if [[ -f last-successful-tag ]]; then previous_tag="$(< last-successful-tag)"; fi
      printf '%s\n' "$1" > last-successful-tag
      repository="$(python3 -c 'import json; print(json.load(open("deployment.json"))["repository_url"])')"
      # Only this service's superseded SHA7 tags; never global prune/force.
      while IFS= read -r old_tag; do
        if [[ "$old_tag" =~ ^[0-9a-f]{7}$ && "$old_tag" != "$1" && "$old_tag" != "$previous_tag" ]]; then
          docker image rm "$repository:$old_tag" >/dev/null 2>&1 || true
        fi
      done < <(docker image ls "$repository" --format '{{.Tag}}')
    fi
    echo 'Container health check passed. Model invocation and indexing still require end-to-end tests.'
    exit 0
  fi
  sleep 10
done
echo 'Container health check failed; attempting previous configuration.' >&2
restore_previous
exit 1
