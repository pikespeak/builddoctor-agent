#!/bin/bash
# Known holes and secret patterns. Run before every deployment: ops/audit.sh
set -e -o pipefail
cd "$(dirname "$0")/.."
(cd app && mix hex.audit)
(cd agent && go run golang.org/x/vuln/cmd/govulncheck@v1.1.4 ./... | tail -4)
bad=$(git grep -nIE 'ghp_[A-Za-z0-9]{30}|github_pat_[A-Za-z0-9_]{40}|sk-[A-Za-z0-9_-]{30}|tsec_[A-Za-z0-9]{10}|AKIA[A-Z0-9]{16}|BEGIN [A-Z ]*PRIVATE KEY|fo1_[A-Za-z0-9]|fm2_[A-Za-z0-9]|privaterelay\.' -- . ':!ops/audit.sh' || true)
[ -z "$bad" ] || { echo "Possible secrets:"; echo "$bad" | cut -d: -f1,2; exit 1; }
echo "audit clean"
