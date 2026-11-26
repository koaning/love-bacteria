.PHONY: test unit smoke tokens music music-check run pico8 pico8-preview fetch-lovejs site serve clean

PICO8 ?= pico8
PORT ?= 8000

DIST := dist
SITE := $(DIST)/site
P8_STAGE := $(DIST)/pico8-preview
LOVEJS_DIR := site/lovejs
LOVEJS_BASE := https://raw.githubusercontent.com/2dengine/love.js/main
LOVEJS_FILES := player.js lua/normalize1.lua lua/normalize2.lua 11.5/love.js 11.5/love.wasm

# Everything CI checks: brain unit tests, cart smoke test, PICO-8 token
# budget, and that the cart's music data matches tools/music.lua.
test: unit smoke tokens music-check

unit:
	luajit tests/test_brain.lua

# Boots pico8/main.lua on a stubbed PICO-8 API and plays to game over.
smoke:
	luajit tests/cart_smoke.lua

# Approximate PICO-8 token count for the cart (limit 8192).
tokens:
	luajit tools/p8tokens.lua

# Compile the background-music score in tools/music.lua into the cart.
music:
	luajit tools/music.lua

music-check:
	luajit tools/music.lua --check

run: pico8

pico8:
	$(PICO8) -run pico8/mossballs.p8

# Download the love.js runtime once so `make serve` can run the browser preview player.
fetch-lovejs:
	mkdir -p "$(LOVEJS_DIR)/lua" "$(LOVEJS_DIR)/11.5"
	@for f in $(LOVEJS_FILES); do \
		echo "  $$f"; \
		curl -fsSL "$(LOVEJS_BASE)/$$f" -o "$(LOVEJS_DIR)/$$f" || exit 1; \
	done
	@echo "Downloaded love.js runtime files into $(LOVEJS_DIR)."

# Package the PICO-8 preview player (pico8/preview, a LÖVE stand-in for
# PICO-8) together with the cart into dist/mossballs-p8.love.
# `love dist/mossballs-p8.love` plays it on the desktop.
pico8-preview:
	rm -rf "$(P8_STAGE)"
	mkdir -p "$(P8_STAGE)/cart"
	cp pico8/preview/main.lua pico8/preview/conf.lua pico8/preview/synth.lua "$(P8_STAGE)/"
	cp pico8/mossballs.p8 pico8/*.lua "$(P8_STAGE)/cart/"
	rm -f "$(DIST)/mossballs-p8.love"
	cd "$(P8_STAGE)" && zip -9 -q -r ../mossballs-p8.love .
	@echo "Built $(DIST)/mossballs-p8.love"

# Static site hosting the PICO-8 cart in the browser:
#   /          PICO-8 cart on the preview player via love.js
#   /official/ real PICO-8 HTML export, only if $(PICO8) is installed
site: pico8-preview
	@for f in $(LOVEJS_FILES); do \
		if [ ! -f "$(LOVEJS_DIR)/$$f" ]; then \
			echo "Missing love.js runtime file $$f. Run: make fetch-lovejs"; \
			exit 1; \
		fi; \
	done
	rm -rf "$(SITE)"
	mkdir -p "$(SITE)"
	cp site/index.html site/coi-serviceworker.js "$(SITE)/"
	touch "$(SITE)/.nojekyll"
	cp "$(DIST)/mossballs-p8.love" "$(SITE)/"
	@for f in $(LOVEJS_FILES); do \
		mkdir -p "$(SITE)/$$(dirname $$f)"; \
		cp "$(LOVEJS_DIR)/$$f" "$(SITE)/$$f"; \
	done
	@if command -v "$(PICO8)" >/dev/null 2>&1; then \
		mkdir -p "$(SITE)/official"; \
		"$(PICO8)" pico8/mossballs.p8 -export "$(abspath $(SITE))/official/index.html" \
			&& echo "Exported official PICO-8 player to $(SITE)/official/"; \
	else \
		echo "($(PICO8) not found: skipping the official PICO-8 export; the preview player is still included)"; \
	fi
	@echo "Built $(SITE)/"

# Build the site and serve it (with the COOP/COEP headers love.js needs).
serve: site
	python3 tools/serve.py "$(SITE)" $(PORT)

clean:
	rm -rf "$(DIST)"
