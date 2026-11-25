#!/bin/bash
# update-config.sh <workdir> - refresh config/config-s390x for the pinned
# upstream tree.
#
# Prepares the source in <workdir> with all patches applied (options added by
# patches only exist in a patched tree) and runs Proxmox's 'debian/rules
# updateconfig': the committed config, the overrides of config-common.opts and
# config-s390x.opts, then 'make olddefconfig'. Options that are new to the
# committed config are listed before their Kconfig defaults are applied: review
# that list. The result is copied back to config/config-s390x; commit it.
#
# CONFIG_BASE=<file> starts from another full config instead of the committed
# one, for example Debian's s390x config when moving to a new kernel series.
set -euo pipefail
top=$(cd "$(dirname "$0")/.." && pwd)
work=${1:?usage: update-config.sh <workdir>}

[ "$(dpkg --print-architecture)" = s390x ] || { echo "update-config: run this on s390x" >&2; exit 1; }
ALLOW_DIRTY=1 "$top/scripts/prepare-source.sh" "$work"
cd "$work"
[ -z "${CONFIG_BASE:-}" ] || install -m 644 "$CONFIG_BASE" debian/config/config-s390x
QUILT_PATCHES=debian/patches quilt push -a -q > /dev/null
make -f debian/rules updateconfig
cp debian/config/config-s390x "$top/config/config-s390x"
echo "update-config: config/config-s390x refreshed:"
git -C "$top" --no-pager diff --stat -- config/config-s390x
