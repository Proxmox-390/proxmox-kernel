# Proxmox kernel packages for IBM Z (s390x).
#
# This repository holds no kernel source. It fetches Proxmox's kernel tree at
# the tag pinned in upstream.conf, applies patches/packaging to its debian/
# directory, adds patches/kernel to its patch series and builds the packages.
# See README.md.

include upstream.conf

SOURCE_PKG := $(shell dpkg-parsechangelog -l changelog -SSource)
VERSION := $(shell dpkg-parsechangelog -l changelog -SVersion)
UPSTREAM_VERSION := $(firstword $(subst -, ,$(VERSION)))

# where the upstream tree is fetched to (a git repository, about 300 MB packed)
UPSTREAM_DIR ?= $(CURDIR)/upstream
# where the source is prepared and built; the path ends up in a few binaries,
# use a neutral one for packages meant for distribution
BUILD_DIR ?= $(CURDIR)/build
SRC_DIR = $(BUILD_DIR)/$(SOURCE_PKG)-$(UPSTREAM_VERSION)
JOBS ?= $(shell nproc)

export UPSTREAM_DIR

.PHONY: all
all: deb

.PHONY: fetch
fetch:
	scripts/fetch-upstream.sh

.PHONY: prepare
prepare: fetch
	scripts/prepare-source.sh '$(SRC_DIR)'

.PHONY: deb
deb: prepare
	cd '$(SRC_DIR)' && dpkg-checkbuilddeps && dpkg-buildpackage -b -uc -us --jobs=$(JOBS)
	@echo "packages for $(VERSION) are in $(BUILD_DIR)/"

# continue a failed build in the prepared tree
.PHONY: deb-continue
deb-continue:
	cd '$(SRC_DIR)' && dpkg-buildpackage -b -uc -us -nc --jobs=$(JOBS)

# refresh config/config-s390x for the pinned upstream tree, see README.md
.PHONY: updateconfig
updateconfig: fetch
	scripts/update-config.sh '$(BUILD_DIR)/updateconfig'

.PHONY: check
check:
	scripts/check-public.sh

.PHONY: clean
clean:
	rm -rf '$(SRC_DIR)' '$(BUILD_DIR)/updateconfig'

.PHONY: distclean
distclean:
	rm -rf '$(BUILD_DIR)' '$(UPSTREAM_DIR)'
