#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
bash -n cluster scripts/check.sh scripts/test-rke2.sh
./cluster check
for playbook in validate bootstrap preflight prepare servers agents verify status kubeconfig backup ubuntu-update ping; do
  ANSIBLE_LOCAL_TEMP="${TMPDIR:-/tmp}/kubernetes-ansible-$UID" \
    ansible-playbook "kube-cluster/ansible-playbook/$playbook.yml" --syntax-check
done
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck cluster scripts/check.sh scripts/test-rke2.sh
fi
./scripts/test-rke2.sh
git diff --check
