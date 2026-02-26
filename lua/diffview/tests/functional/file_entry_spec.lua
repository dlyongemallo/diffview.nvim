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
    assert.has_no.errors(function()
      entry:convert_layout(Diff2Hor)
    end)

    assert.are.equal(original_layout, entry.layout)
  end)

  it("does not treat should_null errors as truthy null markers", function()
    local captured
    local layout_class = setmetatable({
      should_null = function()
        error("boom")
      end,
    }, {
      __call = function(_, opt)
        captured = opt
        return {
          files = function()
            return { opt.b }
          end,
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

  it("forwards force flag to contained files when destroyed", function()
    local seen = {}
    local layout_destroyed = false

    local layout = {
      files = function()
        return {
          {
            destroy = function(_, force)
              seen[#seen + 1] = force
            end,
          },
          {
            destroy = function(_, force)
              seen[#seen + 1] = force
            end,
          },
        }
      end,
      destroy = function()
        layout_destroyed = true
      end,
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
