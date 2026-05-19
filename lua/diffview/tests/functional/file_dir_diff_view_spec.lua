local helpers = require("diffview.tests.helpers")
local lib = require("diffview.lib")
local Diff2Hor = require("diffview.scene.layouts.diff_2_hor").Diff2Hor
local Diff3Hor = require("diffview.scene.layouts.diff_3_hor").Diff3Hor
local FileDirDiffView = require("diffview.scene.views.diff.file_dir_diff_view").FileDirDiffView
local NullAdapter = require("diffview.vcs.adapters.null").NullAdapter
local RevType = require("diffview.vcs.rev").RevType

local eq = helpers.eq

local function mktmpdir()
  local path = vim.fn.tempname()
  vim.fn.mkdir(path, "p")
  return path
end

local function write_file(path, content)
  local fd = io.open(path, "w")
  fd:write(content)
  fd:close()
end

local function rm_rf(path)
  vim.fn.delete(path, "rf")
end

---Populate a directory triple shaped like jj would lay it out: $left
---contains "before" content, $right contains "after" content, $output is a
---copy of $right ready for the user to edit. Returns paths to all three
---plus the shared parent (for cleanup).
---@return string left
---@return string right
---@return string output
---@return string root
local function fixture()
  local root = mktmpdir()
  local left = root .. "/left"
  local right = root .. "/right"
  local output = root .. "/output"
  vim.fn.mkdir(left .. "/sub", "p")
  vim.fn.mkdir(right .. "/sub", "p")
  vim.fn.mkdir(output .. "/sub", "p")

  write_file(left .. "/same.txt", "shared\n")
  write_file(right .. "/same.txt", "shared\n")
  write_file(output .. "/same.txt", "shared\n")

  write_file(left .. "/changed.txt", "before\n")
  write_file(right .. "/changed.txt", "after\n")
  write_file(output .. "/changed.txt", "after\n")

  write_file(left .. "/only_left.txt", "left-only\n")
  write_file(right .. "/only_right.txt", "right-only\n")
  write_file(output .. "/only_right.txt", "right-only\n")

  write_file(left .. "/sub/nested.txt", "nested-before\n")
  write_file(right .. "/sub/nested.txt", "nested-after\n")
  write_file(output .. "/sub/nested.txt", "nested-after\n")

  return left, right, output, root
end

describe("diffview.scene.views.diff.file_dir_diff_view", function()
  local left, right, output, root

  before_each(function()
    left, right, output, root = fixture()
  end)

  after_each(function()
    rm_rf(root)
  end)

  describe("FileDirDiffView constructor (2-pane)", function()
    it("creates a valid view", function()
      local adapter = NullAdapter.create({ toplevel = right })
      local view = FileDirDiffView({
        adapter = adapter,
        left_path = left,
        right_path = right,
      })

      assert.True(view:is_valid())
      eq(left, view.left_path)
      eq(right, view.right_path)
      assert.is_nil(view.output_path)
    end)

    it("lists exactly the differing paths", function()
      local adapter = NullAdapter.create({ toplevel = right })
      local view = FileDirDiffView({
        adapter = adapter,
        left_path = left,
        right_path = right,
      })

      local paths = {}
      for _, e in ipairs(view.files.working) do
        paths[e.path] = e.status
      end

      eq("M", paths["changed.txt"])
      eq("D", paths["only_left.txt"])
      eq("A", paths["only_right.txt"])
      eq("M", paths["sub/nested.txt"]) -- recursive walk
      assert.is_nil(paths["same.txt"]) -- identical content filtered out
    end)

    it("uses Diff2Hor with both sides bound to LOCAL", function()
      local adapter = NullAdapter.create({ toplevel = right })
      local view = FileDirDiffView({
        adapter = adapter,
        left_path = left,
        right_path = right,
      })

      local e = view.files.working[1]
      assert.True(e.layout:instanceof(Diff2Hor))
      eq(RevType.LOCAL, e.revs.a.type)
      eq(RevType.LOCAL, e.revs.b.type)
    end)

    it("points each entry's a/b file at the matching left/right path", function()
      local adapter = NullAdapter.create({ toplevel = right })
      local view = FileDirDiffView({
        adapter = adapter,
        left_path = left,
        right_path = right,
      })

      for _, e in ipairs(view.files.working) do
        eq(left .. "/" .. e.path, e.layout.a.file.path)
        eq(right .. "/" .. e.path, e.layout.b.file.path)
      end
    end)
  end)

  describe("FileDirDiffView constructor (3-pane)", function()
    it("uses Diff3Hor when output is provided", function()
      local adapter = NullAdapter.create({ toplevel = output })
      local view = FileDirDiffView({
        adapter = adapter,
        left_path = left,
        right_path = right,
        output_path = output,
      })

      local e = view.files.working[1]
      assert.True(e.layout:instanceof(Diff3Hor))
    end)

    it("makes the b-side LOCAL (editable output) and a/c CUSTOM (read-only)", function()
      local adapter = NullAdapter.create({ toplevel = output })
      local view = FileDirDiffView({
        adapter = adapter,
        left_path = left,
        right_path = right,
        output_path = output,
      })

      local e = view.files.working[1]
      eq(RevType.CUSTOM, e.revs.a.type)
      eq(RevType.LOCAL, e.revs.b.type)
      eq(RevType.CUSTOM, e.revs.c.type)
    end)

    it("points b at $output/<rel>, a at $left/<rel>, c at $right/<rel>", function()
      local adapter = NullAdapter.create({ toplevel = output })
      local view = FileDirDiffView({
        adapter = adapter,
        left_path = left,
        right_path = right,
        output_path = output,
      })

      for _, e in ipairs(view.files.working) do
        eq(left .. "/" .. e.path, e.layout.a.file.path)
        eq(output .. "/" .. e.path, e.layout.b.file.path)
        eq(right .. "/" .. e.path, e.layout.c.file.path)
      end
    end)
  end)

  describe("lib.diffview_dir_diff", function()
    local function dispose(view)
      for i, v in ipairs(lib.views) do
        if v == view then
          table.remove(lib.views, i)
          break
        end
      end
    end

    it("returns nil when given fewer than two paths", function()
      assert.is_nil(lib.diffview_dir_diff({}))
      assert.is_nil(lib.diffview_dir_diff({ left }))
    end)

    it("returns nil when given more than three paths", function()
      assert.is_nil(lib.diffview_dir_diff({ left, right, output, "extra" }))
    end)

    it("returns nil when a path is not a directory", function()
      local file_path = left .. "/changed.txt"
      assert.is_nil(lib.diffview_dir_diff({ file_path, right }))
    end)

    it("returns nil when a directory does not exist", function()
      assert.is_nil(lib.diffview_dir_diff({ left, "/nonexistent/dir" }))
    end)

    it("creates a 2-pane FileDirDiffView from two valid dirs", function()
      local view = lib.diffview_dir_diff({ left, right })
      assert.is_not_nil(view)
      assert.True(view:is_valid())
      assert.is_nil(view.output_path)
      dispose(view)
    end)

    it("creates a 3-pane FileDirDiffView when output is provided", function()
      local view = lib.diffview_dir_diff({ left, right, output })
      assert.is_not_nil(view)
      assert.True(view:is_valid())
      eq(output, view.output_path)
      dispose(view)
    end)

    it("returns nil when the two sides have no differences", function()
      -- Use the same directory as both inputs so the walks produce identical
      -- file sets with identical content. External diff drivers like jj
      -- would otherwise be left in an editor with no file panel content.
      assert.is_nil(lib.diffview_dir_diff({ left, left }))
    end)
  end)

  describe("FileDirDiffView:update_files", function()
    it("is a no-op", function()
      local adapter = NullAdapter.create({ toplevel = right })
      local view = FileDirDiffView({
        adapter = adapter,
        left_path = left,
        right_path = right,
      })

      local len = view.files:len()
      assert.has_no.errors(function()
        view:update_files()
      end)
      eq(len, view.files:len())
    end)
  end)
end)
