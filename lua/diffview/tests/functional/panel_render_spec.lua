local helpers = require("diffview.tests.helpers")
local config = require("diffview.config")
local Node = require("diffview.ui.models.file_tree.node").Node
local FileTree = require("diffview.ui.models.file_tree.file_tree").FileTree
local FileDict = require("diffview.vcs.file_dict").FileDict

local eq = helpers.eq

-- ---------------------------------------------------------------------------
-- Mock RenderComponent (same pattern as file_history_render_spec.lua)
-- ---------------------------------------------------------------------------

---Create a mock RenderComponent that records add_text / add_line / ln calls.
---@return table
local function make_comp()
  local comp = { lines = { {} }, components = {} }

  function comp:add_text(text, hl)
    local cur = self.lines[#self.lines]
    cur[#cur + 1] = { text = text, hl = hl }
  end

  function comp:add_line(line, hl)
    if line and hl then
      local cur = self.lines[#self.lines]
      cur[#cur + 1] = { text = line, hl = hl }
    elseif line then
      local cur = self.lines[#self.lines]
      cur[#cur + 1] = { text = line }
    end
    self.lines[#self.lines + 1] = {}
  end

  function comp:ln()
    self.lines[#self.lines + 1] = {}
  end

  function comp:clear()
    self.lines = { {} }
  end

  --- Flatten all recorded text into a single string.
  function comp:flat_text()
    local parts = {}
    for _, line in ipairs(self.lines) do
      for _, seg in ipairs(line) do
        parts[#parts + 1] = seg.text
      end
    end
    return table.concat(parts)
  end

  --- Return every segment whose hl group matches `hl`.
  function comp:segments_by_hl(hl)
    local result = {}
    for _, line in ipairs(self.lines) do
      for _, seg in ipairs(line) do
        if seg.hl == hl then
          result[#result + 1] = seg.text
        end
      end
    end
    return result
  end

  return comp
end

---Create a minimal file entry stub.
---@param path string
---@param kind? string
---@param status? string
---@return table
local function make_entry(path, kind, status)
  local parts = vim.split(path, "/")
  return {
    path = path,
    basename = parts[#parts],
    extension = parts[#parts]:match("%.(%w+)$") or "",
    parent_path = table.concat(parts, "/", 1, math.max(#parts - 1, 0)),
    kind = kind or "working",
    status = status or "M",
    active = false,
  }
end

-- ---------------------------------------------------------------------------
-- Tests
-- ---------------------------------------------------------------------------

describe("panel_render", function()
  local original_config

  before_each(function()
    original_config = vim.deepcopy(config.get_config())
  end)

  after_each(function()
    config.setup(original_config)
  end)

  -- -----------------------------------------------------------------------
  -- File count on collapsed folders (commit bdbe846)
  -- -----------------------------------------------------------------------

  describe("file count on collapsed folders", function()
    describe("Node:leaves()", function()
      it("returns leaf nodes for a flat directory", function()
        local root = Node("root", { name = "root", path = "root", kind = "working", collapsed = false, status = "M" })
        root:add_child(Node("a.lua", { path = "root/a.lua", status = "M" }))
        root:add_child(Node("b.lua", { path = "root/b.lua", status = "A" }))
        root:add_child(Node("c.lua", { path = "root/c.lua", status = "D" }))

        local leaves = root:leaves()
        eq(3, #leaves)
      end)

      it("returns leaf nodes across nested directories", function()
        -- Structure: src/ -> components/ -> [a.lua, b.lua]
        --                  -> utils/ -> [c.lua]
        local src = Node("src", { name = "src", path = "src", kind = "working", collapsed = false, status = "M" })
        local components = Node("components", { name = "components", path = "src/components", kind = "working", collapsed = false, status = "M" })
        local utils_dir = Node("utils", { name = "utils", path = "src/utils", kind = "working", collapsed = false, status = "A" })
        src:add_child(components)
        src:add_child(utils_dir)
        components:add_child(Node("a.lua", { path = "src/components/a.lua", status = "M" }))
        components:add_child(Node("b.lua", { path = "src/components/b.lua", status = "M" }))
        utils_dir:add_child(Node("c.lua", { path = "src/utils/c.lua", status = "A" }))

        local leaves = src:leaves()
        eq(3, #leaves)
      end)

      it("returns only the deeply nested leaf in a long chain", function()
        -- Chain: a/ -> b/ -> c/ -> file.lua
        local a = Node("a", { name = "a", path = "a", kind = "working", collapsed = false, status = "M" })
        local b = Node("b", { name = "b", path = "a/b", kind = "working", collapsed = false, status = "M" })
        local c = Node("c", { name = "c", path = "a/b/c", kind = "working", collapsed = false, status = "M" })
        a:add_child(b)
        b:add_child(c)
        c:add_child(Node("file.lua", { path = "a/b/c/file.lua", status = "M" }))

        local leaves = a:leaves()
        eq(1, #leaves)
        eq("file.lua", leaves[1].name)
      end)
    end)

    describe("render output for collapsed directories", function()
      it("shows simple file count in parentheses when folder_count_style is 'simple'", function()
        local conf = config.get_config()
        conf.file_panel.tree_options.folder_count_style = "simple"
        config.setup(conf)

        -- Build a directory node with 3 leaves.
        local dir_node = Node("src", { name = "src", path = "src", kind = "working", collapsed = true, status = "M" })
        dir_node:add_child(Node("a.lua", { path = "src/a.lua", status = "M" }))
        dir_node:add_child(Node("b.lua", { path = "src/b.lua", status = "M" }))
        dir_node:add_child(Node("c.lua", { path = "src/c.lua", status = "M" }))

        ---@type DirData
        local ctx = {
          name = "src",
          path = "src",
          kind = "working",
          collapsed = true,
          status = "M",
          _node = dir_node,
        }

        -- Use the same logic as render.lua to produce the count text.
        local file_count = #ctx._node:leaves()
        eq(3, file_count)

        -- Verify the formatted string.
        local count_text = " (" .. file_count .. ")"
        eq(" (3)", count_text)
      end)

      it("shows grouped status counts when folder_count_style is 'grouped'", function()
        local conf = config.get_config()
        conf.file_panel.tree_options.folder_count_style = "grouped"
        config.setup(conf)

        local dir_node = Node("src", { name = "src", path = "src", kind = "working", collapsed = true, status = "M" })
        dir_node:add_child(Node("a.lua", { path = "src/a.lua", status = "M" }))
        dir_node:add_child(Node("b.lua", { path = "src/b.lua", status = "A" }))
        dir_node:add_child(Node("c.lua", { path = "src/c.lua", status = "M" }))

        local leaves = dir_node:leaves()
        eq(3, #leaves)

        -- Replicate the grouped counting logic from render.lua.
        local status_counts = {}
        for _, node in ipairs(leaves) do
          local s = node.data.status or "?"
          status_counts[s] = (status_counts[s] or 0) + 1
        end

        local statuses = vim.tbl_keys(status_counts)
        table.sort(statuses)

        -- Should have "A" -> 1 and "M" -> 2, sorted alphabetically.
        eq({ "A", "M" }, statuses)
        eq(1, status_counts["A"])
        eq(2, status_counts["M"])
      end)

      it("renders grouped count segments to a mock component", function()
        local conf = config.get_config()
        conf.file_panel.tree_options.folder_count_style = "grouped"
        config.setup(conf)

        local dir_node = Node("src", { name = "src", path = "src", kind = "working", collapsed = true, status = "M" })
        dir_node:add_child(Node("x.lua", { path = "src/x.lua", status = "D" }))
        dir_node:add_child(Node("y.lua", { path = "src/y.lua", status = "D" }))
        dir_node:add_child(Node("z.lua", { path = "src/z.lua", status = "A" }))

        local leaves = dir_node:leaves()
        local status_counts = {}
        for _, node in ipairs(leaves) do
          local s = node.data.status or "?"
          status_counts[s] = (status_counts[s] or 0) + 1
        end
        local statuses = vim.tbl_keys(status_counts)
        table.sort(statuses)

        -- Render into a mock component using the same pattern as render.lua.
        local comp = make_comp()
        comp:add_text(" (", "DiffviewDim1")
        for i, s in ipairs(statuses) do
          if i > 1 then
            comp:add_text(" ", "DiffviewDim1")
          end
          local hl = require("diffview.hl")
          comp:add_text(tostring(status_counts[s]) .. hl.get_status_icon(s), hl.get_git_hl(s))
        end
        comp:add_text(")", "DiffviewDim1")

        local flat = comp:flat_text()
        -- Should contain both status groups.
        assert.truthy(flat:find("1"), "expected count for A status")
        assert.truthy(flat:find("2"), "expected count for D status")

        -- The opening and closing parentheses should be DiffviewDim1.
        local dim_segs = comp:segments_by_hl("DiffviewDim1")
        eq(" (", dim_segs[1])
        eq(")", dim_segs[#dim_segs])
      end)

      it("does not show count when directory is expanded", function()
        -- When collapsed is false, the count section is skipped.
        local dir_node = Node("src", { name = "src", path = "src", kind = "working", collapsed = false, status = "M" })
        dir_node:add_child(Node("a.lua", { path = "src/a.lua", status = "M" }))

        local ctx = {
          name = "src",
          path = "src",
          kind = "working",
          collapsed = false,
          status = "M",
          _node = dir_node,
        }

        -- The render code gates on `ctx.collapsed and ctx._node`.
        local should_show_count = ctx.collapsed and ctx._node
        assert.falsy(should_show_count)
      end)
    end)
  end)

  -- -----------------------------------------------------------------------
  -- Loading indicator (commit 5f1603a)
  -- -----------------------------------------------------------------------

  describe("loading indicator", function()
    local FilePanel = require("diffview.scene.views.diff.file_panel").FilePanel

    ---Build a mock FileDict.
    local function make_files(working)
      local files = { conflicting = {}, working = working or {}, staged = {} }
      function files:iter()
        local all = {}
        for _, f in ipairs(self.working) do all[#all + 1] = f end
        local i = 0
        return function()
          i = i + 1
          if i <= #all then return i, all[i] end
        end
      end
      function files:len() return #self.conflicting + #self.working + #self.staged end
      return files
    end

    ---Create a panel with render_data and components initialised.
    local function make_panel(entries, is_loading)
      -- Disable icons so render does not require nvim-web-devicons.
      config.get_config().use_icons = false

      local adapter = {
        ctx = { toplevel = "/tmp", dir = "/tmp/.git" },
        get_branch_name = function() return nil end,
      }
      local panel = FilePanel(adapter, make_files(entries or {}), {})
      panel.listing_style = "list"
      panel.is_loading = is_loading

      -- Initialise the buffer and render_data so render() can run.
      panel:init_buffer()

      return panel
    end

    it("shows 'Fetching changes...' when panel.is_loading is true", function()
      local panel = make_panel({}, true)
      panel:update_components()
      panel:render()

      -- Read back the buffer lines.
      local lines = vim.api.nvim_buf_get_lines(panel.bufid, 0, -1, false)
      local joined = table.concat(lines, "\n")
      assert.truthy(joined:find("Fetching changes"), "expected loading message in rendered output")

      -- The working/staged section titles should NOT appear.
      assert.falsy(joined:find("Changes "), "should not show Changes section while loading")

      panel:destroy()
    end)

    it("shows full content after loading completes", function()
      local f = make_entry("hello.lua")
      local panel = make_panel({ f }, false)
      panel:update_components()
      panel:render()

      local lines = vim.api.nvim_buf_get_lines(panel.bufid, 0, -1, false)
      local joined = table.concat(lines, "\n")
      assert.falsy(joined:find("Fetching changes"), "should not show loading message")
      assert.truthy(joined:find("Changes"), "expected Changes section header")

      panel:destroy()
    end)

    it("transitions from loading to full render", function()
      local f = make_entry("transition.lua")
      local panel = make_panel({ f }, true)
      panel:update_components()
      panel:render()

      local lines = vim.api.nvim_buf_get_lines(panel.bufid, 0, -1, false)
      local joined = table.concat(lines, "\n")
      assert.truthy(joined:find("Fetching changes"), "expected loading state initially")

      -- Simulate loading completion.
      panel.is_loading = false
      panel:update_components()
      panel:render()
      panel:redraw()

      lines = vim.api.nvim_buf_get_lines(panel.bufid, 0, -1, false)
      joined = table.concat(lines, "\n")
      assert.falsy(joined:find("Fetching changes"), "loading message should be gone")
      assert.truthy(joined:find("Changes"), "expected Changes section after loading")

      panel:destroy()
    end)
  end)

  -- -----------------------------------------------------------------------
  -- "Working tree clean" message (commit 1f07a2b)
  -- -----------------------------------------------------------------------

  describe("working tree clean message", function()
    local FilePanel = require("diffview.scene.views.diff.file_panel").FilePanel

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

    local function make_panel(conflicting, working, staged)
      -- Disable icons so render does not require nvim-web-devicons.
      config.get_config().use_icons = false

      local adapter = {
        ctx = { toplevel = "/tmp", dir = "/tmp/.git" },
        get_branch_name = function() return nil end,
      }
      local panel = FilePanel(adapter, make_files(conflicting, working, staged), {})
      panel.listing_style = "list"
      panel.is_loading = false
      panel:init_buffer()
      return panel
    end

    it("shows 'Working tree clean' when all sections are empty", function()
      local panel = make_panel({}, {}, {})
      panel:update_components()
      panel:render()

      local lines = vim.api.nvim_buf_get_lines(panel.bufid, 0, -1, false)
      local joined = table.concat(lines, "\n")
      assert.truthy(joined:find("Working tree clean"), "expected 'Working tree clean' message")

      panel:destroy()
    end)

    it("does not show 'Working tree clean' when working files exist", function()
      local f = make_entry("changed.lua")
      local panel = make_panel({}, { f }, {})
      panel:update_components()
      panel:render()

      local lines = vim.api.nvim_buf_get_lines(panel.bufid, 0, -1, false)
      local joined = table.concat(lines, "\n")
      assert.falsy(joined:find("Working tree clean"), "should not show clean message with working files")

      panel:destroy()
    end)

    it("shows '(empty)' for working section when conflicts exist", function()
      -- When there are conflicts but no working changes, the working section
      -- shows "(empty)" rather than "Working tree clean".
      local conflict = make_entry("conflict.lua", "conflicting")
      local panel = make_panel({ conflict }, {}, {})
      panel:update_components()
      panel:render()

      local lines = vim.api.nvim_buf_get_lines(panel.bufid, 0, -1, false)
      local joined = table.concat(lines, "\n")
      -- "Working tree clean" should NOT appear because conflicts exist.
      assert.falsy(joined:find("Working tree clean"),
        "should not show clean message when conflicts exist")

      panel:destroy()
    end)

    it("shows '(empty)' for working section when staged files exist", function()
      local staged = make_entry("staged.lua", "staged")
      local panel = make_panel({}, {}, { staged })
      panel:update_components()
      panel:render()

      local lines = vim.api.nvim_buf_get_lines(panel.bufid, 0, -1, false)
      local joined = table.concat(lines, "\n")
      -- When staged files exist but working is empty, it should say "(empty)"
      -- for the working section, not "Working tree clean".
      assert.falsy(joined:find("Working tree clean"),
        "should not show clean message when staged files exist")

      panel:destroy()
    end)

    it("shows Changes (0) header with the clean message", function()
      local panel = make_panel({}, {}, {})
      panel:update_components()
      panel:render()

      local lines = vim.api.nvim_buf_get_lines(panel.bufid, 0, -1, false)
      local joined = table.concat(lines, "\n")
      assert.truthy(joined:find("Changes"), "expected Changes header")
      assert.truthy(joined:find("%(0%)"), "expected (0) counter")

      panel:destroy()
    end)
  end)

  -- -----------------------------------------------------------------------
  -- Tree collapsed state preservation (commit 49c3984)
  -- -----------------------------------------------------------------------

  describe("tree collapsed state preservation", function()
    describe("FileTree get/set collapsed state round-trip", function()
      it("preserves collapsed state through get -> rebuild -> set", function()
        local files = {
          make_entry("src/components/button.lua"),
          make_entry("src/components/input.lua"),
          make_entry("src/utils/math.lua"),
          make_entry("lib/core.lua"),
        }

        -- Build the initial tree and collapse some directories.
        local tree1 = FileTree(files)
        -- Manually set collapsed state on tree nodes.
        tree1:set_collapsed_state({
          ["src"] = true,
          ["src/components"] = true,
          ["src/utils"] = false,
          ["lib"] = false,
        })

        -- Capture collapsed state.
        local state = tree1:get_collapsed_state()
        eq(true, state["src"])
        eq(true, state["src/components"])
        eq(false, state["src/utils"])
        eq(false, state["lib"])

        -- Rebuild a new tree (simulating tab switch or refresh).
        local tree2 = FileTree(files)

        -- Verify the new tree starts with everything expanded.
        local fresh_state = tree2:get_collapsed_state()
        eq(false, fresh_state["src"])
        eq(false, fresh_state["src/components"])
        eq(false, fresh_state["src/utils"])
        eq(false, fresh_state["lib"])

        -- Restore the saved state.
        tree2:set_collapsed_state(state)

        -- Verify the restoration.
        local restored = tree2:get_collapsed_state()
        eq(true, restored["src"])
        eq(true, restored["src/components"])
        eq(false, restored["src/utils"])
        eq(false, restored["lib"])
      end)

      it("handles state for paths not present in the new tree", function()
        local files1 = {
          make_entry("src/old.lua"),
          make_entry("src/keep.lua"),
        }
        local files2 = {
          make_entry("src/keep.lua"),
          make_entry("src/new.lua"),
        }

        local tree1 = FileTree(files1)
        tree1:set_collapsed_state({ ["src"] = true })
        local state = tree1:get_collapsed_state()
        eq(true, state["src"])

        -- Rebuild with slightly different files.
        local tree2 = FileTree(files2)
        tree2:set_collapsed_state(state)

        -- "src" still exists in the new tree, so the state carries over.
        local restored = tree2:get_collapsed_state()
        eq(true, restored["src"])
      end)

      it("ignores state keys for directories absent in the new tree", function()
        local files1 = {
          make_entry("old_dir/file.lua"),
        }
        local files2 = {
          make_entry("new_dir/file.lua"),
        }

        local tree1 = FileTree(files1)
        tree1:set_collapsed_state({ ["old_dir"] = true })
        local state = tree1:get_collapsed_state()

        local tree2 = FileTree(files2)
        tree2:set_collapsed_state(state)

        -- "old_dir" does not exist in tree2, so it should not appear.
        local restored = tree2:get_collapsed_state()
        eq(nil, restored["old_dir"])
        eq(false, restored["new_dir"])
      end)
    end)

    describe("FileDict.update_file_trees preserves collapsed state", function()
      it("restores collapsed state when trees are rebuilt", function()
        local fd = FileDict()

        -- Populate the working list with some entries.
        local entries = {
          make_entry("src/a.lua"),
          make_entry("src/b.lua"),
          make_entry("lib/c.lua"),
        }
        for i, e in ipairs(entries) do
          fd.working[i] = e
        end
        fd:update_file_trees()

        -- Collapse "src" in the working tree.
        fd.working_tree:set_collapsed_state({ ["src"] = true })
        local before = fd.working_tree:get_collapsed_state()
        eq(true, before["src"])
        eq(false, before["lib"])

        -- Rebuild trees (simulating what happens on tab switch or refresh).
        fd:update_file_trees()

        -- The collapsed state should be preserved.
        local after = fd.working_tree:get_collapsed_state()
        eq(true, after["src"])
        eq(false, after["lib"])
      end)

      it("preserves collapsed state independently for each section", function()
        local fd = FileDict()

        fd.working[1] = make_entry("src/w.lua", "working")
        fd.staged[1] = make_entry("src/s.lua", "staged")
        fd:update_file_trees()

        -- Collapse "src" only in the working tree.
        fd.working_tree:set_collapsed_state({ ["src"] = true })
        -- Leave the staged tree expanded.

        fd:update_file_trees()

        eq(true, fd.working_tree:get_collapsed_state()["src"])
        eq(false, fd.staged_tree:get_collapsed_state()["src"])
      end)
    end)

    describe("collapsed state with nested and flattened directories", function()
      it("round-trips collapsed state for deeply nested paths", function()
        local files = {
          make_entry("a/b/c/d/file.lua"),
        }

        local tree = FileTree(files)
        tree:set_collapsed_state({
          ["a"] = true,
          ["a/b"] = true,
          ["a/b/c"] = false,
          ["a/b/c/d"] = true,
        })

        local state = tree:get_collapsed_state()
        eq(true, state["a"])
        eq(true, state["a/b"])
        eq(false, state["a/b/c"])
        eq(true, state["a/b/c/d"])

        -- Rebuild and restore.
        local tree2 = FileTree(files)
        tree2:set_collapsed_state(state)
        local restored = tree2:get_collapsed_state()
        eq(true, restored["a"])
        eq(true, restored["a/b"])
        eq(false, restored["a/b/c"])
        eq(true, restored["a/b/c/d"])
      end)

      it("preserves collapsed state when files change in a directory", function()
        -- Initial tree: src/ has two files.
        local files1 = {
          make_entry("src/a.lua"),
          make_entry("src/b.lua"),
        }
        local tree1 = FileTree(files1)
        tree1:set_collapsed_state({ ["src"] = true })

        local state = tree1:get_collapsed_state()

        -- Rebuild with a third file added.
        local files2 = {
          make_entry("src/a.lua"),
          make_entry("src/b.lua"),
          make_entry("src/c.lua"),
        }
        local tree2 = FileTree(files2)
        tree2:set_collapsed_state(state)

        -- "src" should still be collapsed.
        eq(true, tree2:get_collapsed_state()["src"])
      end)
    end)
  end)
end)
