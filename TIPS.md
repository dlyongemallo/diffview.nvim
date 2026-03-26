# Tips and FAQ

Common questions, useful patterns, and known compatibility issues.

## General Tips

- **Hide untracked files:**
  - `DiffviewOpen -uno`
- **Exclude certain paths:**
  - `DiffviewOpen -- :!exclude/this :!and/this`
- **Run as if git was started in a specific directory:**
  - `DiffviewOpen -C/foo/bar/baz`
- **Diff the index against a git rev:**
  - `DiffviewOpen HEAD~2 --cached`
  - Defaults to `HEAD` if no rev is given.
- **Compare against merge-base (PR-style diff):**
  - `DiffviewOpen origin/main...HEAD --merge-base`
  - Shows only changes introduced since branching.
- **Use as a merge tool from the command line:**
  - `:DiffviewOpen` automatically detects conflicts during a merge, rebase,
    cherry-pick, or revert, so it can replace `git mergetool`. Add a git alias
    for convenience:
    ```gitconfig
    # In ~/.gitconfig:
    [alias]
        diffview = "!nvim -c DiffviewOpen"
    ```
  - Then run `git diffview` after a conflicted merge or rebase. Stage
    resolved files with `-` in the file panel before quitting, or with
    `git add` afterwards.
- **Trace line evolution:**
  - Visual select lines, then `:'<,'>DiffviewFileHistory --follow`
  - Or for single line: `:.DiffviewFileHistory --follow`
- **Diff two arbitrary files (like `vimdiff`):**
  - `:DiffviewDiffFiles file1 file2`
  - This works without a VCS repository.
  - To use it as a replacement for `nvim -d`, add a shell function:
    ```bash
    dvdiff() {
      nvim -c "DiffviewDiffFiles ${1// /\\ } ${2// /\\ }"
    }
    ```
  - Then run `dvdiff file1 file2` from the command line.

## Understanding Revision Arguments

- `DiffviewOpen HEAD~5` compares HEAD~5 to working tree (all changes since)
- `DiffviewOpen HEAD~5..HEAD` compares HEAD~5 to HEAD (excludes working tree changes)
- `DiffviewOpen HEAD~5^..HEAD~5` shows changes within that single commit
- For viewing a specific commit's changes, use `DiffviewFileHistory` instead

## FAQ

- **Q: How do I get the diagonal lines in place of deleted lines in
  diff-mode?**
  - A: Change your `:h 'fillchars'`:
    - (vimscript): `set fillchars+=diff:╱`
    - (Lua): `vim.opt.fillchars:append { diff = "╱" }`
  - Note: whether or not the diagonal lines will line up nicely will depend on
    your terminal emulator. The terminal used in the screenshots is Kitty.
- **Q: How do I jump between hunks in the diff?**
  - A: Use `[c` and `]c`
  - `:h jumpto-diffs`

## Diff Display

- **Better diff display (changes shown as add+delete instead of modification):**
  - Set Neovim's `diffopt` to use a better algorithm:
    - `vim.opt.diffopt:append { "algorithm:histogram" }`
  - Alternatives: `algorithm:patience` or `algorithm:minimal`
  - This affects how Neovim's built-in diff mode displays changes.
- **VSCode-style character-level highlighting:**
  - Pair diffview with
    [diffchar.vim](https://github.com/rickhowe/diffchar.vim) for precise
    character/word-level diff highlights. See
    [Companion Plugins](README.md#companion-plugins) for setup details.

## LSP Diagnostics in Diff Buffers

- Diagnostics only appear for the working tree (LOCAL) side of diffs.
- When comparing commits (e.g., `DiffviewOpen main..HEAD`), neither side is the
  working tree, so LSP won't attach to those buffers.
- To see diagnostics, compare against the working tree: `DiffviewOpen main`
  (not `main..HEAD`). The right side will show your current files with
  diagnostics.
- Inlay hints are automatically disabled for non-working-tree buffers to
  prevent position mismatch errors.

## Neogit Integration

- Configure [Neogit](https://github.com/NeogitOrg/neogit) with
  `integrations = { diffview = true }` for seamless integration.

## Customizing Default Keymaps

The default keymaps (`<leader>e`, `<leader>b`, `<leader>c*`) may conflict
with your configuration. Override them in your setup:

```lua
local actions = require("diffview.actions")
require("diffview").setup({
  keymaps = {
    view = {
      -- Use localleader instead to avoid conflicts
      { "n", "<localleader>e", actions.focus_files },
      { "n", "<localleader>b", actions.toggle_files },
      -- Or disable specific mappings
      { "n", "<leader>e", false },
    },
  },
})
```

## Platform Notes

- **MSYS2/Cygwin on Windows:**
  - If you use MSYS2 or Cygwin git with native Windows Neovim, path conversion
    is handled automatically via `cygpath`. Ensure `cygpath` is on your `PATH`.
    Alternatively, install [Git for Windows](https://gitforwindows.org/) which
    uses native Windows paths and avoids the issue entirely.

## Known Compatibility Issues

Some plugins may conflict with diffview's window layout or keymaps. Here are
known issues and workarounds:

- **lens.vim (automatic window resizing):**
  - [camspiers/lens.vim](https://github.com/camspiers/lens.vim) automatically
    resizes windows based on focus, which interferes with diffview's layout.
  - **Workaround:** Configure lens.vim to exclude diffview filetypes:
    ```lua
    -- In your lens.vim or lens.nvim config:
    vim.g['lens#disabled_filetypes'] = {
      'DiffviewFiles', 'DiffviewFileHistory', 'DiffviewFileHistoryPanel'
    }
    ```

- **Scrollbind misalignment with context or winbar plugins:**
  - Plugins that add lines at the top of windows (code context, breadcrumbs)
    cause the diff panes to fall out of visual sync.

  - **[nvim-treesitter-context](https://github.com/nvim-treesitter/nvim-treesitter-context):**
    Two steps are needed. First, configure treesitter-context to disable
    itself for diffview buffers using the `on_attach` callback:
    ```lua
    require('treesitter-context').setup({
      on_attach = function(buf)
        return not vim.b[buf].ts_context_disable
      end,
    })
    ```
    Then add diffview hooks to force treesitter-context to re-evaluate
    `on_attach` at the right times. This is necessary because
    treesitter-context only evaluates `on_attach` once per buffer (on
    `BufReadPost`), so working-tree files that were loaded before diffview
    opened would otherwise keep context enabled:
    ```lua
    require('diffview').setup({
      hooks = {
        diff_buf_win_enter = function(bufnr)
          pcall(vim.api.nvim_exec_autocmds, "BufReadPost", {
            buffer = bufnr,
            group = "treesitter_context_update",
          })
        end,
        view_closed = function()
          local ok, tsc = pcall(require, "treesitter-context")
          if ok and tsc.enabled() then
            tsc.enable()
          end
        end,
      },
    })
    ```

  - **[barbecue.nvim](https://github.com/utilyre/barbecue.nvim)** and other
    winbar plugins: Unlike treesitter-context, barbecue re-sets the winbar
    on every `CursorMoved` and `BufWinEnter`, so clearing it per-window is
    not sufficient. Instead, toggle barbecue's visibility using
    `view_enter`/`view_leave` hooks (these fire when switching to and from
    the diffview tab):
    ```lua
    require('diffview').setup({
      hooks = {
        view_enter = function()
          pcall(function() require("barbecue.ui").toggle(false) end)
        end,
        view_leave = function()
          pcall(function() require("barbecue.ui").toggle(true) end)
        end,
      },
    })
    ```

- **[vim-markdown](https://github.com/preservim/vim-markdown) (preservim/vim-markdown):**
  - vim-markdown creates folds for markdown sections. Older versions of
    diffview set `foldlevel=0` which collapsed these sections, hiding diff
    content. This has been fixed by setting `foldlevel=99` by default.
  - If you still experience issues, you can manually set foldlevel in hooks:
    ```lua
    require('diffview').setup({
      hooks = {
        diff_buf_win_enter = function(bufnr, winid, ctx)
          if ctx.layout_name == 'diff2_horizontal' then
            vim.wo[winid].foldlevel = 99
          end
        end,
      },
    })
    ```

<!-- vim: set tw=80 -->
