.PHONY: test run love build fetch-lovejs web clean appimage

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

LINUX_ARCH := x86_64
LOVE_VERSION := 11.5
LOVE_APPIMAGE := $(DIST_DIR)/love-$(LOVE_VERSION)-$(LINUX_ARCH).AppImage
LOVE_APPIMAGE_URL := https://github.com/love2d/love/releases/download/$(LOVE_VERSION)/love-$(LOVE_VERSION)-$(LINUX_ARCH).AppImage
APPIMAGETOOL := $(DIST_DIR)/appimagetool-$(LINUX_ARCH).AppImage
APPIMAGETOOL_URL := https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$(LINUX_ARCH).AppImage
APPIMAGE_SRC := build/appimage
APPIMAGE_OUT := $(DIST_DIR)/Sporeline-$(LINUX_ARCH).AppImage
APPDIR := $(DIST_DIR)/squashfs-root

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
		-x "Makefile" "README.md" "*.DS_Store" \
		-x "web/*" "assets/audio/music/demos/*" \
		-x "build/*"

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

# love.js runtime (2dengine). Upstream now ships a single 11.5 build:
# 11.5/love.js + 11.5/love.wasm (the old release/ and compat/ folders are gone).
LOVEJS_FILES := player.js lua/normalize1.lua lua/normalize2.lua 11.5/love.js 11.5/love.wasm

fetch-lovejs:
	mkdir -p "$(LOVEJS_DIR)/lua" "$(LOVEJS_DIR)/11.5"
	@for f in $(LOVEJS_FILES); do \
		echo "  $$f"; \
		curl -fsSL "$(LOVEJS_BASE)/$$f" -o "$(LOVEJS_DIR)/$$f" || exit 1; \
	done
	@echo "Downloaded love.js runtime files into $(LOVEJS_DIR)."

appimage: love
	@if [ "$(UNAME_S)" != "Linux" ]; then \
		echo "'make appimage' must be run on Linux (use the release GitHub Action from macOS)."; \
		exit 1; \
	fi
	@mkdir -p "$(DIST_DIR)"
	@if [ ! -f "$(LOVE_APPIMAGE)" ]; then \
		echo "Downloading $(LOVE_APPIMAGE_URL)"; \
		curl -fsSL -o "$(LOVE_APPIMAGE)" "$(LOVE_APPIMAGE_URL)"; \
		chmod +x "$(LOVE_APPIMAGE)"; \
	fi
	@if [ ! -f "$(APPIMAGETOOL)" ]; then \
		echo "Downloading $(APPIMAGETOOL_URL)"; \
		curl -fsSL -o "$(APPIMAGETOOL)" "$(APPIMAGETOOL_URL)"; \
		chmod +x "$(APPIMAGETOOL)"; \
	fi
	rm -rf "$(APPDIR)" "$(APPIMAGE_OUT)"
	cd "$(DIST_DIR)" && "./love-$(LOVE_VERSION)-$(LINUX_ARCH).AppImage" --appimage-extract >/dev/null
	cp "$(LOVE_ARCHIVE)" "$(APPDIR)/$(APP_SLUG).love"
	install -m 0755 "$(APPIMAGE_SRC)/AppRun" "$(APPDIR)/AppRun"
	rm -f "$(APPDIR)/love.desktop"
	cp "$(APPIMAGE_SRC)/sporeline.desktop" "$(APPDIR)/sporeline.desktop"
	@if [ -f "$(APPIMAGE_SRC)/sporeline.png" ]; then \
		rm -f "$(APPDIR)/love.svg" "$(APPDIR)/love.png"; \
		cp "$(APPIMAGE_SRC)/sporeline.png" "$(APPDIR)/sporeline.png"; \
	elif [ -f "$(APPDIR)/love.svg" ]; then \
		mv "$(APPDIR)/love.svg" "$(APPDIR)/sporeline.svg"; \
	fi
	@rm -f "$(APPDIR)/.DirIcon"
	@if [ -f "$(APPDIR)/sporeline.png" ]; then \
		ln -s sporeline.png "$(APPDIR)/.DirIcon"; \
	elif [ -f "$(APPDIR)/sporeline.svg" ]; then \
		ln -s sporeline.svg "$(APPDIR)/.DirIcon"; \
	fi
	APPIMAGE_EXTRACT_AND_RUN=1 "./$(APPIMAGETOOL)" "$(APPDIR)" "$(APPIMAGE_OUT)"
	rm -rf "$(APPDIR)"
	@echo "Built $(APPIMAGE_OUT)"

web: love
	rm -rf "$(WEB_DIR)"
	mkdir -p "$(WEB_DIR)"
	cp "$(LOVE_ARCHIVE)" "$(WEB_DIR)/$(APP_SLUG).love"
	cp "$(WEB_SOURCE_DIR)/index.html" "$(WEB_DIR)/index.html"
	cp "$(WEB_SOURCE_DIR)/_headers" "$(WEB_DIR)/_headers"
	cp "$(WEB_SOURCE_DIR)/.htaccess" "$(WEB_DIR)/.htaccess"
	@for f in $(LOVEJS_FILES); do \
		if [ ! -f "$(LOVEJS_DIR)/$$f" ]; then \
			echo "Missing love.js runtime file $$f. Run: make fetch-lovejs"; \
			exit 1; \
		fi; \
		mkdir -p "$(WEB_DIR)/$$(dirname $$f)"; \
		cp "$(LOVEJS_DIR)/$$f" "$(WEB_DIR)/$$f"; \
	done
	@echo "Prepared web bundle in $(WEB_DIR)."
