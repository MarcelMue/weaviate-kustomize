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
ETCDCTL_ENDPOINTS="http://etcd-0.etcd-headless.default.svc.cluster.local:2379"
# Remove the last comma "," introduced in the string
export ETCDCTL_ENDPOINTS="$(sed 's/,/ /g' <<< $ETCDCTL_ENDPOINTS | awk '{$1=$1};1' | sed 's/ /,/g')"

etcdctl $AUTH_OPTIONS member remove --debug=true "$(cat "$ETCD_DATA_DIR/member_id")" > "$(dirname "$ETCD_DATA_DIR")/member_removal.log" 2>&1
