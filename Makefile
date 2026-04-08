.PHONY: test run love build clean

APP_NAME := Bacteria
APP_SLUG := bacteria
DIST_DIR := dist
LOVE_ARCHIVE := $(DIST_DIR)/$(APP_SLUG).love
APP_BUNDLE := $(DIST_DIR)/$(APP_NAME).app
LOVE_APP := /Applications/love.app
UNAME_S := $(shell uname -s)

test:
	luajit tests/run.lua

run:
	love .

clean:
	rm -rf $(DIST_DIR)

$(DIST_DIR):
	mkdir -p $(DIST_DIR)

love: $(LOVE_ARCHIVE)

$(LOVE_ARCHIVE): | $(DIST_DIR)
	rm -f "$(LOVE_ARCHIVE)"
	zip -9 -r "$(LOVE_ARCHIVE)" . \
		-x ".git" ".git/*" ".gitkeep" ".context/*" "dist/*" ".github/*" "tests/*" \
		-x "HANDOFF.md" "Makefile" "README.md" "*.DS_Store"

build: love
ifeq ($(UNAME_S),Darwin)
	@if [ ! -d "$(LOVE_APP)" ]; then \
		echo "Missing $(LOVE_APP). Install LÖVE first."; \
		exit 1; \
	fi
	rm -rf "$(APP_BUNDLE)"
	cp -R "$(LOVE_APP)" "$(APP_BUNDLE)"
	cp "$(LOVE_ARCHIVE)" "$(APP_BUNDLE)/Contents/Resources/$(APP_SLUG).love"
	@echo "Built $(APP_BUNDLE)"
else
	@echo "Standalone app bundling is currently implemented for macOS only."
	@echo "Created archive: $(LOVE_ARCHIVE)"
endif
