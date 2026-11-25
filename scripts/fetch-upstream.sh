#!/bin/bash
# fetch-upstream.sh - get the upstream tree pinned in upstream.conf.
#
# A shallow fetch of the one tag (the full repository carries the whole kernel
# history, several GB), checked against the pinned commit, plus the ZFS
# packaging submodule recorded in that tree with its nested OpenZFS submodule.
#
#   UPSTREAM_DIR      where to keep it (default: ./upstream)
#   UPSTREAM_MIRROR   fetch from this repository instead of UPSTREAM_URL, for
#                     example a local clone; the pinned commit is checked alike
set -euo pipefail
top=$(cd "$(dirname "$0")/.." && pwd)
. "$top/upstream.conf"
dir=${UPSTREAM_DIR:-$top/upstream}
from=${UPSTREAM_MIRROR:-$UPSTREAM_URL}

die() { echo "fetch-upstream: $*" >&2; exit 1; }

[ -d "$dir/.git" ] || git init -q "$dir"
if ! git -C "$dir" cat-file -e "$UPSTREAM_COMMIT^{commit}" 2>/dev/null; then
    echo "fetch-upstream: fetching $UPSTREAM_TAG from $from"
    git -C "$dir" fetch -q --depth 1 "$from" tag "$UPSTREAM_TAG"
fi
have=$(git -C "$dir" rev-parse "$UPSTREAM_TAG^{commit}" 2>/dev/null) || die "tag $UPSTREAM_TAG not found in $dir"
[ "$have" = "$UPSTREAM_COMMIT" ] ||
    die "tag $UPSTREAM_TAG is $have, upstream.conf pins $UPSTREAM_COMMIT"

# the submodules need a work tree
if [ "$(git -C "$dir" rev-parse -q --verify HEAD 2>/dev/null)" != "$UPSTREAM_COMMIT" ]; then
    git -C "$dir" checkout -q --detach "$UPSTREAM_COMMIT"
fi
zfs=$(git -C "$dir" ls-tree "$UPSTREAM_COMMIT" debian/zfsonlinux | awk '{print $3}')
[ "$zfs" = "$UPSTREAM_ZFS_COMMIT" ] ||
    die "debian/zfsonlinux is recorded as $zfs, upstream.conf pins $UPSTREAM_ZFS_COMMIT"
if [ "$(git -C "$dir/debian/zfsonlinux" rev-parse -q --verify HEAD 2>/dev/null)" != "$zfs" ] ||
   [ ! -f "$dir/debian/zfsonlinux/upstream/META" ]; then
    echo "fetch-upstream: fetching the zfsonlinux submodule"
    git -C "$dir" submodule update -q --init --recursive debian/zfsonlinux
fi
[ "$(git -C "$dir/debian/zfsonlinux" rev-parse HEAD)" = "$zfs" ] || die "zfsonlinux submodule is not at $zfs"
echo "fetch-upstream: $UPSTREAM_TAG ($UPSTREAM_COMMIT) ready in $dir"
