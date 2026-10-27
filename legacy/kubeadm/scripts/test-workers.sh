#!/usr/bin/env bash
# Exercise the real worker playbook locally with a fake kubeadm, without a cluster or sudo.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TASK_TMP="$(mktemp -d "${TMPDIR:-/tmp}/kubernetes-workers.XXXXXX")"
trap 'rm -rf "$TASK_TMP"' EXIT
export ANSIBLE_CONFIG="$ROOT/ansible.cfg"
export ANSIBLE_LOCAL_TEMP="$TASK_TMP/ansible"
export ANSIBLE_REMOTE_TEMP="$TASK_TMP/remote"
export MOCK_KUBEADM_LOG="$TASK_TMP/kubeadm.log"
export PATH="$TASK_TMP:$PATH"
cat > "$TASK_TMP/kubeadm" <<'MOCK'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> "$MOCK_KUBEADM_LOG"
case "$*" in
  'token create --ttl 15m --print-join-command')
    echo 'kubeadm join 192.0.2.1:6443 --token abcdef.0123456789abcdef --discovery-token-ca-cert-hash sha256:fake'
    ;;
  join*)
    if [[ "${MOCK_JOIN_FAIL:-0}" == 1 && "$*" == *worker-02* ]]; then exit 1; fi
    ;;
  'token delete abcdef.0123456789abcdef') ;;
  *) echo "Unexpected command: $*" >&2; exit 2 ;;
esac
MOCK
chmod +x "$TASK_TMP/kubeadm"
cat > "$TASK_TMP/hosts" <<'INVENTORY'
[master]
master-01 ansible_connection=local
[workers]
worker-01 ansible_connection=local
worker-02 ansible_connection=local
[k8s:children]
master
workers
INVENTORY
run_workers() {
  ansible-playbook -i "$TASK_TMP/hosts" "$ROOT/kube-cluster/ansible-playbook/workers.yml" \
    -e ansible_become=false > "$TASK_TMP/output" 2>&1
}
if ! run_workers; then cat "$TASK_TMP/output"; exit 1; fi
[[ $(grep -c '^join ' "$MOCK_KUBEADM_LOG") == 2 ]]
[[ $(grep -c '^token delete ' "$MOCK_KUBEADM_LOG") == 1 ]]
grep -q -- '--node-name=worker-01' "$MOCK_KUBEADM_LOG"
grep -q -- '--node-name=worker-02' "$MOCK_KUBEADM_LOG"
: > "$MOCK_KUBEADM_LOG"
export MOCK_JOIN_FAIL=1
if run_workers; then echo 'Failed join should fail the playbook' >&2; exit 1; fi
[[ $(grep -c '^token delete ' "$MOCK_KUBEADM_LOG") == 1 ]]
echo 'Worker joins and token revocation on success/failure: passed.'
