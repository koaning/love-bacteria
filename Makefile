# Shared PICO-8 toolchain from koaning/geyser-pico8-template. Don't edit this
# file in a game: `copier update` overwrites it. Game-specific settings and
# targets go in game.mk.

GAME ?= game
TITLE ?= $(GAME)
# extra files copied next to the preview player's main.lua in the .love
# (e.g. a solver that pico8/preview/shots.lua requires)
PREVIEW_EXTRA ?=
# extra prerequisites of `make test` (game.mk can add its own checks)
TEST_EXTRA ?=

include game.mk

PICO8 ?= pico8
LOVE ?= love
PORT ?= 8000

CART := pico8/$(GAME).p8
export CART

DIST := dist
SITE := $(DIST)/site
P8_STAGE := $(DIST)/pico8-preview
P8_LOVE := $(DIST)/$(GAME)-p8.love
LOVEJS_DIR := site/lovejs
LOVEJS_BASE := https://raw.githubusercontent.com/2dengine/love.js/main
LOVEJS_FILES := player.js lua/normalize1.lua lua/normalize2.lua 11.5/love.js 11.5/love.wasm

UNIT_TESTS ?= $(sort $(wildcard tests/test_*.lua))

.PHONY: test unit smoke tokens music music-check run pico8 play pico8-preview \
	fetch-lovejs site serve screenshots clean

# Everything CI checks: unit tests, cart smoke test, PICO-8 token budget, and
# that the cart's sound data matches tools/scores.lua.
test: unit smoke tokens music-check $(TEST_EXTRA)

# Every tests/test_*.lua.
unit:
	@for t in $(UNIT_TESTS); do echo "luajit $$t"; luajit "$$t" || exit 1; done

# Boots pico8/main.lua on a stubbed PICO-8 API and plays it through its buttons.
smoke:
	luajit tests/cart_smoke.lua

# Approximate PICO-8 token count for the cart (limit 8192).
tokens:
	luajit tools/p8tokens.lua "$(CART)"

# Compile the sound effects and music scores in tools/scores.lua into the cart.
music:
	luajit tools/sfx.lua "$(CART)"

music-check:
	luajit tools/sfx.lua "$(CART)" --check

run: pico8

pico8:
	$(PICO8) -run "$(CART)"

# Export a standalone player (no editor behind it, so Esc reaches the
# cart's own menu) into dist/$(GAME).bin/ and open it on macOS.
play:
	mkdir -p "$(DIST)"
	rm -rf "$(DIST)/$(GAME).bin"
	"$(PICO8)" "$(CART)" -export "$(abspath $(DIST))/$(GAME).bin"
	@if [ "$$(uname)" = "Darwin" ]; then open "$(DIST)/$(GAME).bin/$(GAME).app"; \
	else echo "Built $(DIST)/$(GAME).bin/ (players for linux, windows, raspi, macOS)"; fi

# Download the love.js runtime once so `make serve` can run the browser preview player.
fetch-lovejs:
	mkdir -p "$(LOVEJS_DIR)/lua" "$(LOVEJS_DIR)/11.5"
	@for f in $(LOVEJS_FILES); do \
		echo "  $$f"; \
		curl -fsSL "$(LOVEJS_BASE)/$$f" -o "$(LOVEJS_DIR)/$$f" || exit 1; \
	done
	@echo "Downloaded love.js runtime files into $(LOVEJS_DIR)."

# Package the PICO-8 preview player (pico8/preview, a LÖVE stand-in for
# PICO-8) together with the cart into dist/$(GAME)-p8.love.
# `love dist/$(GAME)-p8.love` plays it on the desktop.
pico8-preview:
	rm -rf "$(P8_STAGE)"
	mkdir -p "$(P8_STAGE)/cart"
	cp pico8/preview/*.lua $(PREVIEW_EXTRA) "$(P8_STAGE)/"
	printf 'return { game = %s, title = %s }\n' '"$(GAME)"' '"$(TITLE)"' > "$(P8_STAGE)/game.lua"
	cp "$(CART)" pico8/*.lua "$(P8_STAGE)/cart/"
	rm -f "$(P8_LOVE)"
	cd "$(P8_STAGE)" && zip -9 -q -r "$(abspath $(P8_LOVE))" .
	@echo "Built $(P8_LOVE)"

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
	sed -e 's|@GAME@|$(GAME)|g' -e 's|@TITLE@|$(TITLE)|g' site/index.html > "$(SITE)/index.html"
	cp site/coi-serviceworker.js "$(SITE)/"
	touch "$(SITE)/.nojekyll"
	cp "$(P8_LOVE)" "$(SITE)/"
	@for f in $(LOVEJS_FILES); do \
		mkdir -p "$(SITE)/$$(dirname $$f)"; \
		cp "$(LOVEJS_DIR)/$$f" "$(SITE)/$$f"; \
	done
	@if command -v "$(PICO8)" >/dev/null 2>&1; then \
		mkdir -p "$(SITE)/official"; \
		"$(PICO8)" "$(CART)" -export "$(abspath $(SITE))/official/index.html" \
			&& echo "Exported official PICO-8 player to $(SITE)/official/"; \
	else \
		echo "($(PICO8) not found: skipping the official PICO-8 export; the preview player is still included)"; \
	fi
	@echo "Built $(SITE)/"

# Build the site and serve it (with the COOP/COEP headers love.js needs).
serve: site
	python3 tools/serve.py "$(SITE)" $(PORT)

# Play the scripted run in pico8/preview/shots.lua on the preview player,
# save the README screenshots into docs/screenshots/ and the title screen as
# the cart's label (needs LÖVE: brew install love; without a display use
# `make screenshots LOVE="xvfb-run -a love"`).
screenshots: pico8-preview
	mkdir -p docs/screenshots
	$(LOVE) "$(P8_LOVE)" --shots "$(abspath docs/screenshots)" --label "$(abspath $(DIST)/label.txt)"
	luajit tools/label.lua "$(DIST)/label.txt" "$(CART)"

clean:
	rm -rf "$(DIST)"
