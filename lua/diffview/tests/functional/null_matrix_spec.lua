local Diff1 = require("diffview.scene.layouts.diff_1").Diff1
local Diff2 = require("diffview.scene.layouts.diff_2").Diff2
local Diff3 = require("diffview.scene.layouts.diff_3").Diff3
local Diff4 = require("diffview.scene.layouts.diff_4").Diff4
local RevType = require("diffview.vcs.rev").RevType

describe("diffview layout should_null matrix", function()
  it("returns booleans and never errors for supported symbols", function()
    local layouts = {
      { cls = Diff1, symbols = { "b" } },
      { cls = Diff2, symbols = { "a", "b" } },
      { cls = Diff3, symbols = { "a", "b", "c" } },
      { cls = Diff4, symbols = { "a", "b", "c", "d" } },
    }

    local revs = {
      { type = RevType.LOCAL },
      { type = RevType.COMMIT },
      { type = RevType.STAGE, stage = 0 },
      { type = RevType.STAGE, stage = 2 },
    }

    local statuses = { "A", "?", "M", "D", "U", " " }

    for _, layout in ipairs(layouts) do
      for _, rev in ipairs(revs) do
        for _, status in ipairs(statuses) do
          for _, sym in ipairs(layout.symbols) do
            local ok, value = pcall(layout.cls.should_null, rev, status, sym)
            assert.True(ok)
            assert.equals("boolean", type(value))
          end
        end
      end
    end
  end)
end)
