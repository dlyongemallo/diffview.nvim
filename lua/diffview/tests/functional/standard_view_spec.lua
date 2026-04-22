local helpers = require("diffview.tests.helpers")
local StandardView = require("diffview.scene.views.standard.standard_view").StandardView

local eq = helpers.eq

describe("diffview.standard_view panel cursor", function()
  local orig_win_is_valid, orig_win_get_cursor, orig_win_set_cursor

  before_each(function()
    orig_win_is_valid = vim.api.nvim_win_is_valid
    orig_win_get_cursor = vim.api.nvim_win_get_cursor
    orig_win_set_cursor = vim.api.nvim_win_set_cursor
  end)

  after_each(function()
    vim.api.nvim_win_is_valid = orig_win_is_valid
    vim.api.nvim_win_get_cursor = orig_win_get_cursor
    vim.api.nvim_win_set_cursor = orig_win_set_cursor
  end)

  ---Build a minimal mock view with a panel stub.
  local function make_view(panel_open, winid)
    local view = {
      panel = {
        winid = winid or 42,
        is_open = function()
          return panel_open
        end,
      },
      panel_cursor = nil,
    }
    setmetatable(view, { __index = StandardView })
    return view
  end

  it("save_panel_cursor stores the cursor when panel is open", function()
    local view = make_view(true, 42)
    vim.api.nvim_win_is_valid = function()
      return true
    end
    vim.api.nvim_win_get_cursor = function()
      return { 5, 3 }
    end

    view:save_panel_cursor()
    eq({ 5, 3 }, view.panel_cursor)
  end)

  it("save_panel_cursor is a no-op when panel is closed", function()
    local view = make_view(false)
    vim.api.nvim_win_is_valid = function()
      return true
    end
    vim.api.nvim_win_get_cursor = function()
      error("should not be called")
    end

    view:save_panel_cursor()
    eq(nil, view.panel_cursor)
  end)

  it("save_panel_cursor is a no-op when winid is invalid", function()
    local view = make_view(true, 42)
    vim.api.nvim_win_is_valid = function()
      return false
    end
    vim.api.nvim_win_get_cursor = function()
      error("should not be called")
    end

    view:save_panel_cursor()
    eq(nil, view.panel_cursor)
  end)

  it("restore_panel_cursor sets the cursor when panel_cursor exists", function()
    local set_args
    local view = make_view(true, 42)
    view.panel_cursor = { 10, 2 }
    vim.api.nvim_win_is_valid = function()
      return true
    end
    vim.api.nvim_win_set_cursor = function(w, c)
      set_args = { w, c }
    end

    view:restore_panel_cursor()
    eq({ 42, { 10, 2 } }, set_args)
  end)

  it("restore_panel_cursor is a no-op when panel_cursor is nil", function()
    local view = make_view(true, 42)
    vim.api.nvim_win_is_valid = function()
      return true
    end
    vim.api.nvim_win_set_cursor = function()
      error("should not be called")
    end

    view:restore_panel_cursor()
  end)

  it("round-trips: save then restore preserves cursor position", function()
    local restored
    local view = make_view(true, 42)
    vim.api.nvim_win_is_valid = function()
      return true
    end
    vim.api.nvim_win_get_cursor = function()
      return { 7, 4 }
    end
    vim.api.nvim_win_set_cursor = function(_, c)
      restored = c
    end

    view:save_panel_cursor()
    view:restore_panel_cursor()
    eq({ 7, 4 }, restored)
  end)
end)
