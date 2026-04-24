.PHONY: all
all: dev test

TEST_PATH := $(if $(TEST_PATH),$(TEST_PATH),lua/diffview/tests/)
export TEST_PATH

# Usage:
# 	Run all tests:
# 	$ make test
#
# 	Run tests for a specific path:
# 	$ TEST_PATH=tests/some/path make test
.PHONY: test
test:
	nvim --headless -i NONE -n -u scripts/test_init.lua -c \
		"PlenaryBustedDirectory $(TEST_PATH) { minimal_init = './scripts/test_init.lua' }"

.PHONY: check-config-schema
check-config-schema:
	nvim --headless -i NONE -n -u NONE -c "luafile scripts/check_config_schema.lua"

# Run lua-language-server in --check mode. Requires `lua-language-server` on
# PATH and the neodev types fetched via `make dev`. Fails if any diagnostics
# are reported (after the suppressions configured in `.luarc.json`).
#
# VIMRUNTIME is resolved from nvim so `.luarc.json` can reference it via a
# generated absolute path (LuaLS does not expand env vars inside JSON).
#
# Source code is checked strictly. Tests are checked separately and the job
# is advisory (see `type-check-tests`) because the Luassert modifier chains
# (`assert.is_not_nil`, `assert.has_no.errors`, etc.) are not fully covered
# by the static type annotations plenary.nvim ships with.
.PHONY: type-check
type-check: dev .luarc.source.json
	@rm -rf .luals-log
	lua-language-server \
		--check=lua/diffview \
		--configpath="$(CURDIR)/.luarc.source.json" \
		--check_format=json \
		--logpath=.luals-log
	@if [ -f .luals-log/check.json ] && [ -s .luals-log/check.json ] && [ "$$(cat .luals-log/check.json)" != "[]" ]; then \
		echo "LuaLS diagnostics (source): see .luals-log/check.json"; \
		exit 1; \
	fi
	@echo "No LuaLS diagnostics in source."

# Advisory type-check across the test tree. Emits diagnostics for inspection
# but does not fail; the source-code gate is `type-check`.
.PHONY: type-check-tests
type-check-tests: dev .luarc.generated.json
	@rm -rf .luals-log-tests
	lua-language-server \
		--check=lua/diffview/tests \
		--configpath="$(CURDIR)/.luarc.generated.json" \
		--check_format=json \
		--logpath=.luals-log-tests \
		|| true
	@if [ -f .luals-log-tests/check.json ] && [ -s .luals-log-tests/check.json ] && [ "$$(cat .luals-log-tests/check.json)" != "[]" ]; then \
		echo "LuaLS diagnostics (tests, advisory): see .luals-log-tests/check.json"; \
	else \
		echo "No LuaLS diagnostics in tests."; \
	fi

# Source-only variant: adds Lua.workspace.ignoreDir so LuaLS skips the tests
# subtree during the scan.
.PHONY: .luarc.source.json
.luarc.source.json: .luarc.generated.json
	@jq '. + {"Lua.workspace.ignoreDir": ["tests", "lua/diffview/tests"]}' \
		.luarc.generated.json > .luarc.source.json

# Generate an LuaLS config with VIMRUNTIME expanded to an absolute path.
# Expand $VIMRUNTIME and resolve relative `./...` paths against the project
# root — LuaLS resolves relative workspace.library entries against the
# --check root (`lua/`), which would point them into the wrong subtree.
.PHONY: .luarc.generated.json
.luarc.generated.json:
	@VIMRUNTIME="$$(nvim --headless -c 'lua io.write(vim.env.VIMRUNTIME)' -c 'qa' 2>&1 | head -1)"; \
		sed -e "s|\$$VIMRUNTIME|$$VIMRUNTIME|g" \
		    -e "s|\"\\./|\"$(CURDIR)/|g" \
		    .luarc.json > .luarc.generated.json

.PHONY: dev
dev: .dev/lua/nvim .dev/lua/plenary

.dev/lua/nvim:
	mkdir -p "$@"
	git clone --filter=blob:none https://github.com/folke/neodev.nvim.git "$@/repo"
	cd "$@/repo" && git -c advice.detachedHead=false checkout ce9a2e8eaba5649b553529c5498acb43a6c317cd
	cp	"$@/repo/types/nightly/uv.lua" \
		"$@/repo/types/nightly/cmd.lua" \
		"$@/repo/types/nightly/alias.lua" \
		"$@/"
	rm -rf "$@/repo"

# Plenary is fetched for its Busted runner and luassert-style assertion
# module, which are used throughout `lua/diffview/tests/`. Having the Lua
# sources on disk lets LuaLS resolve `assert.equals`, `assert.truthy`, etc.
.dev/lua/plenary:
	mkdir -p "$(dir $@)"
	git clone --depth 1 --filter=blob:none \
		https://github.com/nvim-lua/plenary.nvim.git "$@"
	rm -rf "$@/.git"

.PHONY: clean
clean:
	rm -rf .tests .dev .luals-log .luals-log-tests .luarc.generated.json .luarc.source.json
