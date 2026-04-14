local api = vim.api

describe("diffview.scene.view", function()
  local view_mod = require("diffview.scene.view")
  local View = view_mod.View
  local EventEmitter = require("diffview.events").EventEmitter
  local config = require("diffview.config")

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

  -- Regression: saved diffopt must be per-view so multiple views don't
  -- clobber each other's saved state.
  describe("per-view diffopt", function()
    local orig_config
    local orig_diffopt

    before_each(function()
      orig_config = vim.deepcopy(config.get_config())
      orig_diffopt = vim.deepcopy(vim.opt.diffopt:get())
      config.setup({ diffopt = { algorithm = "patience" } })
    end)

    after_each(function()
      config.setup(orig_config)
      vim.opt.diffopt = vim.deepcopy(orig_diffopt)
    end)

    it("stores saved diffopt independently per view", function()
      local view_a = View({ default_layout = {} })
      local view_b = View({ default_layout = {} })

      local baseline = vim.opt.diffopt:get()

      -- Simulate view A entering its tab.
      view_mod._test.apply_diffopt(view_a)
      assert.is_not_nil(view_a._saved_diffopt)
      assert.is_nil(view_b._saved_diffopt)

      -- Simulate switching: A leaves, B enters.
      view_mod._test.restore_diffopt(view_a)
      view_mod._test.apply_diffopt(view_b)
      assert.is_nil(view_a._saved_diffopt)
      assert.is_not_nil(view_b._saved_diffopt)

      -- Closing view A must not wipe view B's saved state.
      view_mod._test.restore_diffopt(view_a) -- no-op: A has no saved state
      assert.is_not_nil(view_b._saved_diffopt)

      -- View B can still restore cleanly.
      view_mod._test.restore_diffopt(view_b)
      assert.are.same(baseline, vim.opt.diffopt:get())
    end)
  end)

  describe("diffopt linematch override", function()
    local orig_config
    local orig_diffopt

    before_each(function()
      orig_config = vim.deepcopy(config.get_config())
      orig_diffopt = vim.deepcopy(vim.opt.diffopt:get())
    end)

    after_each(function()
      config.setup(orig_config)
      vim.opt.diffopt = vim.deepcopy(orig_diffopt)
    end)

    local function find_linematch(opts)
      for _, v in ipairs(opts) do
        local n = v:match("^linematch:(%d+)$")
        if n then return tonumber(n) end
      end
      return nil
    end

    it("applies linematch:N when configured", function()
      vim.opt.diffopt:remove(
        vim.tbl_filter(function(v) return v:match("^linematch:") end, vim.opt.diffopt:get())
      )
      config.setup({ diffopt = { linematch = 60 } })

      local view = View({ default_layout = {} })
      view_mod._test.apply_diffopt(view)

      assert.are.equal(60, find_linematch(vim.opt.diffopt:get()))

      view_mod._test.restore_diffopt(view)
      assert.is_nil(find_linematch(vim.opt.diffopt:get()))
    end)

    it("replaces an existing linematch:N entry", function()
      vim.opt.diffopt:remove(
        vim.tbl_filter(function(v) return v:match("^linematch:") end, vim.opt.diffopt:get())
      )
      vim.opt.diffopt:append({ "linematch:30" })
      config.setup({ diffopt = { linematch = 60 } })

      local view = View({ default_layout = {} })
      view_mod._test.apply_diffopt(view)

      -- Only the configured value should remain (no duplicate).
      local matches = vim.tbl_filter(
        function(v) return v:match("^linematch:") end,
        vim.opt.diffopt:get()
      )
      assert.are.equal(1, #matches)
      assert.are.equal(60, find_linematch(vim.opt.diffopt:get()))

      -- Restoring brings back the pre-view value.
      view_mod._test.restore_diffopt(view)
      assert.are.equal(30, find_linematch(vim.opt.diffopt:get()))
    end)

    it("leaves linematch untouched when not configured", function()
      vim.opt.diffopt:remove(
        vim.tbl_filter(function(v) return v:match("^linematch:") end, vim.opt.diffopt:get())
      )
      vim.opt.diffopt:append({ "linematch:45" })
      config.setup({ diffopt = { algorithm = "patience" } })

      local view = View({ default_layout = {} })
      view_mod._test.apply_diffopt(view)

      assert.are.equal(45, find_linematch(vim.opt.diffopt:get()))

      view_mod._test.restore_diffopt(view)
      assert.are.equal(45, find_linematch(vim.opt.diffopt:get()))
    end)
  end)
end)
