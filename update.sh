#!/usr/bin/env fish

set REPO_DIR (cd (dirname (status --current-filename)); and pwd)
cd $REPO_DIR

ruby scripts/08_make_readme.rb > README

set -x GPG_TTY (tty)
if git status --porcelain | grep -q .
    set BRANCH (git rev-parse --abbrev-ref HEAD)
    git add -A
    git commit -S -m "Update as of "(date +%Y-%m-%d)
    git push origin $BRANCH
else
    echo "No changes"
end
