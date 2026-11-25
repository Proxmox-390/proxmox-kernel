#!/bin/bash
# check-packages.sh <directory with the built .deb files> [<prepared source tree>]
#
# Looks for traces of the build environment in the built packages:
#   - the build account, the build machine's name and the home directory
#   - the expressions of CHECK_DENY_FILE (extended regular expressions, one per line), if set
# in every file of every package (as text and as strings of binaries), in the modinfo fields and
# the .comment section of every module, in the generated compile.h of the headers package and in
# the kernel's version banner. The banner is taken from the uncompressed vmlinux of the source
# tree when one is given, as the installed image is compressed.
#
# The directory the packages were built in is reported separately: it is expected in a few
# places (see README.md) and should be a neutral path.
set -euo pipefail
export PATH=$PATH:/sbin:/usr/sbin
dir=$(readlink -f "${1:?usage: check-packages.sh <deb directory> [<source tree>]}")
src=${2:-}
work=$(mktemp -d "${TMPDIR:-/tmp}/check-packages.XXXXXX")
trap 'rm -rf "$work"' EXIT

pat=$work/patterns
{
    id -un
    hostname
    hostname -f 2>/dev/null || true
    echo "$HOME"
    [ -z "${CHECK_DENY_FILE:-}" ] || cat "$CHECK_DENY_FILE"
} | awk 'length($0) > 2 && !seen[$0]++' > "$pat"
# a banner is fine if it names the fixed identity, whatever the account is called
ident='\(build@proxmox-390\)'

rc=0
note() { echo "check-packages: $*"; rc=1; }

for deb in "$dir"/*.deb; do
    name=$(basename "$deb" | cut -d_ -f1)
    mkdir -p "$work/x/$name"
    dpkg-deb -x "$deb" "$work/x/$name"
    dpkg-deb -e "$deb" "$work/x/$name/DEBIAN"
done

echo "== files (text and binary strings)"
hits=$(grep -r -l -a -E -f "$pat" "$work/x" 2>/dev/null || true)
if [ -n "$hits" ]; then
    echo "$hits" | sed "s#^$work/x/##" | head -n 40
    for f in $(echo "$hits" | head -n 5); do
        strings -a "$f" | grep -E -f "$pat" | head -n 3 | sed 's/^/    /'
    done
    note "build environment names found in the files above"
else
    echo "none"
fi

echo "== modules: modinfo fields and .comment"
n=0; bad=0
while read -r ko; do
    n=$((n + 1))
    if { modinfo "$ko"; readelf -p .comment "$ko" 2>/dev/null; } | grep -v '^filename:' | grep -q -E -f "$pat"; then
        bad=$((bad + 1)); echo "  ${ko#"$work/x/"}"
    fi
done < <(find "$work/x" -name '*.ko' | sort)
echo "$n modules checked, $bad with hits"
[ "$bad" -eq 0 ] || note "build environment names in module information"
find "$work/x" -name '*.ko' | sort | head -n 2000 | xargs -r -n 200 modinfo -F vermagic | sort | uniq -c

echo "== compile.h of the headers package"
ch=$(find "$work/x" -path '*/include/generated/compile.h' | head -n1)
if [ -n "$ch" ]; then
    grep -E 'LINUX_COMPILE_(BY|HOST)|UTS_VERSION' "$ch"
    grep -E 'LINUX_COMPILE_(BY|HOST)' "$ch" | grep -q -E -f "$pat" && note "compile.h names the build environment"
else
    echo "not found"
fi

echo "== version banner"
if [ -n "$src" ] && [ -f "$src/vmlinux" ]; then
    banner=$(strings -a "$src/vmlinux" | grep -m1 '^Linux version [0-9]')
    echo "$banner"
    echo "$banner" | grep -q -E "$ident" || note "the banner does not carry the fixed build identity"
    echo "$banner" | sed -E "s/$ident//" | grep -q -E -f "$pat" && note "the banner names the build environment"
else
    echo "no source tree with a vmlinux given, banner not checked"
fi

echo "== build directory in the packages (expected in few places, should be a neutral path)"
if [ -n "$src" ]; then
    grep -r -l -a -F "$(dirname "$src")" "$work/x" 2>/dev/null | sed "s#^$work/x/##" | awk -F/ '{print $1}' | sort | uniq -c
fi

[ $rc -eq 0 ] && echo "check-packages: ok" || echo "check-packages: FAILED"
exit $rc
