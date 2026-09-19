.DEFAULT_GOAL := help
.PHONY: help build test check rules calls probe web-probe
# Scripts share object files, so even `make -j check` must build them in order.
.NOTPARALLEL:

help:
	@echo 'make build      Build and sign the input method'
	@echo 'make test       Rebuild the library and run composition/editing checks'
	@echo 'make check      Check rules, build, test, and verify the signed app'
	@echo 'make calls      Count text-client calls on fixed test text'
	@echo 'make probe      Build the native input test window'
	@echo 'make web-probe  Build the test window with CodeMirror (needs npm)'

build:
	@bash scripts/build.sh

test:
	@bash scripts/test.sh

rules:
	@python3 scripts/generate_combinations.py --check

check: rules build test
	@./dist/Sunarae.app/Contents/MacOS/Sunarae --self-check

calls:
	@bash scripts/test-client-calls.sh

probe:
	@bash scripts/build-probe.sh

web-probe: probe
	@bash scripts/build-web-probe.sh
