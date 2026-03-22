local actions = require("diffview.actions")
local helpers = require("diffview.tests.helpers")

local eq = helpers.eq

describe("diffview.actions goto_file API", function()
  it("exports all four goto_file functions", function()
    assert.is_function(actions.goto_file)
    assert.is_function(actions.goto_file_edit)
    assert.is_function(actions.goto_file_split)
    assert.is_function(actions.goto_file_tab)
  end)

  -- The goto_file functions require an active DiffView to operate.
  -- Without one, prepare_goto_file accesses a nil view, which is the
  -- expected pre-existing behaviour (they are only called from keymaps
  -- bound inside a DiffView tabpage). Verify they consistently error
  -- rather than silently misbehaving.
  it("goto_file errors without an active view (expected guard)", function()
    assert.has_error(function() actions.goto_file() end)
  end)

  it("goto_file_edit errors without an active view (expected guard)", function()
    assert.has_error(function() actions.goto_file_edit() end)
  end)

  it("goto_file_split errors without an active view (expected guard)", function()
    assert.has_error(function() actions.goto_file_split() end)
  end)

  it("goto_file_tab errors without an active view (expected guard)", function()
    assert.has_error(function() actions.goto_file_tab() end)
  end)
end)

describe("diffview.actions goto_file command routing", function()
  local lib = require("diffview.lib")
  local utils = require("diffview.utils")
  local DiffView_class = require("diffview.scene.views.diff.diff_view").DiffView

  local saved = {}
  local cmds_issued

  before_each(function()
    cmds_issued = {}
    saved.get_current_view = lib.get_current_view
    saved.get_prev_tabpage = lib.get_prev_non_view_tabpage
    saved.set_cursor = utils.set_cursor
    saved.nvim_set_current_tabpage = vim.api.nvim_set_current_tabpage
    saved.nvim_get_current_buf = vim.api.nvim_get_current_buf
    saved.nvim_buf_delete = vim.api.nvim_buf_delete
    saved.vim_cmd = vim.cmd
    saved.fnameescape = vim.fn.fnameescape

    local mock_file = {
      absolute_path = "/tmp/test.lua",
      layout = { restore_winopts = function() end, get_main_win = function() return { id = 1 } end },
      active = true,
    }
    local mock_view = {
      class = DiffView_class,
      instanceof = function(self, other) return self.class == other end,
      infer_cur_file = function() return mock_file end,
      cur_entry = nil,
      cur_layout = { get_main_win = function() return { id = 1 } end },
    }

    lib.get_current_view = function() return mock_view end
    lib.get_prev_non_view_tabpage = function() return nil end
    utils.set_cursor = function() end
    vim.api.nvim_set_current_tabpage = function() end
    vim.api.nvim_get_current_buf = function() return 999 end
    vim.api.nvim_buf_delete = function() end
    vim.fn.fnameescape = function(p) return p end
    vim.cmd = function(c) cmds_issued[#cmds_issued + 1] = c end
    utils.path.readable = function() return true end
  end)

  after_each(function()
    lib.get_current_view = saved.get_current_view
    lib.get_prev_non_view_tabpage = saved.get_prev_tabpage
    utils.set_cursor = saved.set_cursor
    vim.api.nvim_set_current_tabpage = saved.nvim_set_current_tabpage
    vim.api.nvim_get_current_buf = saved.nvim_get_current_buf
    vim.api.nvim_buf_delete = saved.nvim_buf_delete
    vim.cmd = saved.vim_cmd
    vim.fn.fnameescape = saved.fnameescape
  end)

  it("goto_file issues 'tabnew' then 'keepalt edit' when no previous tab", function()
    actions.goto_file()
    eq("tabnew", cmds_issued[1])
    assert.truthy(cmds_issued[2]:find("^keepalt edit"))
  end)

  it("goto_file_edit issues 'tabnew' then 'keepalt edit' when no previous tab", function()
    actions.goto_file_edit()
    eq("tabnew", cmds_issued[1])
    assert.truthy(cmds_issued[2]:find("^keepalt edit"))
  end)

  it("goto_file issues 'sp <file>' when a previous tab exists", function()
    lib.get_prev_non_view_tabpage = function() return 1 end
    actions.goto_file()
    eq(1, #cmds_issued)
    assert.truthy(cmds_issued[1]:find("^sp "))
  end)

  it("goto_file_edit issues 'edit <file>' when a previous tab exists", function()
    lib.get_prev_non_view_tabpage = function() return 1 end
    actions.goto_file_edit()
    eq(1, #cmds_issued)
    assert.truthy(cmds_issued[1]:find("^edit "))
  end)

  it("goto_file_split issues 'new' then 'keepalt edit'", function()
    actions.goto_file_split()
    eq("new", cmds_issued[1])
    assert.truthy(cmds_issued[2]:find("^keepalt edit"))
  end)

  it("goto_file_tab issues 'tabnew' then 'keepalt edit'", function()
    actions.goto_file_tab()
    eq("tabnew", cmds_issued[1])
    assert.truthy(cmds_issued[2]:find("^keepalt edit"))
  end)
end)
