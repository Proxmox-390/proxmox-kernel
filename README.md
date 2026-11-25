# Proxmox kernel for IBM Z (s390x)

Packaging of the Proxmox VE kernel for the Proxmox-390 port. It builds the same packages as
Proxmox's own kernel packaging does on amd64 and arm64:

| Package | Content |
|---|---|
| `proxmox-kernel-<release>` | kernel image, modules, the OpenZFS modules (`zfs.ko`, `spl.ko`) |
| `proxmox-headers-<release>` | headers for building external modules (DKMS) |
| `proxmox-kernel-7.3`, `proxmox-headers-7.3` | series meta packages, depend on the latest of the above |
| `linux-tools-7.3` | perf |
| `proxmox-kernel-libc-dev` | user space headers; built, not meant to be published |

`<release>` is the kernel release, for example `7.3.6-1+s390x2-pve`.

## What is in this repository

No kernel source. The source is Proxmox's kernel repository, a kernel.org stable tree with
Proxmox's `debian/` packaging, taken at the release tag named in `upstream.conf`. This repository
adds what the s390x port needs on top:

| Path | Content |
|---|---|
| `upstream.conf` | upstream repository, tag, and the commits the tag and its ZFS submodule must have |
| `patches/packaging/` | patches to Proxmox's `debian/` directory (s390x as an architecture), with a `series` file |
| `patches/kernel/<topic>/` | kernel patches, ordered by `patches/kernel/series`; applied after Proxmox's own kernel patches |
| `config/config-s390x` | the full kernel configuration |
| `config/config-s390x.opts` | the s390x overrides that every build and every config refresh applies again |
| `changelog` | our changelog entries; they go on top of Proxmox's changelog |
| `scripts/`, `Makefile` | fetch, prepare, build, helpers |

The upstream tree is fetched as a shallow copy of the one tag instead of being a git submodule:
the full repository carries the complete kernel history (several GB), and a shallow submodule
cannot reliably check out a pinned commit that is not a branch head. The tag is verified against
the commit in `upstream.conf` after every fetch, so the build input is pinned as tightly as with
a submodule.

## Supported machines

The kernel is built for the z10 instruction set (`CONFIG_MARCH_Z10`, default tuning), like
Debian's s390x kernel. The port supports the zEnterprise 114/196 generation and newer; Debian 13
user space needs that generation as a minimum. Do not raise the architecture level.

## Building

On Debian 13 (trixie), s390x, with about 25 GB of free disk space:

    apt install git build-essential devscripts quilt
    make fetch                                  # upstream tree into ./upstream
    make prepare PKG_BUILD_DIR=/build/kernel        # source tree, see below
    (cd /build/kernel/proxmox-kernel-7.3-*/ && mk-build-deps -ir debian/control)
    make deb PKG_BUILD_DIR=/build/kernel

`make deb` alone does all steps once the build dependencies are installed (it removes nothing:
run `make clean` before preparing again). The packages end up in `PKG_BUILD_DIR`. `PKG_JOBS=<n>` limits
the parallelism, `make deb-continue` continues a failed build in the prepared tree.

`PKG_BUILD_DIR` defaults to `./build`. Its path is recorded in a few places of the result (assertion
messages of the ZFS modules, generated files of the headers package), so use a neutral path for
packages that are distributed.

What `make prepare` does, in order: export the pinned upstream commit with its submodules; apply
`patches/packaging`; install the config files; append `patches/kernel` to `debian/patches/series`;
put `changelog` on top of Proxmox's; write `debian/source-commit` (the commit of this repository)
and `debian/source-upstream`; regenerate `debian/control`. The packages name both in
`/usr/share/doc/<package>/SOURCE`. Builds from a tree with uncommitted changes are refused unless
`ALLOW_DIRTY=1` is set; the recorded commit then ends in `-dirty`.

The kernel is built with a fixed build user and host name (`build@proxmox-390`, set in
`debian/rules.d/s390x.mk`) and the changelog date as time stamp.
`scripts/check-packages.sh <directory with the .deb files> <source tree>` looks for the build
account, machine name and home directory in the files, module information and version banner
of the result; run it before packages leave the build machine.

Every build that is installed anywhere needs its own version: the Debian revision is part of the
kernel release name and of the package names, and modules are signed with a key that only exists
during the build.

## Adding kernel patches

    scripts/import-patches.sh <topic> <directory> <new version> "<changelog line>" [<patch>...]

for example

    scripts/import-patches.sh kvm-vsie ~/out/patches 7.3.6-1+s390x2 "KVM: s390: vsie: fix ..."

copies the patches (`git format-patch` output) to `patches/kernel/<topic>/`, replacing what the
topic held before, lists them in `patches/kernel/series`, test-applies the complete series
(Proxmox's patches, then ours) to the pinned upstream tree without fuzz, adds the changelog entry
and commits. Patches with a `Co-Authored-By` trailer are refused. To drop a topic, remove its
directory and its lines from the series by hand and add a changelog entry.

## Moving to a new upstream tag

1. Set `UPSTREAM_TAG`, `UPSTREAM_COMMIT` and `UPSTREAM_ZFS_COMMIT` in `upstream.conf`
   (`git ls-remote https://git.proxmox.com/git/proxmox-kernel.git 'refs/tags/proxmox/*'`; the
   commit is the peeled `^{}` entry; `make fetch` prints the ZFS commit it found if the pinned one
   does not match).
2. `make fetch`, then `make clean prepare`. If a packaging patch no longer applies, fix it in a
   scratch copy of the upstream `debian/` directory and replace the patch file.
3. Check the kernel patches. Step 2 copied them into the prepared tree;
   `cd <source>; QUILT_PATCHES=debian/patches quilt push -a --fuzz=0` shows whether they still
   apply. Drop what went upstream, refresh the rest.
4. `make updateconfig` and review the list of new options it prints. Enable what the port needs
   in `config/config-s390x.opts`, not by editing the full config.
5. Add a changelog entry `<upstream version>-<Proxmox revision>+s390x1` to `changelog`; older
   entries of ours that Proxmox's changelog now sorts above can stay.
6. Commit, `make deb`.

For a new kernel series (7.4, ...) the tag is on another upstream branch and the source package
name changes with it (`proxmox-kernel-7.4`); start `changelog` again with that name. When Debian
has an s390x config for the series, `make updateconfig CONFIG_BASE=<that config>` shows what
Debian changed for the architecture.

## Kernel configuration

`config/config-s390x` started as Debian's s390x configuration of the 7.3 series
(`linux-image-7.3.4+deb13-s390x`), so that every driver Debian ships for the architecture is
there. On top come Proxmox's overrides for all architectures (`debian/rules.d/config-common.opts`
in the upstream tree) and `config/config-s390x.opts`, which

- keeps modules uncompressed on install (the packaging strips and signs them itself),
- enables vfio-ccw and vfio-ap device pass-through, protected key support and kexec, none of which
  Debian's configuration has,
- switches off Rust, the Android binder and options of the common list that do not apply.

## Booting

The packages do not touch the boot configuration. On IBM Z the boot record is written by `zipl`;
the kernel hooks of `s390-tools` and of `proxmox-kernel-helper` run it when a kernel is installed
or removed.
