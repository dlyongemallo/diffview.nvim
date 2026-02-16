local Diff2 = require("diffview.scene.layouts.diff_2").Diff2
local RevType = require("diffview.vcs.rev").RevType

describe("diffview.layout null detection", function()
  it("treats COMMIT-side deletions as null in window b for Diff2", function()
    local rev = { type = RevType.COMMIT }

    assert.True(Diff2.should_null(rev, "D", "b"))
    assert.False(Diff2.should_null(rev, "M", "b"))
    assert.True(Diff2.should_null(rev, "A", "a"))
  end)
end)
