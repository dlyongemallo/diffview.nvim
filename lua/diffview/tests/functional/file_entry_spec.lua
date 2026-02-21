local FileEntry = require("diffview.scene.file_entry").FileEntry
local Diff2Hor = require("diffview.scene.layouts.diff_2_hor").Diff2Hor
local RevType = require("diffview.vcs.rev").RevType
local GitRev = require("diffview.vcs.adapters.git.rev").GitRev

describe("diffview.file_entry", function()
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
end)
