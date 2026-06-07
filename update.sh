#!/usr/bin/env fish

set REPO_DIR (cd (dirname (status --current-filename)); and pwd)
cd $REPO_DIR

set -x GPG_TTY (tty)

set -l old_songs (git show HEAD:README 2>/dev/null | ruby scripts/08_make_readme.rb --flatten)
ruby scripts/08_make_readme.rb > README
set -l new_songs (ruby scripts/08_make_readme.rb --flatten < README)

if not git status --porcelain | grep -q .
    echo "No changes"
    exit 0
end

set -l added (comm -13 (printf '%s\n' $old_songs | psub) (printf '%s\n' $new_songs | psub))
set -l removed (comm -23 (printf '%s\n' $old_songs | psub) (printf '%s\n' $new_songs | psub))
set -l na (count $added)
set -l nr (count $removed)

set -l parts
if test $na -gt 0
    set -l w songs
    test $na -eq 1; and set w song
    set -a parts "added $na $w"
end
if test $nr -gt 0
    set -l w songs
    test $nr -eq 1; and set w song
    set -a parts "removed $nr $w"
end

set -l msg (string join ", " $parts)
if test -z "$msg"
    set msg "Update music list"
else
    set msg (string upper (string sub -l 1 -- $msg))(string sub -s 2 -- $msg)
end

set -l BRANCH (git rev-parse --abbrev-ref HEAD)
git add -A
git commit -q -S -m "$msg"
git push -q origin $BRANCH

for s in $added
    set_color green
    echo "+ "(string replace -a \u0001 ' / ' -- $s)
    set_color normal
end
for s in $removed
    set_color red
    echo "- "(string replace -a \u0001 ' / ' -- $s)
    set_color normal
end

set_color --bold green
echo "Pushed to origin/$BRANCH ("(git rev-parse --short HEAD)"): $msg"
set_color normal
