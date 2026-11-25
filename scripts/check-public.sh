#!/bin/bash
# check-public.sh - checks on the repository content before it is pushed:
# every listed patch exists and every patch file is listed, no patch carries a
# Co-Authored-By trailer, and, with CHECK_DENY_FILE naming a file of extended
# regular expressions (one per line), no tracked file matches one of them.
set -euo pipefail
top=$(cd "$(dirname "$0")/.." && pwd)
cd "$top"
rc=0
for d in patches/packaging patches/kernel; do
    while read -r p; do
        case $p in ''|'#'*) continue ;; esac
        [ -f "$d/$p" ] || { echo "$d/series lists missing file $p"; rc=1; }
    done < "$d/series"
    while read -r f; do
        grep -qxF "${f#"$d/"}" "$d/series" || { echo "$f is not in $d/series"; rc=1; }
    done < <(find "$d" -name '*.patch' | sort)
done
if grep -rn -i '^Co-Authored-By:' patches; then rc=1; fi
if [ -n "${CHECK_DENY_FILE:-}" ] && git ls-files -z | xargs -0 grep -n -I -E -f "$CHECK_DENY_FILE" --; then
    echo "tracked files match an expression of $CHECK_DENY_FILE (see above)"; rc=1
fi
[ $rc -eq 0 ] && echo "check-public: ok"
exit $rc
