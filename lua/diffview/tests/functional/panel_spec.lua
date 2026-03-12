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
