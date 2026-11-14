ADDON_FILES=$(filter-out %.test.lua,$(wildcard *.lua)) $(wildcard *.toc) $(wildcard *.xml)
WOW_INTERFACE_DIR=/tmp/WoW/Interface/Addons

-include personal.mak

KACKLA_DIR=${WOW_INTERFACE_DIR}/kackla

all: ${ADDON_FILES}
	mkdir -p ${KACKLA_DIR}
	cp $? ${KACKLA_DIR}

test:
	lua kackla.test.lua

# Release files for a GitHub release, upload both as release assets so
# strongbox can install it: dist/kackla-VERSION.zip and dist/release.json
VERSION=$(shell sed -n 's/^\#\# Version: *//p' kackla.toc)
DIST_DIR=dist
DIST_ZIP=kackla-${VERSION}.zip

dist: test
	rm -rf ${DIST_DIR}
	mkdir -p ${DIST_DIR}/kackla
	cp ${ADDON_FILES} ${DIST_DIR}/kackla
	cd ${DIST_DIR} && zip -qr ${DIST_ZIP} kackla
	lua scripts/release_json.lua ${VERSION} ${DIST_ZIP} $(wildcard *.toc) > ${DIST_DIR}/release.json
	rm -rf ${DIST_DIR}/kackla
	@echo "Upload as release assets: ${DIST_DIR}/${DIST_ZIP} ${DIST_DIR}/release.json"

clean:
	rm -rf ${KACKLA_DIR} ${DIST_DIR}

.PHONY: test dist clean
