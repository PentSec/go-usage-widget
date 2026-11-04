# Makefile — daily commands for the plasmoid.
#
# `make`        run every check that does not need a Plasma session
# `make run`    load the applet from the working tree in a window
# `make install` install or upgrade it in the current user's session

PACKAGE_ID := io.github.pentsec.gousage
PACKAGE_DIR := package
BUILD_DIR := build

.PHONY: all test test-logic test-helper check-metadata lint run install uninstall package clean

all: test check-metadata

## Tests --------------------------------------------------------------------

test: test-logic test-helper

test-logic:
	@echo "== logic (node, default timezone)"
	node --test
	@echo "== logic (node, America/New_York)"
	TZ=America/New_York node --test
	@echo "== logic (node, Asia/Tokyo)"
	TZ=Asia/Tokyo node --test

test-helper:
	@echo "== helper (python unittest)"
	python3 -m unittest discover -s tests

## Static checks ------------------------------------------------------------

check-metadata:
	@python3 -c "import json; json.load(open('$(PACKAGE_DIR)/metadata.json'))"
	@python3 -c "import xml.dom.minidom as m; m.parse('$(PACKAGE_DIR)/contents/config/main.xml')"
	@echo "metadata.json and main.xml parse"

lint:
	qmllint $(shell find $(PACKAGE_DIR) -name '*.qml')

## Developer loop -----------------------------------------------------------

run:
	plasmawindowed $(CURDIR)/$(PACKAGE_DIR)

install:
	@if kpackagetool6 --type Plasma/Applet --show $(PACKAGE_ID) >/dev/null 2>&1; then \
		kpackagetool6 --type Plasma/Applet --upgrade $(CURDIR)/$(PACKAGE_DIR); \
	else \
		kpackagetool6 --type Plasma/Applet --install $(CURDIR)/$(PACKAGE_DIR); \
	fi

uninstall:
	kpackagetool6 --type Plasma/Applet --remove $(PACKAGE_ID)

## Distribution -------------------------------------------------------------

package:
	@mkdir -p $(BUILD_DIR)
	@rm -f $(BUILD_DIR)/$(PACKAGE_ID).plasmoid
	cd $(PACKAGE_DIR) && zip -qr ../$(BUILD_DIR)/$(PACKAGE_ID).plasmoid . \
		-x '*/__pycache__/*' -x '*.pyc'
	@echo "built $(BUILD_DIR)/$(PACKAGE_ID).plasmoid"

clean:
	rm -rf $(BUILD_DIR)
	find . -name '__pycache__' -type d -prune -exec rm -rf {} +
