#!/bin/bash
# Copies what may become public into an empty folder and checks it. Publishes nothing.
#   ops/export.sh FOLDER
set -e -o pipefail
out=$1; [ -n "$out" ] && [ ! -e "$out" ] || { echo "Give a folder that does not exist yet."; exit 2; }
cd "$(dirname "$0")/.."
git diff --quiet HEAD || { echo "There are changes without a commit."; exit 1; }
mkdir -p "$out"
git archive HEAD README.md .gitignore agent app demo media ops | tar -x -C "$out"
[ ! -f LICENSE ] || cp LICENSE "$out/"
cd "$out"
bad=$(grep -rnIE "/Users/|$(id -un)|"'privaterelay|@icloud|@gmail|ghp_[A-Za-z0-9]{20}|github_pat_[A-Za-z0-9_]{30}|sk-[A-Za-z0-9_-]{30}|AKIA[A-Z0-9]{16}|BEGIN [A-Z ]*PRIVATE KEY' . | grep -v '^./ops/\(audit\|export\).sh\|^./app/assets/vendor/posthog.LICENSE:256:' | cut -d: -f1,2 || true)
[ -z "$bad" ] || { echo "Look at these lines first:"; echo "$bad"; exit 1; }
echo "$(find . -type f | wc -l | tr -d ' ') files, $(du -sh . | cut -f1), nothing suspicious found by the patterns"
