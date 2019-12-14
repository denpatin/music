#!/bin/bash

tree ~/Music/Music/Media/Music -N | sed 's/\.m[p4][3a]$//' > README

export GPG_TTY=$(tty)
if git status -s | grep -q README
then
  git add -A
  git commit -S -m "Update as of $(date +%Y-%m-%d)"
  git push origin master
else
  echo "No changes"
fi
