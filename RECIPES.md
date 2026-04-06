# Recipes

Here are some practical snippets and keymaps for common diffview workflows.
Each recipe shows only the relevant options. Combine them as needed.

## Recommended Keymaps

These keymaps are commonly used patterns for working with diffview:

```lua
-- Toggle diffview open/close
vim.keymap.set('n', '<leader>dv', '<cmd>DiffviewToggle<cr>', { desc = 'Toggle Diffview' })

-- Diff working directory
vim.keymap.set('n', '<leader>do', '<cmd>DiffviewOpen<cr>', { desc = 'Diffview open' })
vim.keymap.set('n', '<leader>dc', '<cmd>DiffviewClose<cr>', { desc = 'Diffview close' })

-- File history
vim.keymap.set('n', '<leader>dh', '<cmd>DiffviewFileHistory %<cr>', { desc = 'File history (current file)' })
vim.keymap.set('n', '<leader>dH', '<cmd>DiffviewFileHistory<cr>', { desc = 'File history (repo)' })

-- Visual mode: history for selection
vim.keymap.set('v', '<leader>dh', "<Esc><cmd>'<,'>DiffviewFileHistory --follow<CR>", { desc = 'Range history' })

-- Single line history
vim.keymap.set('n', '<leader>dl', '<cmd>.DiffviewFileHistory --follow<CR>', { desc = 'Line history' })

-- Diff against main/master branch (useful before merging)
vim.keymap.set('n', '<leader>dm', function()
  -- Try main first, fall back to master
  local result = vim.fn.systemlist({ 'git', 'rev-parse', '--verify', 'main' })
  local ok = vim.v.shell_error == 0 and result[1] ~= nil and result[1] ~= ''
  local branch = ok and 'main' or 'master'
  vim.cmd('DiffviewOpen ' .. branch)
end, { desc = 'Diff against main/master' })
```

## Restoring Files

If the right side of the diff is showing the local state of a file, you can
restore the file to the state from the left side of the diff (key binding `X`
from the file panel by default). The current state of the file is stored in the
git object database, and a command is echoed that shows how to undo the change.

## Hooks

The `hooks` table allows you to define callbacks for various events emitted
from Diffview. The available hooks are documented in detail in
`:h diffview-config-hooks`. The hook events are also available as User
autocommands. See `:h diffview-user-autocmds` for more details.

Examples:

```lua
hooks = {
  diff_buf_read = function(bufnr)
    -- Change local options in diff buffers
    vim.opt_local.wrap = false
    vim.opt_local.list = false
    vim.opt_local.colorcolumn = { 80 }
  end,
  view_opened = function(view)
    print(
      ("A new %s was opened on tab page %d!")
      :format(view.class:name(), vim.api.nvim_tabpage_get_number(view.tabpage))
    )
  end,
}
```

## Configuration Recipes

<details>
<summary><b>Minimal / Clean</b></summary>

Strip away visual noise and auto-clean resources on close.

```lua
require("diffview").setup({
  show_help_hints = false,
  hide_merge_artifacts = true,
  clean_up_buffers = true,
  auto_close_on_empty = true,
})
```

</details>

<details>
<summary><b>PR Review</b></summary>

Optimised for reviewing pull requests against a base branch. `--imply-local`
makes the right-side buffer editable so you can fix things as you review.

```lua
require("diffview").setup({
  default_args = {
    DiffviewOpen = { "--imply-local" },
  },
  file_panel = {
    show_branch_name = true,
    always_show_sections = true,
  },
})
```

Open with a symmetric range to see only the changes introduced by the branch:

```
:DiffviewOpen origin/main...HEAD
```

</details>

<details>
<summary><b>Better Diffs</b></summary>

Enable enhanced highlighting and use the histogram diff algorithm for more
readable diffs. Pair with
[diffchar.vim](https://github.com/rickhowe/diffchar.vim) for character-level
precision (see [Companion Plugins](README.md#companion-plugins) for setup
details).

```lua
require("diffview").setup({
  enhanced_diff_hl = true,
  diffopt = { algorithm = "histogram" },
})
```

</details>

<details>
<summary><b>File History Power User</b></summary>

Show both numeric and bar stats, use relative dates, and reorder commit info
for a denser history view.

```lua
require("diffview").setup({
  file_history_panel = {
    stat_style = "both",
    date_format = "relative",
    commit_format = { "hash", "subject", "author", "date", "ref", "reflog", "status", "files", "stats" },
  },
  view = {
    file_history = {
      layout = "diff2_vertical",
    },
  },
})
```

</details>

<details>
<summary><b>Merge Conflict Resolution</b></summary>

Use a 4-way diff layout showing BASE, OURS, THEIRS, and the merge result.
Winbar labels help identify each pane. Diagnostics are disabled to reduce
noise during conflict resolution.

```lua
require("diffview").setup({
  view = {
    merge_tool = {
      layout = "diff4_mixed",
      disable_diagnostics = true,
      winbar_info = true,
    },
    cycle_layouts = {
      merge_tool = { "diff4_mixed", "diff3_mixed", "diff3_horizontal", "diff1_plain" },
    },
  },
})
```

</details>

<details>
<summary><b>Telescope Integration</b></summary>

Use [Telescope](https://github.com/nvim-telescope/telescope.nvim) to select
branches or commits for diffview:

```lua
-- Diff against a branch selected via Telescope
vim.keymap.set('n', '<leader>db', function()
  require('telescope.builtin').git_branches({
    attach_mappings = function(_, map)
      map('i', '<CR>', function(prompt_bufnr)
        local selection = require('telescope.actions.state').get_selected_entry()
        require('telescope.actions').close(prompt_bufnr)
        vim.cmd('DiffviewOpen ' .. selection.value)
      end)
      return true
    end,
  })
end, { desc = 'Diffview branch' })

-- File history for a commit selected via Telescope
vim.keymap.set('n', '<leader>dC', function()
  require('telescope.builtin').git_commits({
    attach_mappings = function(_, map)
      map('i', '<CR>', function(prompt_bufnr)
        local selection = require('telescope.actions.state').get_selected_entry()
        require('telescope.actions').close(prompt_bufnr)
        vim.cmd('DiffviewOpen ' .. selection.value .. '^!')
      end)
      return true
    end,
  })
end, { desc = 'Diffview commit' })
```

</details>

<!-- vim: set tw=80 -->
