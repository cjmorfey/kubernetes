#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TASK_TMP="$(mktemp -d "${TMPDIR:-/tmp}/kubernetes-rke2-test.XXXXXX")"
trap 'rm -rf "$TASK_TMP"' EXIT
export ANSIBLE_CONFIG="$ROOT/ansible.cfg"
export ANSIBLE_LOCAL_TEMP="$TASK_TMP/local"
export ANSIBLE_REMOTE_TEMP="$TASK_TMP/remote"
cat > "$TASK_TMP/hosts" <<'INVENTORY'
[master]
server-01
server-02
server-03
[workers]
agent-01
[k8s:children]
master
workers
INVENTORY
ansible-playbook -i "$TASK_TMP/hosts" "$ROOT/kube-cluster/ansible-playbook/validate.yml" \
  -e "@$ROOT/kube-cluster/group_vars/all.yml" -e rke2_require_ha=true \
  > "$TASK_TMP/validate" 2>&1 || { cat "$TASK_TMP/validate"; exit 1; }
if ansible-playbook -i "$TASK_TMP/hosts" "$ROOT/kube-cluster/ansible-playbook/validate.yml" \
  -e "@$ROOT/kube-cluster/group_vars/all.yml" -e rke2_version=latest > "$TASK_TMP/invalid" 2>&1; then
  echo 'Unpinned RKE2 version should have been rejected' >&2
  exit 1
fi
if ansible-playbook -i "$TASK_TMP/hosts" "$ROOT/kube-cluster/ansible-playbook/validate.yml" \
  -e "@$ROOT/kube-cluster/group_vars/all.yml" -e rke2_registration_address=server-01 > "$TASK_TMP/endpoint" 2>&1; then
  echo 'Single-node endpoint for HA should have been rejected' >&2
  exit 1
fi
ansible-playbook -i "$TASK_TMP/hosts" "$ROOT/scripts/test-rke2.yml" \
  -e "@$ROOT/kube-cluster/group_vars/all.yml" -e "test_directory=$TASK_TMP" \
  -e '{"rke2_s3":{"etcd-s3":true,"etcd-s3-bucket":"test-bucket","etcd-s3-secret-key":"fake-s3-secret"}}' \
  > "$TASK_TMP/result" 2>&1 || { cat "$TASK_TMP/result"; exit 1; }
echo 'RKE2 bootstrap, server/agent credentials, networking and snapshot config: passed.'
