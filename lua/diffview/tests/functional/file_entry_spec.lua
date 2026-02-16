local FileEntry = require("diffview.scene.file_entry").FileEntry
local RevType = require("diffview.vcs.rev").RevType
local GitRev = require("diffview.vcs.adapters.git.rev").GitRev

describe("diffview.file_entry", function()
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
