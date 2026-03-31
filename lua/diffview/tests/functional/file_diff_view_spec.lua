local helpers = require("diffview.tests.helpers")
local lib = require("diffview.lib")
local Diff2Hor = require("diffview.scene.layouts.diff_2_hor").Diff2Hor
local NullAdapter = require("diffview.vcs.adapters.null").NullAdapter
local NullRev = require("diffview.vcs.adapters.null.rev").NullRev
local FileDiffView = require("diffview.scene.views.diff.file_diff_view").FileDiffView
local RevType = require("diffview.vcs.rev").RevType

local eq = helpers.eq

-- Create a temporary file with the given content and return its path.
local function tmpfile(content)
  local path = vim.fn.tempname()
  local f = io.open(path, "w")
  f:write(content)
  f:close()
  return path
end

describe("diffview.scene.views.diff.file_diff_view", function()
  describe("FileDiffView constructor", function()
    local left_path, right_path

    before_each(function()
      left_path = tmpfile("left content\n")
      right_path = tmpfile("right content\n")
    end)

    after_each(function()
      os.remove(left_path)
      os.remove(right_path)
    end)

    it("creates a valid view with two file paths", function()
      local adapter = NullAdapter.create({ toplevel = "/tmp" })
      local view = FileDiffView({
        adapter = adapter,
        left_path = left_path,
        right_path = right_path,
      })

      assert.True(view:is_valid())
      eq(left_path, view.left_path)
      eq(right_path, view.right_path)
    end)

    it("populates files with a single working entry", function()
      local adapter = NullAdapter.create({ toplevel = "/tmp" })
      local view = FileDiffView({
        adapter = adapter,
        left_path = left_path,
        right_path = right_path,
      })

      eq(1, view.files:len())
      eq(1, #view.files.working)
      eq(0, #view.files.staged)
      eq(0, #view.files.conflicting)
    end)

    it("sets the entry path and oldpath correctly", function()
      local adapter = NullAdapter.create({ toplevel = "/tmp" })
      local view = FileDiffView({
        adapter = adapter,
        left_path = left_path,
        right_path = right_path,
      })

      local entry = view.files.working[1]
      eq(right_path, entry.path)
      eq(left_path, entry.oldpath)
    end)

    it("uses LOCAL revs for both sides", function()
      local adapter = NullAdapter.create({ toplevel = "/tmp" })
      local view = FileDiffView({
        adapter = adapter,
        left_path = left_path,
        right_path = right_path,
      })

      local entry = view.files.working[1]
      eq(RevType.LOCAL, entry.revs.a.type)
      eq(RevType.LOCAL, entry.revs.b.type)
    end)

    it("defaults to Diff2Hor layout", function()
      local adapter = NullAdapter.create({ toplevel = "/tmp" })
      local view = FileDiffView({
        adapter = adapter,
        left_path = left_path,
        right_path = right_path,
      })

      local entry = view.files.working[1]
      assert.True(entry.layout:instanceof(Diff2Hor))
    end)

    it("uses a NullAdapter", function()
      local adapter = NullAdapter.create({ toplevel = "/tmp" })
      local view = FileDiffView({
        adapter = adapter,
        left_path = left_path,
        right_path = right_path,
      })

      assert.True(view.adapter:instanceof(NullAdapter))
    end)
  end)

  describe("lib.diffview_diff_files", function()
    it("returns nil when not given exactly two args", function()
      local view = lib.diffview_diff_files({})
      assert.is_nil(view)

      view = lib.diffview_diff_files({ "one_file" })
      assert.is_nil(view)

      view = lib.diffview_diff_files({ "a", "b", "c" })
      assert.is_nil(view)
    end)

    it("returns nil when a file does not exist", function()
      local existing = tmpfile("content\n")
      local view = lib.diffview_diff_files({ existing, "/nonexistent/file" })
      assert.is_nil(view)
      os.remove(existing)
    end)

    it("creates a valid FileDiffView for two existing files", function()
      local left = tmpfile("left\n")
      local right = tmpfile("right\n")

      local view = lib.diffview_diff_files({ left, right })
      assert.is_not_nil(view)
      assert.True(view:is_valid())
      eq(1, view.files:len())

      -- Clean up the view from lib.views.
      for i, v in ipairs(lib.views) do
        if v == view then
          table.remove(lib.views, i)
          break
        end
      end

      os.remove(left)
      os.remove(right)
    end)
  end)

  describe("FileDiffView:update_files", function()
    it("is a no-op", function()
      local left = tmpfile("a\n")
      local right = tmpfile("b\n")
      local adapter = NullAdapter.create({ toplevel = "/tmp" })
      local view = FileDiffView({
        adapter = adapter,
        left_path = left,
        right_path = right,
      })

      -- Calling update_files should not error and should not change the file list.
      assert.has_no.errors(function() view:update_files() end)
      eq(1, view.files:len())

      os.remove(left)
      os.remove(right)
    end)
  end)
end)
