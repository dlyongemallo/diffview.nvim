local Diff2 = require("diffview.scene.layouts.diff_2").Diff2
local Diff3 = require("diffview.scene.layouts.diff_3").Diff3
local Diff4 = require("diffview.scene.layouts.diff_4").Diff4
local RevType = require("diffview.vcs.rev").RevType

describe("diffview.layout null detection", function()
  it("treats COMMIT-side deletions as null in window b for Diff2", function()
    local rev = { type = RevType.COMMIT }

    assert.True(Diff2.should_null(rev, "D", "b"))
    assert.False(Diff2.should_null(rev, "M", "b"))
    assert.True(Diff2.should_null(rev, "A", "a"))
  end)

  it("keeps merge stages non-null in Diff3 and Diff4", function()
    local stage2 = { type = RevType.STAGE, stage = 2 }

    assert.False(Diff3.should_null(stage2, "U", "a"))
    assert.False(Diff4.should_null(stage2, "U", "a"))
  end)

  it("handles LOCAL/COMMIT nulling consistently in Diff3 and Diff4", function()
    local local_rev = { type = RevType.LOCAL }
    local commit_rev = { type = RevType.COMMIT }

    assert.True(Diff3.should_null(local_rev, "D", "b"))
    assert.True(Diff4.should_null(local_rev, "D", "b"))
    assert.True(Diff3.should_null(commit_rev, "D", "c"))
    assert.True(Diff4.should_null(commit_rev, "D", "d"))
    assert.True(Diff3.should_null(commit_rev, "A", "a"))
    assert.True(Diff4.should_null(commit_rev, "A", "a"))
  end)
end)
