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
end)
