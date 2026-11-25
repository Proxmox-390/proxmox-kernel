#!/bin/bash
# prepare-source.sh <dir> - turn the fetched upstream tree into the source the
# packages are built from:
#
#   1. export the pinned commit and its submodules (as git archive does)
#   2. apply patches/packaging (changes to Proxmox's debian/ directory)
#   3. install config/config-s390x and config/config-s390x.opts
#   4. add patches/kernel to the end of the kernel patch series (debian/patches)
#   5. put our changelog entries on top of Proxmox's changelog
#   6. record the commits (debian/source-commit, debian/source-upstream)
#   7. regenerate debian/control for the new kernel release name
#
# With PREPARE_NO_KERNEL_PATCHES=1 step 4 is skipped (used to refresh the config
# and to test-apply a new patch set).
set -euo pipefail
top=$(cd "$(dirname "$0")/.." && pwd)
. "$top/upstream.conf"
up=${UPSTREAM_DIR:-$top/upstream}
dest=${1:?usage: prepare-source.sh <dir>}

die() { echo "prepare-source: $*" >&2; exit 1; }

[ "$(git -C "$up" rev-parse -q --verify "$UPSTREAM_COMMIT^{commit}" 2>/dev/null)" = "$UPSTREAM_COMMIT" ] ||
    die "upstream tree missing in $up, run scripts/fetch-upstream.sh"
[ ! -e "$dest" ] || die "$dest exists, remove it first (make clean)"
mkdir -p "$dest"

echo "prepare-source: exporting $UPSTREAM_TAG to $dest"
git -C "$up" archive "$UPSTREAM_COMMIT" | tar -x -C "$dest"
git -C "$up" submodule --quiet foreach --recursive 'echo "$displaypath"' | while read -r sub; do
    git -C "$up/$sub" archive --prefix="$sub/" HEAD | tar -x -C "$dest"
done

while read -r p; do
    case $p in ''|'#'*) continue ;; esac
    echo "prepare-source: packaging patch $p"
    patch -s -p1 --no-backup-if-mismatch -d "$dest" < "$top/patches/packaging/$p"
done < "$top/patches/packaging/series"

install -m 644 "$top/config/config-s390x" "$dest/debian/config/config-s390x"
install -m 644 "$top/config/config-s390x.opts" "$dest/debian/rules.d/config-s390x.opts"

if [ -z "${PREPARE_NO_KERNEL_PATCHES:-}" ]; then
    n=0
    while read -r p; do
        case $p in ''|'#'*) continue ;; esac
        mkdir -p "$dest/debian/patches/$(dirname "$p")"
        cp "$top/patches/kernel/$p" "$dest/debian/patches/$p"
        echo "$p" >> "$dest/debian/patches/series"
        n=$((n + 1))
    done < "$top/patches/kernel/series"
    echo "prepare-source: $n kernel patch(es) added to debian/patches/series"
fi

cat "$top/changelog" "$dest/debian/changelog" > "$dest/debian/changelog.new"
mv "$dest/debian/changelog.new" "$dest/debian/changelog"

commit=$(git -C "$top" rev-parse HEAD 2>/dev/null || echo unknown)
if [ -n "$(git -C "$top" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
    [ -n "${ALLOW_DIRTY:-}" ] || die "uncommitted changes in the packaging repository (ALLOW_DIRTY=1 for a test build)"
    commit="$commit-dirty"
fi
echo "$commit" > "$dest/debian/source-commit"
cat > "$dest/debian/source-upstream" <<EOF
prepared from:
git clone $UPSTREAM_URL
tag $UPSTREAM_TAG, commit $UPSTREAM_COMMIT
EOF

(cd "$dest" && debian/rules debian/control > /dev/null)
echo "prepare-source: $(cd "$dest" && dpkg-parsechangelog -SSource -SVersion | tr '\n' ' ')ready in $dest"
