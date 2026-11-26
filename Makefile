.PHONY: test test-love mirror smoke tokens run pico8 pico8-preview love build appimage web fetch-lovejs site serve clean

PICO8 ?= pico8
PORT ?= 8000

DIST := dist
SITE := $(DIST)/site
P8_STAGE := $(DIST)/pico8-preview
LOVEJS_DIR := love/web/lovejs
LOVEJS_FILES := player.js lua/normalize1.lua lua/normalize2.lua 11.5/love.js 11.5/love.wasm

# Everything CI checks: LÖVE unit tests, the AI mirror match, the cart smoke
# test, and the PICO-8 token budget.
test: test-love mirror smoke tokens

test-love:
	$(MAKE) -C love test

# LÖVE brain vs PICO-8 brain, same seeds, must agree on every move.
mirror:
	luajit tests/mirror_match.lua

# Boots pico8/main.lua on a stubbed PICO-8 API and plays to game over.
smoke:
	luajit tests/cart_smoke.lua

# Approximate PICO-8 token count for the cart (limit 8192).
tokens:
	luajit tools/p8tokens.lua

run:
	$(MAKE) -C love run

pico8:
	$(PICO8) -run pico8/mossballs.p8

# Package the PICO-8 preview player (pico8/preview, a LÖVE stand-in for
# PICO-8) together with the cart into dist/mossballs-p8.love.
# `love dist/mossballs-p8.love` plays it on the desktop.
pico8-preview:
	rm -rf "$(P8_STAGE)"
	mkdir -p "$(P8_STAGE)/cart"
	cp pico8/preview/main.lua pico8/preview/conf.lua "$(P8_STAGE)/"
	cp pico8/mossballs.p8 pico8/*.lua "$(P8_STAGE)/cart/"
	rm -f "$(DIST)/mossballs-p8.love"
	cd "$(P8_STAGE)" && zip -9 -q -r ../mossballs-p8.love .
	@echo "Built $(DIST)/mossballs-p8.love"

# LÖVE packaging targets live in love/Makefile; outputs land in love/dist/.
love build web fetch-lovejs:
	$(MAKE) -C love $@

# Also copied to dist/ at the root, which is where the release workflow
# picks the AppImage up.
appimage:
	$(MAKE) -C love appimage
	mkdir -p "$(DIST)"
	cp love/dist/Mossballs-x86_64.AppImage "$(DIST)/Mossballs-x86_64.AppImage"
	@echo "Copied to $(DIST)/Mossballs-x86_64.AppImage"

# One static site with both editions:
#   /         landing page
#   /love/    LÖVE edition via love.js
#   /pico8/   PICO-8 cart on the preview player via love.js
#   /pico8-official/  real PICO-8 HTML export, only if $(PICO8) is installed
site: web pico8-preview
	rm -rf "$(SITE)"
	mkdir -p "$(SITE)/pico8" "$(SITE)/shots"
	cp site/index.html "$(SITE)/index.html"
	cp -R love/dist/web "$(SITE)/love"
	cp site/pico8.html "$(SITE)/pico8/index.html"
	cp "$(DIST)/mossballs-p8.love" "$(SITE)/pico8/"
	@for f in $(LOVEJS_FILES); do \
		mkdir -p "$(SITE)/pico8/$$(dirname $$f)"; \
		cp "$(LOVEJS_DIR)/$$f" "$(SITE)/pico8/$$f"; \
	done
	-cp docs/screenshots/*.png "$(SITE)/shots/" 2>/dev/null
	@if command -v "$(PICO8)" >/dev/null 2>&1; then \
		mkdir -p "$(SITE)/pico8-official"; \
		"$(PICO8)" pico8/mossballs.p8 -export "$(abspath $(SITE))/pico8-official/index.html" \
			&& echo "Exported official PICO-8 player to $(SITE)/pico8-official/"; \
	else \
		echo "($(PICO8) not found: skipping the official PICO-8 export; the preview player is still included)"; \
	fi
	@echo "Built $(SITE)/"

# Build the site and serve it (with the COOP/COEP headers love.js needs).
serve: site
	python3 tools/serve.py "$(SITE)" $(PORT)

clean:
	$(MAKE) -C love clean
	rm -rf "$(DIST)"
