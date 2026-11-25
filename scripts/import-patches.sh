#!/bin/bash
# import-patches.sh - add or replace a set of kernel patches.
#
#   import-patches.sh <topic> <dir> <new-version> "<changelog line>" [<patch>...]
#
# <dir> holds *.patch files (git format-patch output). Without a list of patch
# names, its 'series' file gives the order, or else all *.patch sorted by name.
# The patches replace patches/kernel/<topic>/ and are listed for that topic in
# patches/kernel/series; other topics keep their place. Before anything is
# committed the complete series (Proxmox's patches, then ours) is test-applied
# to the pinned upstream tree without fuzz. Each import starts a new package
# version, as every build needs its own kernel release name.
#
# Patches with a Co-Authored-By trailer are refused. IMPORT_DENY_FILE may name
# a file of extended regular expressions (one per line) that must not occur in
# a patch either.
set -euo pipefail
top=$(cd "$(dirname "$0")/.." && pwd)
. "$top/upstream.conf"
up=${UPSTREAM_DIR:-$top/upstream}
topic=${1:?topic}; dir=$(readlink -f "${2:?patch directory}"); newver=${3:?new version}; msg=${4:?changelog line}
shift 4

die() { echo "import-patches: $*" >&2; exit 1; }

case $topic in */*|.*|'') die "bad topic name '$topic'" ;; esac
cd "$top"
[ -z "$(git status --porcelain --untracked-files=no)" ] || die "uncommitted changes in $top"

if [ $# -gt 0 ]; then list=("$@")
elif [ -f "$dir/series" ]; then mapfile -t list < <(grep -v -e '^#' -e '^$' "$dir/series")
else mapfile -t list < <(cd "$dir" && ls -- *.patch | sort); fi
[ ${#list[@]} -gt 0 ] || die "no patches in $dir"
for p in "${list[@]}"; do [ -f "$dir/$p" ] || die "$dir/$p not found"; done

if grep -n -i '^Co-Authored-By:' "${list[@]/#/$dir/}"; then
    die "patches carry a Co-Authored-By trailer (see above)"
fi
if [ -n "${IMPORT_DENY_FILE:-}" ] && grep -n -E -f "$IMPORT_DENY_FILE" "${list[@]/#/$dir/}"; then
    die "patches match an expression of $IMPORT_DENY_FILE (see above)"
fi

restore() { git -C "$top" checkout -q -- patches/kernel changelog; git -C "$top" clean -fdq patches/kernel; }

git rm -rq --ignore-unmatch "patches/kernel/$topic"
mkdir -p "patches/kernel/$topic"
grep -v "^$topic/" patches/kernel/series > patches/kernel/series.new || true
for p in "${list[@]}"; do
    cp "$dir/$p" "patches/kernel/$topic/$(basename "$p")"
    echo "$topic/$(basename "$p")" >> patches/kernel/series.new
done
mv patches/kernel/series.new patches/kernel/series

# test-apply: the upstream tree with Proxmox's own series, then ours
scripts/fetch-upstream.sh > /dev/null
t=$(mktemp -d "${TMPDIR:-/tmp}/import-patches.XXXXXX")
trap 'rm -rf "$t"' EXIT
git -C "$up" archive "$UPSTREAM_COMMIT" | tar -x -C "$t"
mkdir "$t/q"
cp -a "$t/debian/patches/." "$t/q/"
while read -r p; do
    case $p in ''|'#'*) continue ;; esac
    mkdir -p "$t/q/$(dirname "$p")"; cp "patches/kernel/$p" "$t/q/$p"; echo "$p" >> "$t/q/series"
done < patches/kernel/series
if ! (cd "$t" && QUILT_PATCHES=q quilt push -a -q --fuzz=0 > "$t/quilt.log" 2>&1); then
    tail -n 20 "$t/quilt.log" >&2
    restore
    die "the series does not apply to $UPSTREAM_TAG"
fi

DEBEMAIL=${DEBEMAIL:-$(dpkg-parsechangelog -l changelog -SMaintainer)} \
    dch -c changelog -v "$newver" -D trixie --force-distribution "$msg"
git add -A patches/kernel changelog
git commit -q -m "kernel patches: $topic ($newver)" -m "$msg"
echo "import-patches: ${#list[@]} patch(es) in patches/kernel/$topic, version $newver committed; build with 'make deb'"
