local Window = require("diffview.scene.window").Window

-- Tests for the fold-limit fix (a67a808) and its successor (fc62484).
--
-- Commit a67a808 introduced Window.MAX_CUSTOM_FOLDS and a guard in
-- apply_custom_folds to skip fold creation when the count exceeds the
-- limit. Later, commit fc62484 removed custom fold creation entirely
-- because setting foldmethod=manual triggers a Neovim screen-redraw bug
-- that freezes the editor. These tests verify the removal holds.

describe("fold limit removal (a67a808, fc62484)", function()
  it("Window.MAX_CUSTOM_FOLDS is no longer defined", function()
    -- The constant was introduced in a67a808 and removed in fc62484.
    assert.is_nil(Window.MAX_CUSTOM_FOLDS)
  end)

  it("Window:apply_custom_folds is no longer defined", function()
    -- The method was introduced before a67a808 and removed in fc62484.
    assert.is_nil(Window.apply_custom_folds)
  end)

  it("Window:post_open does not reference custom folds", function()
    -- post_open previously called apply_custom_folds. After removal it
    -- should still exist but must not error when called on a minimal
    -- window object (no file.custom_folds field needed).
    assert.is_function(Window.post_open)

    -- Calling post_open on a bare Window instance should not error.
    local win = Window({ id = vim.api.nvim_get_current_win() })
    assert.has_no.errors(function()
      win:post_open()
    end)
  end)

  it("File class has no custom_folds field by default", function()
    -- custom_folds was removed from the File class in fc62484.
    local File = require("diffview.vcs.file").File
    local GitRev = require("diffview.vcs.adapters.git.rev").GitRev
    local RevType = require("diffview.vcs.rev").RevType

    local adapter = {
      ctx = { toplevel = vim.uv.cwd(), dir = vim.uv.cwd() },
      is_binary = function()
        return false
      end,
    }

    local file = File({
      adapter = adapter,
      path = "test.lua",
      kind = "working",
      rev = GitRev(RevType.COMMIT, "abc1234"),
    })

    assert.is_nil(file.custom_folds)
  end)
end)
