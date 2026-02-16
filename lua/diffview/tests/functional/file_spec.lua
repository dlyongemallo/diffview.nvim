local async = require("diffview.async")
local File = require("diffview.vcs.file").File
local GitRev = require("diffview.vcs.adapters.git.rev").GitRev
local RevType = require("diffview.vcs.rev").RevType

describe("diffview.vcs.file", function()
  it("uses the null buffer when a conflict stage blob is missing", function()
    local show_called = false

    local adapter = {
      ctx = {
        toplevel = vim.uv.cwd(),
        dir = vim.uv.cwd(),
      },
      file_blob_hash = function(_, _, rev_arg)
        assert.equals(":2", rev_arg)
        return nil
      end,
      is_binary = function()
        return false
      end,
      show = function(_, _, _, callback)
        show_called = true
        callback(nil, { "unexpected" })
      end,
    }

    local file = File({
      adapter = adapter,
      path = "README.md",
      kind = "conflicting",
      rev = GitRev(RevType.STAGE, 2),
    })

    local bufnr = async.await(file:create_buffer())

    assert.equals(File._get_null_buffer(), bufnr)
    assert.False(show_called)
  end)
end)
