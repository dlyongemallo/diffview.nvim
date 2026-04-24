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

# Run lua-language-server in --check mode. Requires `lua-language-server`,
# `nvim` (used to resolve VIMRUNTIME), `jq` (used to derive
# `.luarc.source.json`), and `git` (used by `make dev` to fetch sources)
# on PATH, plus the neodev/plenary sources fetched via `make dev`. Fails
# if any diagnostics are reported (after the suppressions configured in
# `.luarc.json`).
#
# VIMRUNTIME is resolved from nvim so `.luarc.json` can reference it via a
# generated absolute path (LuaLS does not expand env vars inside JSON).
#
# Source code is checked strictly. Tests are checked separately and the job
# is advisory (see `type-check-tests`) because the Luassert modifier chains
# (`assert.is_not_nil`, `assert.has_no.errors`, etc.) are not fully covered
# by the static type annotations `plenary.nvim` ships with.
.PHONY: type-check
type-check: dev .luarc.source.json
	@rm -rf .luals-log
	lua-language-server \
		--check=lua/diffview \
		--configpath="$(CURDIR)/.luarc.source.json" \
		--check_format=json \
		--logpath=.luals-log
	@if [ -s .luals-log/check.json ] && [ "$$(jq 'length' .luals-log/check.json)" != "0" ]; then \
		echo "LuaLS diagnostics (source): see .luals-log/check.json"; \
		exit 1; \
	fi
	@echo "No LuaLS diagnostics in source."

# Advisory type-check across the test tree. Emits diagnostics for inspection
# but does not fail; the source-code gate is `type-check`. The exit status
# is captured so a LuaLS crash or missing binary is surfaced distinctly
# from a clean run with no diagnostics (in both cases `check.json` is
# absent, but only the latter means the tests are clean).
.PHONY: type-check-tests
type-check-tests: dev .luarc.generated.json
	@rm -rf .luals-log-tests
	@status=0; \
	lua-language-server \
		--check=lua/diffview/tests \
		--configpath="$(CURDIR)/.luarc.generated.json" \
		--check_format=json \
		--logpath=.luals-log-tests || status=$$?; \
	if [ "$$status" -ne 0 ]; then \
		echo "LuaLS check (tests, advisory) did not run (exit $$status); skipping."; \
	elif [ -s .luals-log-tests/check.json ] && [ "$$(jq 'length' .luals-log-tests/check.json)" != "0" ]; then \
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

# Generate a LuaLS config with VIMRUNTIME expanded to an absolute path.
# Expand $VIMRUNTIME and resolve relative `./...` paths against the project
# root — LuaLS resolves relative workspace.library entries against the
# --check root (`lua/diffview` or `lua/diffview/tests`), which would point
# them into the wrong subtree.
#
# nvim is invoked with `-u NONE -i NONE -n` so user config/plugins cannot
# emit stray output, and stderr is discarded so warnings (e.g., about a
# missing $HOME on minimal CI containers) cannot be mistaken for the
# VIMRUNTIME value. `io.write` (no newline) gives a clean single token.
.PHONY: .luarc.generated.json
.luarc.generated.json:
	@VIMRUNTIME="$$(nvim --headless -u NONE -i NONE -n \
		-c 'lua io.write(vim.env.VIMRUNTIME)' -c 'qa' 2>/dev/null)"; \
	if [ -z "$$VIMRUNTIME" ]; then \
		echo "error: failed to resolve VIMRUNTIME from nvim (is nvim on PATH?)" >&2; \
		exit 1; \
	fi; \
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
# Pinned to a specific commit so upstream changes cannot silently introduce
# new diagnostics in the type-check job; bump intentionally when needed.
PLENARY_REV := 74b06c6c75e4eeb3108ec01852001636d85a932b
.dev/lua/plenary:
	mkdir -p "$@"
	cd "$@" && \
		git init -q && \
		git remote add origin https://github.com/nvim-lua/plenary.nvim.git && \
		git -c advice.detachedHead=false fetch --depth 1 --filter=blob:none \
			origin $(PLENARY_REV) && \
		git -c advice.detachedHead=false checkout FETCH_HEAD
	rm -rf "$@/.git"

.PHONY: clean
clean:
	rm -rf .tests .dev .luals-log .luals-log-tests .luarc.generated.json .luarc.source.json
