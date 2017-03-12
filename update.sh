#!/bin/bash

tree ~/Music/iTunes/iTunes\ Media/Music -N > README

if git status -s | grep -q README
then
  git add -A
  git commit -am "Update as of $(date +%Y-%m-%d)"
  git push origin master
else
  echo "No changes"
fi
