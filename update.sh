#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

ruby scripts/08_make_readme.rb > README

export GPG_TTY=$(tty)
if git status --porcelain | grep -q .
then
  BRANCH="$(git rev-parse --abbrev-ref HEAD)"
  git add -A
  git commit -S -m "Update as of $(date +%Y-%m-%d)"
  git push origin "$BRANCH"
else
  echo "No changes"
fi
