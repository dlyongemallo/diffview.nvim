local Diff1 = require("diffview.scene.layouts.diff_1").Diff1
local Diff2 = require("diffview.scene.layouts.diff_2").Diff2
local Diff3 = require("diffview.scene.layouts.diff_3").Diff3
local Diff4 = require("diffview.scene.layouts.diff_4").Diff4
local Layout = require("diffview.scene.layout").Layout
local RevType = require("diffview.vcs.rev").RevType
local helpers = require("diffview.tests.helpers")

local eq = helpers.eq

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

describe("diffview.layout symbols", function()
  it("Diff1 declares symbols { 'b' }", function()
    eq({ "b" }, Diff1.symbols)
  end)

  it("Diff2 declares symbols { 'a', 'b' }", function()
    eq({ "a", "b" }, Diff2.symbols)
  end)

  it("Diff3 declares symbols { 'a', 'b', 'c' }", function()
    eq({ "a", "b", "c" }, Diff3.symbols)
  end)

  it("Diff4 declares symbols { 'a', 'b', 'c', 'd' }", function()
    eq({ "a", "b", "c", "d" }, Diff4.symbols)
  end)
end)

describe("diffview.layout.set_file_for", function()
  it("sets the file on the window and tags it with the symbol", function()
    local stored_file
    local mock_win = { set_file = function(_, f) stored_file = f end }
    local mock_layout = { a = mock_win, windows = {}, symbols = { "a" } }
    setmetatable(mock_layout, { __index = Layout })

    local file = { path = "test.lua" }
    mock_layout:set_file_for("a", file)

    eq(file, stored_file)
    eq("a", file.symbol)
  end)
end)
