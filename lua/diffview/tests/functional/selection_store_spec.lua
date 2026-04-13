local helpers = require("diffview.tests.helpers")

local eq = helpers.eq

describe("diffview.selection_store", function()
  local SelectionStore = require("diffview.selection_store")
  local tmpdir

  before_each(function()
    tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, "p")
  end)

  after_each(function()
    vim.fn.delete(tmpdir, "rf")
  end)

  describe("scope_key", function()
    it("combines toplevel and rev_arg", function()
      eq("/repo:HEAD~1", SelectionStore.scope_key("/repo", "HEAD~1"))
    end)

    it("handles nil rev_arg", function()
      eq("/repo:", SelectionStore.scope_key("/repo", nil))
    end)
  end)

  describe("save and load", function()
    local saved_get_path

    before_each(function()
      saved_get_path = SelectionStore.get_path
      SelectionStore.get_path = function()
        return tmpdir .. "/test_selections.json"
      end
    end)

    after_each(function()
      SelectionStore.get_path = saved_get_path
    end)

    it("returns empty list for missing file", function()
      local result = SelectionStore.load("nonexistent:scope")
      eq({}, result)
    end)

    it("round-trips selections", function()
      local scope = "/repo:HEAD"
      local selections = { "working:a.lua", "staged:b.lua" }
      SelectionStore.save(scope, selections)

      local loaded = SelectionStore.load(scope)
      table.sort(loaded)
      table.sort(selections)
      eq(selections, loaded)
    end)

    it("isolates scopes", function()
      SelectionStore.save("/repo1:", { "working:a.lua" })
      SelectionStore.save("/repo2:", { "working:b.lua" })

      local r1 = SelectionStore.load("/repo1:")
      local r2 = SelectionStore.load("/repo2:")
      eq({ "working:a.lua" }, r1)
      eq({ "working:b.lua" }, r2)
    end)

    it("removes scope when saving empty selections", function()
      local scope = "/repo:"
      SelectionStore.save(scope, { "working:a.lua" })
      eq(1, #SelectionStore.load(scope))

      SelectionStore.save(scope, {})
      eq({}, SelectionStore.load(scope))
    end)

    it("handles corrupt file gracefully", function()
      local path = tmpdir .. "/test_selections.json"
      vim.fn.writefile({ "not valid json{{{" }, path)
      local result = SelectionStore.load("any:scope")
      eq({}, result)
    end)

    -- Regression: fs_rename failure must be caught and logged rather than
    -- silently leaving a .tmp file behind.
    it("logs warning when rename fails", function()
      local target = tmpdir .. "/store.json"
      SelectionStore.get_path = function() return target end

      local warns = {}
      local orig_warn = DiffviewGlobal.logger.warn
      local orig_rename = vim.uv.fs_rename
      DiffviewGlobal.logger.warn = function(_, msg) table.insert(warns, msg) end
      vim.uv.fs_rename = function()
        return nil, "mock fs_rename failure"
      end

      SelectionStore.save("scope:", { "a.lua" })

      DiffviewGlobal.logger.warn = orig_warn
      vim.uv.fs_rename = orig_rename

      -- The rename failure should be caught and logged with the rename error.
      assert.is_true(#warns == 1)
      assert.is_truthy(warns[1]:find("mock fs_rename failure", 1, true))
      -- The .tmp file should be cleaned up.
      eq(0, vim.fn.filereadable(target .. ".tmp"))
    end)
  end)

  describe("on_selection_changed callback", function()
    local FilePanel = require("diffview.scene.views.diff.file_panel").FilePanel

    local function make_mock_files(entries)
      local all = entries or {}
      local files = {}
      function files:iter()
        local i = 0
        return function()
          i = i + 1
          if i <= #all then
            return i, all[i]
          end
        end
      end
      function files:len()
        return #all
      end
      return files
    end

    local function make_panel(entries)
      local adapter = { ctx = { toplevel = "/tmp", dir = "/tmp/.git" } }
      return FilePanel(adapter, make_mock_files(entries), {})
    end

    it("fires on toggle_selection", function()
      local f = { path = "a.lua", kind = "working" }
      local panel = make_panel({ f })
      local called = 0
      panel.on_selection_changed = function() called = called + 1 end

      panel:toggle_selection(f)
      eq(1, called)
      panel:toggle_selection(f)
      eq(2, called)
    end)

    it("fires on select_file and deselect_file", function()
      local f = { path = "a.lua", kind = "working" }
      local panel = make_panel({ f })
      local called = 0
      panel.on_selection_changed = function() called = called + 1 end

      panel:select_file(f)
      eq(1, called)
      panel:deselect_file(f)
      eq(2, called)
    end)

    it("fires on clear_selections only when non-empty", function()
      local f = { path = "a.lua", kind = "working" }
      local panel = make_panel({ f })
      local called = 0
      panel.on_selection_changed = function() called = called + 1 end

      -- Clear when empty: should not fire.
      panel:clear_selections()
      eq(0, called)

      panel:select_file(f)
      called = 0
      panel:clear_selections()
      eq(1, called)
    end)

    it("batch_selection fires once after multiple mutations", function()
      local a = { path = "a.lua", kind = "working" }
      local b = { path = "b.lua", kind = "working" }
      local panel = make_panel({ a, b })
      local called = 0
      panel.on_selection_changed = function() called = called + 1 end

      panel:batch_selection(function()
        panel:select_file(a)
        panel:select_file(b)
      end)
      eq(1, called)
    end)

    it("batch_selection does not fire when nothing changed", function()
      local a = { path = "a.lua", kind = "working" }
      local panel = make_panel({ a })
      local called = 0
      panel.on_selection_changed = function() called = called + 1 end

      panel:batch_selection(function()
        -- No mutations inside the batch.
      end)
      eq(0, called)
    end)

    it("batch_selection restores state after error", function()
      local a = { path = "a.lua", kind = "working" }
      local panel = make_panel({ a })
      local called = 0
      panel.on_selection_changed = function() called = called + 1 end

      -- Error inside batch: flags must be restored so future notifications work.
      pcall(function()
        panel:batch_selection(function()
          panel:select_file(a)
          error("boom")
        end)
      end)

      -- The batch should still have notified for the mutation before the error.
      eq(1, called)

      -- Subsequent non-batched mutations must not be suppressed.
      called = 0
      panel:deselect_file(a)
      eq(1, called)
    end)

    it("fires on prune_selections only when entries are removed", function()
      local a = { path = "a.lua", kind = "working" }
      local b = { path = "b.lua", kind = "working" }
      local panel = make_panel({ a, b })
      local called = 0
      panel.on_selection_changed = function() called = called + 1 end

      panel:select_file(a)
      panel:select_file(b)
      called = 0

      -- Prune with all files present: no change.
      panel:prune_selections()
      eq(0, called)

      -- Remove b from file list and prune.
      panel.files = make_mock_files({ a })
      panel:prune_selections()
      eq(1, called)
    end)
  end)
end)
