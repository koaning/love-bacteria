.PHONY: test run love build fetch-lovejs web clean

APP_NAME := Sporeline
APP_SLUG := sporeline
DIST_DIR := dist
LOVE_ARCHIVE := $(DIST_DIR)/$(APP_SLUG).love
APP_BUNDLE := $(DIST_DIR)/$(APP_NAME).app
WEB_DIR := $(DIST_DIR)/web
WEB_SOURCE_DIR := web
LOVEJS_DIR := $(WEB_SOURCE_DIR)/lovejs
LOVEJS_BASE := https://raw.githubusercontent.com/2dengine/love.js/main
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

love: | $(DIST_DIR)
	rm -f "$(LOVE_ARCHIVE)"
	zip -9 -r "$(LOVE_ARCHIVE)" . \
		-x ".git" ".git/*" ".gitkeep" ".context/*" "dist/*" ".github/*" "tests/*" \
		-x "Makefile" "README.md" "*.DS_Store" "web/*" "assets/audio/music/demos/*"

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

fetch-lovejs:
	mkdir -p "$(LOVEJS_DIR)/lua" "$(LOVEJS_DIR)/11.5/release" "$(LOVEJS_DIR)/11.5/compat"
	curl -fsSL "$(LOVEJS_BASE)/player.js" -o "$(LOVEJS_DIR)/player.js"
	curl -fsSL "$(LOVEJS_BASE)/lua/normalize1.lua" -o "$(LOVEJS_DIR)/lua/normalize1.lua"
	curl -fsSL "$(LOVEJS_BASE)/lua/normalize2.lua" -o "$(LOVEJS_DIR)/lua/normalize2.lua"
	curl -fsSL "$(LOVEJS_BASE)/11.5/release/love.js" -o "$(LOVEJS_DIR)/11.5/release/love.js"
	curl -fsSL "$(LOVEJS_BASE)/11.5/release/love.wasm" -o "$(LOVEJS_DIR)/11.5/release/love.wasm"
	curl -fsSL "$(LOVEJS_BASE)/11.5/release/love.worker.js" -o "$(LOVEJS_DIR)/11.5/release/love.worker.js"
	curl -fsSL "$(LOVEJS_BASE)/11.5/compat/love.js" -o "$(LOVEJS_DIR)/11.5/compat/love.js"
	curl -fsSL "$(LOVEJS_BASE)/11.5/compat/love.wasm" -o "$(LOVEJS_DIR)/11.5/compat/love.wasm"
	@echo "Downloaded love.js runtime files into $(LOVEJS_DIR)."

web: love
	rm -rf "$(WEB_DIR)"
	mkdir -p "$(WEB_DIR)"
	cp "$(LOVE_ARCHIVE)" "$(WEB_DIR)/$(APP_SLUG).love"
	cp "$(WEB_SOURCE_DIR)/index.html" "$(WEB_DIR)/index.html"
	cp "$(WEB_SOURCE_DIR)/_headers" "$(WEB_DIR)/_headers"
	cp "$(WEB_SOURCE_DIR)/.htaccess" "$(WEB_DIR)/.htaccess"
	@if [ -f "$(LOVEJS_DIR)/player.js" ] \
		&& [ -f "$(LOVEJS_DIR)/lua/normalize1.lua" ] \
		&& [ -f "$(LOVEJS_DIR)/lua/normalize2.lua" ] \
		&& [ -f "$(LOVEJS_DIR)/11.5/release/love.js" ] \
		&& [ -f "$(LOVEJS_DIR)/11.5/release/love.wasm" ] \
		&& [ -f "$(LOVEJS_DIR)/11.5/release/love.worker.js" ] \
		&& [ -f "$(LOVEJS_DIR)/11.5/compat/love.js" ] \
		&& [ -f "$(LOVEJS_DIR)/11.5/compat/love.wasm" ]; then \
		mkdir -p "$(WEB_DIR)/lua" "$(WEB_DIR)/11.5/release" "$(WEB_DIR)/11.5/compat"; \
		cp "$(LOVEJS_DIR)/player.js" "$(WEB_DIR)/player.js"; \
		cp "$(LOVEJS_DIR)/lua/normalize1.lua" "$(WEB_DIR)/lua/normalize1.lua"; \
		cp "$(LOVEJS_DIR)/lua/normalize2.lua" "$(WEB_DIR)/lua/normalize2.lua"; \
		cp "$(LOVEJS_DIR)/11.5/release/love.js" "$(WEB_DIR)/11.5/release/love.js"; \
		cp "$(LOVEJS_DIR)/11.5/release/love.wasm" "$(WEB_DIR)/11.5/release/love.wasm"; \
		cp "$(LOVEJS_DIR)/11.5/release/love.worker.js" "$(WEB_DIR)/11.5/release/love.worker.js"; \
		cp "$(LOVEJS_DIR)/11.5/compat/love.js" "$(WEB_DIR)/11.5/compat/love.js"; \
		cp "$(LOVEJS_DIR)/11.5/compat/love.wasm" "$(WEB_DIR)/11.5/compat/love.wasm"; \
	else \
		echo "Missing love.js runtime files. Run: make fetch-lovejs"; \
		exit 1; \
	fi
	@echo "Prepared web bundle in $(WEB_DIR)."
