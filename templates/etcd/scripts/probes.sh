#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset

# Debug section
exec 3>&1
exec 4>&2

if [ "${BITNAMI_DEBUG}" = true ]; then
  echo "==> Bash debug is on"
else
  echo "==> Bash debug is off"
  exec 1>/dev/null
  exec 2>/dev/null
fi

# Constants
AUTH_OPTIONS=""

echo "==> [DEBUG] Probing etcd cluster"
echo "==> [DEBUG] Probe command: \"etcdctl $AUTH_OPTIONS endpoint health\""
etcdctl $AUTH_OPTIONS endpoint health
