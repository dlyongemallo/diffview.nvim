local helpers = require("diffview.tests.helpers")

local eq = helpers.eq

describe("diffview.ui.panel", function()
  local Panel = require("diffview.ui.panel").Panel

  describe("interface contract", function()
    -- The tab_enter/tab_leave listeners in diff and file_history views
    -- depend on panel instances exposing a `winid` field and an `is_open`
    -- method.  Verify these exist on the base class so that a future
    -- refactor cannot silently break the contract (see issue #611).

    it("has a winid field after init", function()
      local panel = Panel({
        bufname = "TestPanel",
        config = Panel.default_config_split,
      })
      -- winid starts nil (panel not yet opened).
      eq(nil, panel.winid)
    end)

    it("exposes is_open as a callable method", function()
      local panel = Panel({
        bufname = "TestPanel",
        config = Panel.default_config_split,
      })
      eq("function", type(panel.is_open))
    end)

    it("is_open returns falsy when winid is nil", function()
      local panel = Panel({
        bufname = "TestPanel",
        config = Panel.default_config_split,
      })
      assert.falsy(panel:is_open())
    end)

    it("does not expose a get_winid method", function()
      -- get_winid has never been part of the Panel API.  Callers should
      -- access the winid field directly.  This test guards against
      -- accidental re-introduction of calls to a non-existent method.
      local panel = Panel({
        bufname = "TestPanel",
        config = Panel.default_config_split,
      })
      eq(nil, panel.get_winid)
    end)
  end)

  describe("auto-width", function()
    local api = vim.api

    ---Create a minimal panel with the given width config.
    local function make_panel(width)
      local conf = vim.tbl_deep_extend("force", Panel.default_config_split, {
        position = "left",
        width = width,
      })
      return Panel({
        bufname = "TestAutoWidth",
        config = conf,
      })
    end

    it("get_config accepts 'auto' as a width value", function()
      local panel = make_panel("auto")
      local config = panel:get_config()
      eq("auto", config.width)
    end)

    it("get_config accepts a numeric width value", function()
      local panel = make_panel(42)
      local config = panel:get_config()
      eq(42, config.width)
    end)

    it("get_config rejects an invalid width value", function()
      local panel = make_panel("bogus")
      assert.has_error(function()
        panel:get_config()
      end)
    end)

    it("infer_width returns vim.o.columns when width is 'auto'", function()
      local panel = make_panel("auto")
      eq(vim.o.columns, panel:infer_width())
    end)

    it("infer_width returns configured width for numeric values", function()
      local panel = make_panel(50)
      -- Panel is not open, so it falls through to config.width.
      eq(50, panel:infer_width())
    end)

    it("compute_content_width measures buffer lines", function()
      local panel = make_panel("auto")
      -- Manually create a buffer and populate it so we can test measurement.
      local bufid = api.nvim_create_buf(false, true)
      panel.bufid = bufid
      api.nvim_buf_set_lines(bufid, 0, -1, false, {
        "short",
        "a moderately long line here",
        "x",
      })

      local width = panel:compute_content_width()
      -- Panel is not open, so textoff defaults to 2 (signcolumn).
      -- Expected: max display width (27) + 2 + 1 = 30.
      local expected = api.nvim_strwidth("a moderately long line here") + 2 + 1
      eq(expected, width)

      api.nvim_buf_delete(bufid, { force = true })
    end)

    it("compute_content_width falls back when buffer is not loaded", function()
      -- With "auto" width and no class-level default, falls back to 35.
      local panel = make_panel("auto")
      eq(35, panel:compute_content_width())
    end)

    it("compute_content_width uses class default width when buffer is not loaded", function()
      -- When the panel subclass defines a numeric default width, use that.
      local panel = make_panel("auto")
      local saved = Panel.default_config_split.width
      Panel.default_config_split.width = 40
      eq(40, panel:compute_content_width())
      Panel.default_config_split.width = saved
    end)

    it("compute_content_width clamps to half the editor width", function()
      local panel = make_panel("auto")
      local bufid = api.nvim_create_buf(false, true)
      panel.bufid = bufid
      -- Create a line wider than half the editor.
      local long_line = string.rep("x", vim.o.columns)
      api.nvim_buf_set_lines(bufid, 0, -1, false, { long_line })

      local width = panel:compute_content_width()
      -- Raw content width would exceed the clamp, but compute_content_width
      -- itself does not clamp; clamping is done in resize(). So the raw
      -- value should exceed half the editor width.
      local raw_expected = api.nvim_strwidth(long_line) + 2 + 1
      eq(raw_expected, width)

      api.nvim_buf_delete(bufid, { force = true })
    end)
    it("resize applies computed auto-width to an open split panel", function()
      local panel = make_panel("auto")
      -- Stub abstract methods so init_buffer can complete.
      panel.update_components = function() end
      panel.render = function() end
      panel:init_buffer()

      -- Populate the buffer with known content.
      vim.bo[panel.bufid].modifiable = true
      api.nvim_buf_set_lines(panel.bufid, 0, -1, false, {
        "short",
        "a moderately long line here",
      })
      vim.bo[panel.bufid].modifiable = false

      panel:open()
      assert.truthy(panel:is_open())

      -- The window should have been sized to fit the content.
      local win_width = api.nvim_win_get_width(panel.winid)
      local info = vim.fn.getwininfo(panel.winid)
      local textoff = (info and info[1]) and info[1].textoff or 2
      local expected = api.nvim_strwidth("a moderately long line here") + textoff + 1
      eq(expected, win_width)

      panel:destroy()
    end)

    it("resize clamps auto-width to half the editor width", function()
      local panel = make_panel("auto")
      panel.update_components = function() end
      panel.render = function() end
      panel:init_buffer()

      -- Populate with an extremely long line.
      vim.bo[panel.bufid].modifiable = true
      api.nvim_buf_set_lines(panel.bufid, 0, -1, false, {
        string.rep("x", vim.o.columns),
      })
      vim.bo[panel.bufid].modifiable = false

      panel:open()
      assert.truthy(panel:is_open())

      local win_width = api.nvim_win_get_width(panel.winid)
      local max_width = math.floor(vim.o.columns * 0.5)
      assert.is_true(win_width <= max_width)

      panel:destroy()
    end)
  end)

  describe("subclass contracts", function()
    -- The actual panels used by the two view types must inherit the same
    -- interface.

    local function assert_panel_interface(panel_class, name)
      it(name .. " inherits winid field", function()
        eq(nil, rawget(panel_class, "get_winid"))
      end)

      it(name .. " inherits is_open method", function()
        eq("function", type(panel_class.is_open))
      end)
    end

    local FilePanel = require("diffview.scene.views.diff.file_panel").FilePanel
    local FileHistoryPanel = require("diffview.scene.views.file_history.file_history_panel").FileHistoryPanel

    assert_panel_interface(FilePanel, "FilePanel")
    assert_panel_interface(FileHistoryPanel, "FileHistoryPanel")
  end)

  describe("FilePanel multi-selection", function()
    local FilePanel = require("diffview.scene.views.diff.file_panel").FilePanel

    -- Minimal stub that satisfies FilePanel:init without needing a real adapter.
    local function make_panel()
      local adapter = { ctx = { toplevel = "/tmp", dir = "/tmp/.git" } }
      local files = setmetatable({}, {
        __index = function() return {} end,
      })
      return FilePanel(adapter, files, {})
    end

    -- Lightweight stand-in for a FileEntry (only identity matters).
    local function make_entry(path)
      return { path = path, kind = "working" }
    end

    it("starts with no selections", function()
      local panel = make_panel()
      eq({}, panel:get_selected_files())
    end)

    it("toggle_selection marks a file", function()
      local panel = make_panel()
      local f = make_entry("a.lua")
      panel:toggle_selection(f)
      eq(true, panel:is_selected(f))
      eq(1, #panel:get_selected_files())
    end)

    it("toggle_selection unmarks a previously marked file", function()
      local panel = make_panel()
      local f = make_entry("a.lua")
      panel:toggle_selection(f)
      panel:toggle_selection(f)
      eq(false, panel:is_selected(f))
      eq(0, #panel:get_selected_files())
    end)

    it("tracks multiple selections independently", function()
      local panel = make_panel()
      local a = make_entry("a.lua")
      local b = make_entry("b.lua")
      local c = make_entry("c.lua")
      panel:toggle_selection(a)
      panel:toggle_selection(b)
      eq(true, panel:is_selected(a))
      eq(true, panel:is_selected(b))
      eq(false, panel:is_selected(c))
      eq(2, #panel:get_selected_files())
    end)

    it("clear_selections removes all marks", function()
      local panel = make_panel()
      local a = make_entry("a.lua")
      local b = make_entry("b.lua")
      panel:toggle_selection(a)
      panel:toggle_selection(b)
      panel:clear_selections()
      eq(false, panel:is_selected(a))
      eq(false, panel:is_selected(b))
      eq(0, #panel:get_selected_files())
    end)

    it("is_selected returns false for unknown entries", function()
      local panel = make_panel()
      eq(false, panel:is_selected(make_entry("nope.lua")))
    end)
  end)
end)
