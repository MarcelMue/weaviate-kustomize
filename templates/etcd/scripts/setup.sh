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
HOSTNAME="$(hostname -s)"
AUTH_OPTIONS=""
ETCDCTL_ENDPOINTS="http://etcd-0.etcd-headless.default.svc.cluster.local:2379"
# Remove the last comma "," introduced in the string
export ETCDCTL_ENDPOINTS="$(sed 's/,/ /g' <<< $ETCDCTL_ENDPOINTS | awk '{$1=$1};1' | sed 's/ /,/g')"
export ROOT_PASSWORD="${ETCD_ROOT_PASSWORD:-}"
if [[ -n "${ETCD_ROOT_PASSWORD:-}" ]]; then
  unset ETCD_ROOT_PASSWORD
fi
# Functions
## Store member id for later member replacement
store_member_id() {
    while ! etcdctl $AUTH_OPTIONS member list; do sleep 1; done
    etcdctl $AUTH_OPTIONS member list | grep "$HOSTNAME" | awk '{ print $1}' | awk -F "," '{ print $1}' > "$ETCD_DATA_DIR/member_id"
    echo "==> Stored member id: $(cat ${ETCD_DATA_DIR}/member_id)" 1>&3 2>&4
    exit 0
}
## Configure RBAC
configure_rbac() {
    # When there's more than one replica, we can assume the 1st member
    # to be created is "etcd-0" since a statefulset is used
    if [[ -n "${ROOT_PASSWORD:-}" ]] && [[ "$HOSTNAME" == "etcd-0" ]]; then
        echo "==> Configuring RBAC authentication!" 1>&3 2>&4
        etcd &
        ETCD_PID=$!
        while ! etcdctl $AUTH_OPTIONS member list; do sleep 1; done
        echo "$ROOT_PASSWORD" | etcdctl $AUTH_OPTIONS user add root --interactive=false
        etcdctl $AUTH_OPTIONS auth enable
        kill "$ETCD_PID"
        sleep 5
    fi
}
## Checks whether there was a disaster or not
is_disastrous_failure() {
    local endpoints_array=(${ETCDCTL_ENDPOINTS//,/ })
    local active_endpoints=0
    local -r min_endpoints=$(((3 + 1)/2))

    for e in "${endpoints_array[@]}"; do
        if [[ "$e" != "$ETCD_ADVERTISE_CLIENT_URLS" ]] && (unset -v ETCDCTL_ENDPOINTS; etcdctl $AUTH_OPTIONS  endpoint health --endpoints="$e"); then
            active_endpoints=$((active_endpoints + 1))
        fi
    done
    if [[ $active_endpoints -lt $min_endpoints ]]; then
        true
    else
        false
    fi
}

## Check wether the member was succesfully removed from the cluster
should_add_new_member() {
    return_value=0
    if (grep -E "^Member[[:space:]]+[a-z0-9]+\s+removed\s+from\s+cluster\s+[a-z0-9]+$" "$(dirname "$ETCD_DATA_DIR")/member_removal.log") || \
        ! ([[ -d "$ETCD_DATA_DIR/member/snap" ]] && [[ -f "$ETCD_DATA_DIR/member_id" ]]); then
        rm -rf $ETCD_DATA_DIR/* 1>&3 2>&4
    else
        return_value=1
    fi
    rm -f "$(dirname "$ETCD_DATA_DIR")/member_removal.log" 1>&3 2>&4
    return $return_value
}

if [[ ! -d "$ETCD_DATA_DIR" ]]; then
    echo "==> Creating data dir..." 1>&3 2>&4
    echo "==> There is no data at all. Initializing a new member of the cluster..." 1>&3 2>&4
    store_member_id & 1>&3 2>&4
    configure_rbac
else
    echo "==> Detected data from previous deployments..." 1>&3 2>&4
    if [[ 3 -eq 1 ]]; then
        echo "==> Single node cluster detected!!" 1>&3 2>&4
    elif is_disastrous_failure; then
        echo "==> Cluster not responding!!" 1>&3 2>&4
        echo "==> Disaster recovery is disabled, the cluster will try to recover on it's own..." 1>&3 2>&4
    elif should_add_new_member; then
        echo "==> Adding new member to existing cluster..." 1>&3 2>&4
        etcdctl $AUTH_OPTIONS member add "$HOSTNAME" --peer-urls="https://${HOSTNAME}.etcd-headless.default.svc.cluster.local:2380" | grep "^ETCD_" > "$ETCD_DATA_DIR/new_member_envs" 1>&3 2>&4
        sed -ie 's/^/export /' "$ETCD_DATA_DIR/new_member_envs"
        echo "==> Loading env vars of existing cluster..." 1>&3 2>&4
        source "$ETCD_DATA_DIR/new_member_envs" 1>&3 2>&4
        store_member_id & 1>&3 2>&4
    else
        echo "==> Updating member in existing cluster..." 1>&3 2>&4
        etcdctl $AUTH_OPTIONS member update "$(cat "$ETCD_DATA_DIR/member_id")" --peer-urls="https://${HOSTNAME}.etcd-headless.default.svc.cluster.local:2380" 1>&3 2>&4
    fi
fi
exec etcd 1>&3 2>&4
