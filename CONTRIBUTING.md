# Contributing

Thanks for helping improve `diffview.nvim`. This document covers the local setup
and a few conventions worth knowing before opening a PR.

## Development setup

Run the tests and formatter locally before pushing.

### Tests

```bash
make test                                                       # run the full suite
TEST_PATH=lua/diffview/tests/functional/foo_spec.lua make test  # a single file
```

Requires Neovim >= 0.10.0 with [`plenary.nvim`](https://github.com/nvim-lua/plenary.nvim);
see `scripts/test_init.lua` for how dependencies are fetched.

### Formatting (stylua)

The codebase is formatted with [stylua](https://github.com/JohnnyMorganz/StyLua)
**2.4.1 built with the `luajit` feature**. The `luajit` feature matters: the
default `stylua` build formats Lua 5.x syntax.

Install with:

```bash
cargo install stylua --locked --version 2.4.1 --features luajit
```

Then run:

```bash
stylua --check lua/   # CI equivalent; fails on any diff
stylua lua/           # apply formatting
```

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/). Keep the
subject terse; put rationale in the body when it's not obvious from the diff.

## Debugging

Set `DEBUG_DIFFVIEW=1` in the environment to enable debug logging.
