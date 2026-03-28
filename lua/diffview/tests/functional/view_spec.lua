local api = vim.api

describe("diffview.scene.view", function()
  local View = require("diffview.scene.view").View
  local EventEmitter = require("diffview.events").EventEmitter

  local orig_emitter

  before_each(function()
    orig_emitter = DiffviewGlobal.emitter
    DiffviewGlobal.emitter = EventEmitter()
  end)

  after_each(function()
    DiffviewGlobal.emitter = orig_emitter
  end)

  describe("View:close()", function()
    -- Regression: closing a view whose tabpage contains a modified buffer
    -- must not error. `tabclose` raises E445 in this case, so the code
    -- falls back to `tabclose!`.
    it("closes a tabpage that contains a modified buffer", function()
      local view = View({ default_layout = {} })

      vim.cmd("tabnew")
      view.tabpage = api.nvim_get_current_tabpage()

      -- Create a scratch buffer only in this tabpage, mark it as modified,
      -- and display it in a non-current window. This is the exact E445
      -- trigger: modified buffer, only in this tab, in an "other" window.
      vim.cmd("split")
      local buf = api.nvim_create_buf(true, true)
      api.nvim_buf_set_lines(buf, 0, -1, false, { "unsaved change" })
      vim.bo[buf].modified = true
      api.nvim_win_set_buf(0, buf)
      vim.cmd("wincmd j")

      view:close()

      assert.is_false(api.nvim_tabpage_is_valid(view.tabpage))
      -- The modified buffer should still be in the buffer list (no data loss).
      assert.is_true(api.nvim_buf_is_valid(buf))

      api.nvim_buf_delete(buf, { force = true })
    end)

    it("closes a tabpage with only unmodified buffers", function()
      local view = View({ default_layout = {} })

      vim.cmd("tabnew")
      view.tabpage = api.nvim_get_current_tabpage()

      view:close()

      assert.is_false(api.nvim_tabpage_is_valid(view.tabpage))
    end)

    -- When the view's tabpage is the only one, close should create a new
    -- tabpage first (to avoid closing Neovim) and then close the original.
    it("creates a replacement tabpage when closing the last one", function()
      local view = View({ default_layout = {} })

      while #api.nvim_list_tabpages() > 1 do
        vim.cmd("tabclose")
      end

      view.tabpage = api.nvim_get_current_tabpage()

      view:close()

      assert.is_true(#api.nvim_list_tabpages() >= 1)
      assert.is_false(api.nvim_tabpage_is_valid(view.tabpage))
    end)
  end)
end)
