#!/bin/bash
# make-source.sh <dir> - build the Debian source package (format 3.0 (quilt)) in <dir>:
#
#   <source>_<upstream version>.orig.tar.xz      the pinned upstream tree without its debian/
#                                                directory, as 'git archive' of the pinned commit
#   <source>_<version>.debian.tar.xz             the debian/ directory the packages are built
#                                                from: Proxmox's packaging with patches/packaging
#                                                applied, the configuration, the kernel patches in
#                                                debian/patches and the ZFS packaging submodule
#   <source>_<version>.dsc
#
# The source is prepared like for the binary build (scripts/prepare-source.sh), so a build of the
# unpacked source package gives the same packages. The orig tarball only depends on the pinned
# commit: it is the same file for every revision on one upstream tag.
set -euo pipefail
top=$(cd "$(dirname "$0")/.." && pwd)
. "$top/upstream.conf"
up=${UPSTREAM_DIR:-$top/upstream}
out=${1:?usage: make-source.sh <dir>}

src=$(dpkg-parsechangelog -l "$top/changelog" -SSource)
ver=$(dpkg-parsechangelog -l "$top/changelog" -SVersion)
upver=${ver%-*}
[ ! -e "$out" ] || { echo "make-source: $out exists, remove it first" >&2; exit 1; }
mkdir -p "$out"
out=$(cd "$out" && pwd)

"$top/scripts/prepare-source.sh" "$out/$src-$upver"

echo "make-source: ${src}_$upver.orig.tar.xz from $UPSTREAM_TAG"
git -C "$up" archive --prefix="$src-$upver/" "$UPSTREAM_COMMIT" -- . ':(exclude)debian' |
    xz -6 -T2 > "$out/${src}_$upver.orig.tar.xz"

(cd "$out" && dpkg-source -b "$src-$upver")
rm -rf "$out/$src-$upver"
ls -l "$out"
