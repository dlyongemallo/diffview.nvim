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

    it("infer_width returns vim.o.columns when width is 'auto' and panel is closed", function()
      local panel = make_panel("auto")
      eq(vim.o.columns, panel:infer_width())
    end)

    it("infer_width returns window width when width is 'auto' and panel is open", function()
      local panel = make_panel("auto")
      panel.update_components = function() end
      panel.render = function() end
      panel:init_buffer()
      panel:open()
      assert.truthy(panel:is_open())

      local win_width = api.nvim_win_get_width(panel.winid)
      eq(win_width, panel:infer_width())

      panel:destroy()
    end)

    it("infer_width returns configured width for numeric values", function()
      local panel = make_panel(50)
      -- Panel is not open, so it falls through to config.width.
      eq(50, panel:infer_width())
    end)

    it("get_autosize_components returns nil by default", function()
      local panel = make_panel("auto")
      eq(nil, panel:get_autosize_components())
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

    it("compute_content_width skips lines outside autosize components", function()
      local panel = make_panel("auto")
      local bufid = api.nvim_create_buf(false, true)
      panel.bufid = bufid
      api.nvim_buf_set_lines(bufid, 0, -1, false, {
        "this is a very long header line that should be ignored",
        "short file entry",
        "another entry",
      })

      -- Mock a component covering only lines 1-2 (0-indexed: lstart=1, lend=3).
      local mock_comp = { lstart = 1, lend = 3 }
      panel.get_autosize_components = function() return { mock_comp } end

      local width = panel:compute_content_width()
      -- Should measure only "short file entry" (17 chars) + textoff(2) + 1 = 20.
      local expected = api.nvim_strwidth("short file entry") + 2 + 1
      eq(expected, width)

      api.nvim_buf_delete(bufid, { force = true })
    end)

    it("compute_content_width falls back to all lines when autosize components are empty", function()
      local panel = make_panel("auto")
      local bufid = api.nvim_create_buf(false, true)
      panel.bufid = bufid
      api.nvim_buf_set_lines(bufid, 0, -1, false, {
        "header line",
        "another line here!",
      })

      -- Mock zero-height components (lend <= lstart), as during loading.
      local mock_comp = { lstart = 0, lend = 0 }
      panel.get_autosize_components = function() return { mock_comp } end

      local width = panel:compute_content_width()
      -- Should fall back to measuring all lines.
      local expected = api.nvim_strwidth("another line here!") + 2 + 1
      eq(expected, width)

      api.nvim_buf_delete(bufid, { force = true })
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

    ---Create a mock FileDict that supports iteration over the given entries.
    ---@param entries table[]?
    ---@return table
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

    ---Minimal stub that satisfies FilePanel:init without needing a real adapter.
    ---@param entries table[]?
    local function make_panel(entries)
      local adapter = { ctx = { toplevel = "/tmp", dir = "/tmp/.git" } }
      return FilePanel(adapter, make_mock_files(entries), {})
    end

    -- Lightweight stand-in for a FileEntry (only identity matters).
    local function make_entry(path, kind)
      return { path = path, kind = kind or "working" }
    end

    it("starts with no selections", function()
      local panel = make_panel()
      eq({}, panel:get_selected_files())
    end)

    it("toggle_selection marks a file", function()
      local f = make_entry("a.lua")
      local panel = make_panel({ f })
      panel:toggle_selection(f)
      eq(true, panel:is_selected(f))
      eq(1, #panel:get_selected_files())
    end)

    it("toggle_selection unmarks a previously marked file", function()
      local f = make_entry("a.lua")
      local panel = make_panel({ f })
      panel:toggle_selection(f)
      panel:toggle_selection(f)
      eq(false, panel:is_selected(f))
      eq(0, #panel:get_selected_files())
    end)

    it("tracks multiple selections independently", function()
      local a = make_entry("a.lua")
      local b = make_entry("b.lua")
      local c = make_entry("c.lua")
      local panel = make_panel({ a, b, c })
      panel:toggle_selection(a)
      panel:toggle_selection(b)
      eq(true, panel:is_selected(a))
      eq(true, panel:is_selected(b))
      eq(false, panel:is_selected(c))
      eq(2, #panel:get_selected_files())
    end)

    it("clear_selections removes all marks", function()
      local a = make_entry("a.lua")
      local b = make_entry("b.lua")
      local panel = make_panel({ a, b })
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

    it("selections survive file entry replacement", function()
      -- Simulate what happens on tab switch: a selected file entry is
      -- replaced by a new object with the same path and kind.
      local old = make_entry("src/foo.lua")
      local panel = make_panel({ old })
      panel:toggle_selection(old)
      eq(true, panel:is_selected(old))

      -- Replace with a new object (same path/kind, different identity).
      local new = make_entry("src/foo.lua")
      assert.is_not.equal(old, new)
      panel.files = make_mock_files({ new })

      -- Selection should carry over to the replacement entry.
      eq(true, panel:is_selected(new))
      local selected = panel:get_selected_files()
      eq(1, #selected)
      eq(new, selected[1])
    end)

    it("prune_selections removes stale entries", function()
      local a = make_entry("a.lua")
      local b = make_entry("b.lua")
      local panel = make_panel({ a, b })
      panel:toggle_selection(a)
      panel:toggle_selection(b)

      -- Remove 'b' from the file list (simulating a file disappearing).
      panel.files = make_mock_files({ a })
      panel:prune_selections()

      eq(true, panel:is_selected(a))
      -- 'b' is no longer in the file list, so it should be pruned.
      eq(false, panel:is_selected(b))
      eq(1, #panel:get_selected_files())
    end)

    it("select_file and deselect_file work", function()
      local f = make_entry("x.lua")
      local panel = make_panel({ f })
      panel:select_file(f)
      eq(true, panel:is_selected(f))
      panel:deselect_file(f)
      eq(false, panel:is_selected(f))
    end)

    it("distinguishes files by kind", function()
      local working = make_entry("f.lua", "working")
      local staged = make_entry("f.lua", "staged")
      local panel = make_panel({ working, staged })
      panel:toggle_selection(working)
      eq(true, panel:is_selected(working))
      eq(false, panel:is_selected(staged))
    end)
  end)

  describe("FilePanel set_dir_collapsed", function()
    local FilePanel = require("diffview.scene.views.diff.file_panel").FilePanel
    local Node = require("diffview.ui.models.file_tree.node").Node

    local function make_panel()
      local adapter = { ctx = { toplevel = "/tmp", dir = "/tmp/.git" } }
      local files = {}
      function files:iter() return function() end end
      function files:len() return 0 end
      return FilePanel(adapter, files, {})
    end

    it("propagates collapsed state to tree nodes in a flattened chain", function()
      -- Build a simple tree chain: A -> B -> leaf
      local a_data = { name = "a", path = "a", kind = "working", collapsed = false }
      local b_data = { name = "b", path = "a/b", kind = "working", collapsed = false }

      local a_node = Node("a", a_data)
      local b_node = Node("b", b_data)
      local leaf_node = Node("file.lua", { path = "a/b/file.lua" })
      a_node:add_child(b_node)
      b_node:add_child(leaf_node)

      -- Simulate a flattened DirData created by create_comp_schema.
      local flattened = {
        name = "a/b",
        path = "a/b",
        kind = "working",
        collapsed = false,
        _node = a_node,
      }

      local panel = make_panel()
      panel:set_dir_collapsed(flattened, true)

      eq(true, flattened.collapsed)
      eq(true, a_data.collapsed)
      eq(true, b_data.collapsed)
    end)

    it("does not walk past the end of a flatten chain", function()
      -- Tree: a -> b -> [c (dir), x.lua]
      -- Flatten combines a/b (single-child chain). c is a separate subdir.
      local a_data = { name = "a", path = "a", kind = "working", collapsed = false }
      local b_data = { name = "b", path = "a/b", kind = "working", collapsed = false }
      local c_data = { name = "c", path = "a/b/c", kind = "working", collapsed = false }

      local a_node = Node("a", a_data)
      local b_node = Node("b", b_data)
      local c_node = Node("c", c_data)
      local leaf1 = Node("x.lua", { path = "a/b/x.lua" })
      local leaf2 = Node("y.lua", { path = "a/b/c/y.lua" })
      a_node:add_child(b_node)
      b_node:add_child(c_node)
      b_node:add_child(leaf1)
      c_node:add_child(leaf2)

      local flattened = {
        name = "a/b",
        path = "a/b",
        kind = "working",
        collapsed = false,
        _node = a_node,
      }

      local panel = make_panel()
      panel:set_dir_collapsed(flattened, true)

      eq(true, flattened.collapsed)
      -- a and b are part of the flatten chain (a has one child: b).
      eq(true, a_data.collapsed)
      -- b has multiple children, so the walk stops after b.
      eq(true, b_data.collapsed)
      -- c is a separate subdir, not part of the flatten chain.
      eq(false, c_data.collapsed)
    end)

    it("dir_selection_state reflects none/some/all", function()
      local a_data = { name = "a", path = "a", kind = "working", collapsed = false }
      local a_node = Node("a", a_data)
      local f1 = { path = "a/x.lua", kind = "working" }
      local f2 = { path = "a/y.lua", kind = "working" }
      a_node:add_child(Node("x.lua", f1))
      a_node:add_child(Node("y.lua", f2))
      a_data._node = a_node

      local panel = make_panel()
      eq("none", panel:dir_selection_state(a_data))

      panel:select_file(f1)
      eq("some", panel:dir_selection_state(a_data))

      panel:select_file(f2)
      eq("all", panel:dir_selection_state(a_data))

      panel:deselect_file(f1)
      eq("some", panel:dir_selection_state(a_data))
    end)

    it("dir_selection_state returns none without _node", function()
      local panel = make_panel()
      eq("none", panel:dir_selection_state({ collapsed = false }))
    end)
  end)

  describe("FileTree collapsed state with flatten_dirs", function()
    local FileTree = require("diffview.ui.models.file_tree.file_tree").FileTree

    ---Create a minimal FileEntry stub.
    local function make_entry(path, kind)
      return { path = path, kind = kind or "working", status = "M", basename = path }
    end

    it("get_collapsed_state reads from tree nodes (not flattened DirData)", function()
      -- Build a tree with a flattenable chain: src/components/foo.lua
      local tree = FileTree({ make_entry("src/components/foo.lua") })

      -- Manually collapse the tree nodes (simulating set_dir_collapsed propagation).
      local function collapse_nodes(node)
        if node:has_children() and node.data and node.data.collapsed ~= nil then
          node.data.collapsed = true
        end
        for _, child in ipairs(node.children) do
          collapse_nodes(child)
        end
      end
      for _, child in ipairs(tree.root.children) do
        collapse_nodes(child)
      end

      local state = tree:get_collapsed_state()

      -- Both intermediate nodes should report collapsed = true.
      eq(true, state["src"])
      eq(true, state["src/components"])
    end)

    it("set_collapsed_state restores to tree nodes", function()
      local tree = FileTree({ make_entry("src/components/foo.lua") })

      tree:set_collapsed_state({ ["src"] = true, ["src/components"] = true })

      local state = tree:get_collapsed_state()
      eq(true, state["src"])
      eq(true, state["src/components"])
    end)

    it("create_comp_schema sets _node to outermost node in flattened chain", function()
      local tree = FileTree({ make_entry("src/components/foo.lua") })
      local schema = tree:create_comp_schema({ flatten_dirs = true })

      -- With flatten_dirs, "src" and "components" should be combined into
      -- a single directory component.
      eq("directory", schema[1].name)
      local dir_data = schema[1].context
      assert.truthy(dir_data._node)

      -- _node should point to the outermost node ("src"), not an inner one.
      eq("src", dir_data._node.name)
    end)
  end)

  describe("FilePanel update_components", function()
    local FilePanel = require("diffview.scene.views.diff.file_panel").FilePanel

    ---Build a mock FileDict with named sub-lists.
    local function make_files(conflicting, working, staged)
      local files = { conflicting = conflicting or {}, working = working or {}, staged = staged or {} }
      function files:iter()
        local all = {}
        for _, f in ipairs(self.conflicting) do all[#all + 1] = f end
        for _, f in ipairs(self.working) do all[#all + 1] = f end
        for _, f in ipairs(self.staged) do all[#all + 1] = f end
        local i = 0
        return function()
          i = i + 1
          if i <= #all then return i, all[i] end
        end
      end
      function files:len() return #self.conflicting + #self.working + #self.staged end
      return files
    end

    it("list mode builds file components from list entries", function()
      local renderer = require("diffview.renderer")
      local orig_create_cursor_constraint = renderer.create_cursor_constraint

      local f1 = { path = "a.lua" }
      local f2 = { path = "b.lua" }
      local adapter = { ctx = { toplevel = "/tmp", dir = "/tmp/.git" } }
      local panel = FilePanel(adapter, make_files({}, { f1, f2 }, {}), {})
      panel.listing_style = "list"

      -- Capture the schema passed to render_data:create_component.
      local comp_schema
      panel.render_data = {
        create_component = function(_, schema)
          comp_schema = schema
          return {
            conflicting = { files = { comp = {} } },
            working = { files = { comp = {} } },
            staged = { files = { comp = {} } },
          }
        end,
      }
      renderer.create_cursor_constraint = function() return function() end end

      local ok, err = pcall(function()
        panel:update_components()

        -- The working section is the 3rd top-level entry; its files sub-entry
        -- should contain the two file components built by build_file_list.
        local working_section = comp_schema[3] -- { name="working", title, files, margin }
        eq("working", working_section.name)
        local working_files = working_section[2] -- the files component
        eq("files", working_files.name)
        eq(f1, working_files[1].context)
        eq(f2, working_files[2].context)
      end)

      renderer.create_cursor_constraint = orig_create_cursor_constraint
      if not ok then error(err) end
    end)

    it("tree mode calls update_statuses and create_comp_schema on each tree", function()
      local renderer = require("diffview.renderer")
      local orig_create_cursor_constraint = renderer.create_cursor_constraint

      local statuses_updated = {}
      local schemas_created = {}

      local function mock_tree(name)
        return {
          update_statuses = function() statuses_updated[#statuses_updated + 1] = name end,
          create_comp_schema = function(_, opts)
            schemas_created[#schemas_created + 1] = { name = name, opts = opts }
            return { { name = "directory", context = {} } }
          end,
        }
      end

      local files = {
        conflicting = {}, working = {}, staged = {},
        conflicting_tree = mock_tree("conflicting"),
        working_tree = mock_tree("working"),
        staged_tree = mock_tree("staged"),
      }
      function files:iter()
        local i = 0
        return function() i = i + 1 end
      end
      function files:len() return 0 end

      local adapter = { ctx = { toplevel = "/tmp", dir = "/tmp/.git" } }
      local panel = FilePanel(adapter, files, {})
      panel.listing_style = "tree"
      panel.tree_options = { flatten_dirs = true }
      panel.render_data = {
        create_component = function()
          return {
            conflicting = { files = { comp = {} } },
            working = { files = { comp = {} } },
            staged = { files = { comp = {} } },
          }
        end,
      }
      renderer.create_cursor_constraint = function() return function() end end

      local ok, err = pcall(function()
        panel:update_components()

        eq(3, #statuses_updated)
        eq("conflicting", statuses_updated[1])
        eq("working", statuses_updated[2])
        eq("staged", statuses_updated[3])

        eq(3, #schemas_created)
        for _, entry in ipairs(schemas_created) do
          eq(true, entry.opts.flatten_dirs)
        end
      end)

      renderer.create_cursor_constraint = orig_create_cursor_constraint
      if not ok then error(err) end
    end)
  end)
end)
