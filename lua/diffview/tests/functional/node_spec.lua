local helpers = require("diffview.tests.helpers")

local eq = helpers.eq

describe("diffview.ui.models.file_tree.node", function()
  local Node = require("diffview.ui.models.file_tree.node").Node
  local config = require("diffview.config")

  describe("Node.comparator", function()
    local saved_get_config

    before_each(function()
      saved_get_config = config.get_config
    end)

    after_each(function()
      config.get_config = saved_get_config
    end)

    ---Create a directory node (a node with at least one child).
    ---@param name string
    ---@param data any?
    ---@return Node
    local function make_dir(name, data)
      local node = Node(name, data or {})
      node:add_child(Node("_placeholder"))
      return node
    end

    ---Create a file node (a leaf with no children).
    ---@param name string
    ---@param data any?
    ---@return Node
    local function make_file(name, data)
      return Node(name, data or {})
    end

    ---Stub config.get_config to return the given sort_file value.
    ---@param sort_file function|nil
    local function stub_config(sort_file)
      config.get_config = function()
        return { file_panel = { sort_file = sort_file } }
      end
    end

    -- -- Directories vs. files -- --

    it("directory sorts before file", function()
      stub_config(nil)
      local dir = make_dir("zebra")
      local file = make_file("alpha")
      eq(true, Node.comparator(dir, file))
    end)

    it("file sorts after directory", function()
      stub_config(nil)
      local dir = make_dir("alpha")
      local file = make_file("zebra")
      eq(false, Node.comparator(file, dir))
    end)

    -- -- Two directories: alphabetical fallback -- --

    it("two directories sort alphabetically case-insensitive", function()
      stub_config(nil)
      local a = make_dir("Alpha")
      local b = make_dir("beta")
      eq(true, Node.comparator(a, b))
    end)

    it("two directories in reverse order", function()
      stub_config(nil)
      local a = make_dir("beta")
      local b = make_dir("Alpha")
      eq(false, Node.comparator(a, b))
    end)

    -- -- Two files: alphabetical fallback -- --

    it("two files sort alphabetically case-insensitive", function()
      stub_config(nil)
      local a = make_file("Apple")
      local b = make_file("banana")
      eq(true, Node.comparator(a, b))
    end)

    it("two files in reverse alphabetical order", function()
      stub_config(nil)
      local a = make_file("banana")
      local b = make_file("Apple")
      eq(false, Node.comparator(a, b))
    end)

    it("two files with same name (case-insensitive) are not ordered", function()
      stub_config(nil)
      local a = make_file("Readme")
      local b = make_file("readme")
      -- string.lower("Readme") < string.lower("readme") => false
      eq(false, Node.comparator(a, b))
      eq(false, Node.comparator(b, a))
    end)

    -- -- Custom sort_file comparator -- --

    it("custom sort_file is called with correct arguments", function()
      local captured_args = {}
      local a_data = { path = "src/a.lua", status = "M" }
      local b_data = { path = "src/b.lua", status = "A" }

      stub_config(function(a_name, b_name, a_d, b_d)
        captured_args = { a_name = a_name, b_name = b_name, a_data = a_d, b_data = b_d }
        return true
      end)

      local a = make_file("a.lua", a_data)
      local b = make_file("b.lua", b_data)
      Node.comparator(a, b)

      eq("a.lua", captured_args.a_name)
      eq("b.lua", captured_args.b_name)
      eq(a_data, captured_args.a_data)
      eq(b_data, captured_args.b_data)
    end)

    it("custom sort_file returning true puts a before b", function()
      stub_config(function() return true end)
      local a = make_file("z.lua")
      local b = make_file("a.lua")
      eq(true, Node.comparator(a, b))
    end)

    it("custom sort_file returning false puts b before a", function()
      stub_config(function() return false end)
      local a = make_file("a.lua")
      local b = make_file("z.lua")
      eq(false, Node.comparator(a, b))
    end)

    it("custom sort_file is not called for directory-vs-file comparisons", function()
      local called = false
      stub_config(function()
        called = true
        return true
      end)

      local dir = make_dir("src")
      local file = make_file("readme.md")
      Node.comparator(dir, file)

      eq(false, called)
    end)

    it("custom sort_file is not called for directory-vs-directory comparisons", function()
      local called = false
      stub_config(function()
        called = true
        return true
      end)

      local a = make_dir("alpha")
      local b = make_dir("beta")
      Node.comparator(a, b)

      eq(false, called)
    end)

    -- -- Config without sort_file falls back to alphabetical -- --

    it("nil sort_file falls back to alphabetical", function()
      stub_config(nil)
      local a = make_file("alpha.lua")
      local b = make_file("beta.lua")
      eq(true, Node.comparator(a, b))
      eq(false, Node.comparator(b, a))
    end)

    it("non-function sort_file falls back to alphabetical", function()
      -- sort_file could be set to a non-function value by mistake; the code
      -- guards with type(sort_file) == "function".
      config.get_config = function()
        return { file_panel = { sort_file = "invalid" } }
      end

      local a = make_file("alpha.lua")
      local b = make_file("beta.lua")
      eq(true, Node.comparator(a, b))
      eq(false, Node.comparator(b, a))
    end)
  end)
end)
