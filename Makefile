.PHONY: test run

test:
	luajit tests/run.lua

run:
	love .
