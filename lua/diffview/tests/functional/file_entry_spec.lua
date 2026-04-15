local helpers = require("diffview.tests.helpers")
local FileEntry = require("diffview.scene.file_entry").FileEntry
local Diff2Hor = require("diffview.scene.layouts.diff_2_hor").Diff2Hor
local RevType = require("diffview.vcs.rev").RevType
local GitRev = require("diffview.vcs.adapters.git.rev").GitRev

local eq = helpers.eq

describe("diffview.scene.file_entry", function()
  it("convert_layout skips null entries without error (#612)", function()
    local adapter = { ctx = { toplevel = vim.uv.cwd() } }
    local entry = FileEntry.new_null_entry(adapter)
    local original_layout = entry.layout

    -- Must not error; null entries have no revs.
    assert.has_no.errors(function() entry:convert_layout(Diff2Hor) end)

    assert.are.equal(original_layout, entry.layout)
  end)

  it("convert_layout calls teardown_render on the outgoing layout", function()
    local teardown_calls = 0
    local rev = GitRev(RevType.STAGE, 0)
    local file_b = { bufnr = -1 }
    local old_layout = {
      files = function() return { file_b } end,
      owned_files = function() return { file_b } end,
      get_file_for = function(_, sym) return sym == "b" and file_b or nil end,
      teardown_render = function() teardown_calls = teardown_calls + 1 end,
    }

    local entry = FileEntry({
      adapter = { ctx = { toplevel = vim.uv.cwd() } },
      path = "README.md",
      oldpath = nil,
      revs = { a = rev, b = rev },
      layout = old_layout,
      status = "M",
      stats = {},
      kind = "working",
    })

    local new_layout = {}
    setmetatable(new_layout, {
      __call = function() return { files = function() return {} end } end,
    })

    entry:convert_layout(new_layout)
    eq(1, teardown_calls)
  end)

  it("does not treat should_null errors as truthy null markers", function()
    local captured
    local layout_class = setmetatable({
      should_null = function() error("boom") end,
    }, {
      __call = function(_, opt)
        captured = opt
        return {
          files = function() return { opt.b } end,
        }
      end,
    })

    local rev = GitRev(RevType.STAGE, 0)
    local adapter = { ctx = { toplevel = vim.uv.cwd() } }

    FileEntry.with_layout(layout_class, {
      adapter = adapter,
      path = "README.md",
      status = "M",
      kind = "working",
      revs = { a = rev, b = rev },
    })

    assert.is_not_nil(captured)
    assert.False(captured.b.nulled)
  end)

  describe("update_merge_context", function()
    local function make_entry_with_layout()
      local file_stubs = {}
      local layout = {}
      for _, key in ipairs({ "a", "b", "c", "d" }) do
        file_stubs[key] = { winbar = nil }
        layout[key] = { file = file_stubs[key] }
      end

      local entry = FileEntry({
        adapter = { ctx = { toplevel = "/tmp" } },
        path = "a.txt",
        oldpath = nil,
        revs = {},
        layout = layout,
        status = "M",
        stats = {},
        kind = "working",
      })

      return entry, layout, file_stubs
    end

    it("does not error when merge context entries have nil hashes", function()
      local entry, _, file_stubs = make_entry_with_layout()

      assert.has_no.errors(
        function()
          entry:update_merge_context({
            ours = {},
            theirs = {},
            base = {},
          })
        end
      )

      -- Winbars for ours/theirs/base should remain unset.
      assert.is_nil(file_stubs.a.winbar)
      assert.is_nil(file_stubs.c.winbar)
      assert.is_nil(file_stubs.d.winbar)
      -- LOCAL winbar is always set.
      eq(" LOCAL (Working tree)", file_stubs.b.winbar)
    end)

    it("sets winbars correctly when hashes are present", function()
      local entry, _, file_stubs = make_entry_with_layout()
      local hash = "abc123def456"

      entry:update_merge_context({
        ours = { hash = hash, ref_names = "main" },
        theirs = { hash = hash, ref_names = "feature" },
        base = { hash = hash },
      })

      assert.is_not_nil(file_stubs.a.winbar)
      assert.truthy(file_stubs.a.winbar:find("OURS"))
      assert.truthy(file_stubs.a.winbar:find("main"))
      assert.truthy(file_stubs.c.winbar:find("THEIRS"))
      assert.truthy(file_stubs.c.winbar:find("feature"))
      assert.truthy(file_stubs.d.winbar:find("BASE"))
      assert.truthy(file_stubs.d.winbar:find(hash:sub(1, 10)))
      eq(" LOCAL (Working tree)", file_stubs.b.winbar)
    end)

    it("handles a mix of present and missing hashes", function()
      local entry, _, file_stubs = make_entry_with_layout()

      assert.has_no.errors(
        function()
          entry:update_merge_context({
            ours = { hash = "abc123def456" },
            theirs = {},
            base = { hash = "def789abc012" },
          })
        end
      )

      assert.truthy(file_stubs.a.winbar:find("OURS"))
      assert.is_nil(file_stubs.c.winbar)
      assert.truthy(file_stubs.d.winbar:find("BASE"))
    end)
  end)

  it("forwards force flag to contained files when destroyed", function()
    local seen = {}
    local layout_destroyed = false

    local files_list = {
      {
        destroy = function(_, force) seen[#seen + 1] = force end,
      },
      {
        destroy = function(_, force) seen[#seen + 1] = force end,
      },
    }
    local layout = {
      files = function() return files_list end,
      owned_files = function() return files_list end,
      destroy = function() layout_destroyed = true end,
    }

    local entry = FileEntry({
      adapter = { ctx = { toplevel = "/tmp" } },
      path = "a.txt",
      oldpath = nil,
      revs = {},
      layout = layout,
      status = "M",
      stats = {},
      kind = "working",
    })

    entry:destroy(true)

    eq({ true, true }, seen)
    eq(true, layout_destroyed)
  end)
end)
