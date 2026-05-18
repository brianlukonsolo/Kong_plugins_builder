MDIR = ./
PONGO_VERSION := 2.12.0
KONG_VERSION := 2.8.4.11

PLUGIN_DIRS := $(wildcard custom-plugins/*)

.PHONY: build-venv
build-venv:
	@mkdir -p .venv/bin
	@echo "----> DOWNLOADING PONGO..."
	@git clone https://github.com/Kong/kong-pongo.git --depth 1 --branch $(PONGO_VERSION) .venv/pongo || true
	@ln -sf $$(pwd)/.venv/pongo/pongo.sh $$(pwd)/.venv/bin/pongo
	@echo "export PATH=$$(pwd)/.venv/bin:$$PATH" > .venv/env
	@echo "export KONG_VERSION=$(KONG_VERSION)" >> .venv/env
	@echo "----> READY!"

.PHONY: package
package: build-venv
	@echo "----> PACKAGING PLUGINS"
	@mkdir -p build/out
	@rm -f build/out/*.rock
	@rm -rf build/out/native
	@set -e; \
	for plugin_dir in $(PLUGIN_DIRS); do \
		plugin_name=$$(basename "$$plugin_dir"); \
		if ls "$$plugin_dir"/*.rockspec >/dev/null 2>&1; then \
			echo "----> PACKAGING $$plugin_dir"; \
			(cd "$$plugin_dir" && . ../../.venv/env && pongo build --force && pongo pack); \
			mv "$$plugin_dir"/*.rock build/out/; \
		fi; \
		if ls "$$plugin_dir"/rocks/*.rock >/dev/null 2>&1; then \
			echo "----> COPYING PREBUILT ROCKS FROM $$plugin_dir/rocks"; \
			cp "$$plugin_dir"/rocks/*.rock build/out/; \
		fi; \
		if ls "$$plugin_dir"/dist/*.rock >/dev/null 2>&1; then \
			echo "----> COPYING PREBUILT ROCKS FROM $$plugin_dir/dist"; \
			cp "$$plugin_dir"/dist/*.rock build/out/; \
		fi; \
		if [ -d "$$plugin_dir/native" ]; then \
			echo "----> STAGING NATIVE LIBRARIES FROM $$plugin_dir/native"; \
			mkdir -p "build/out/native/$$plugin_name"; \
			cp -R "$$plugin_dir/native/." "build/out/native/$$plugin_name/"; \
		fi; \
	done
	@echo "----> PACKAGED ROCKS IN build/out/"

.PHONY: test
test: build-venv package
	@echo "----> TESTING PLUGINS"
	@set -e; \
	for plugin_dir in $(PLUGIN_DIRS); do \
		if ls "$$plugin_dir"/*.rockspec >/dev/null 2>&1; then \
			echo "----> TESTING $$plugin_dir"; \
			(cd "$$plugin_dir" && . ../../.venv/env && pongo run); \
		fi; \
	done

.PHONY: expunge
expunge:
	@echo "!! DELETING VIRTUAL ENV"
	@. .venv/env && pongo down || true
	@rm -rf ./.venv
	@echo "!! DELETING BUILT PACKAGES"
	@rm -rf ./build
	@echo "!! DELETING PONGO IMAGE"
	@docker image rm -f kong-pongo:$(PONGO_VERSION)-$(KONG_VERSION) > /dev/null 2>&1 || true
