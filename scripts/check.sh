#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
bash -n cluster scripts/check.sh scripts/test-workers.sh
./cluster check
for playbook in bootstrap preflight status kubeconfig clean_k8s_ubuntu ubuntu-update ping install_docker_ubuntu; do
  ANSIBLE_LOCAL_TEMP="${TMPDIR:-/tmp}/kubernetes-ansible-$UID" \
    ansible-playbook "kube-cluster/ansible-playbook/$playbook.yml" --syntax-check
done
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck cluster scripts/check.sh scripts/test-workers.sh
fi
./scripts/test-workers.sh
git diff --check
