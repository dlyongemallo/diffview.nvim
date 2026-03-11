local vcs_utils = require("diffview.vcs.utils")

describe("diffview.vcs.utils.parse_diff", function()
  it("parses a standard unified diff", function()
    local lines = {
      "diff --git a/file.lua b/file.lua",
      "index abc1234..def5678 100644",
      "--- a/file.lua",
      "+++ b/file.lua",
      "@@ -1,3 +1,4 @@",
      " line1",
      "+added",
      " line2",
      " line3",
    }

    local result = vcs_utils.parse_diff(lines)
    assert.equals(1, #result)
    assert.equals("file.lua", result[1].path_old)
    assert.equals("file.lua", result[1].path_new)
    assert.equals(1, #result[1].hunks)
    assert.equals(1, result[1].hunks[1].old_row)
    assert.equals(3, result[1].hunks[1].old_size)
    assert.equals(1, result[1].hunks[1].new_row)
    assert.equals(4, result[1].hunks[1].new_size)
  end)

  it("parses multiple files in a single patch", function()
    local lines = {
      "diff --git a/a.lua b/a.lua",
      "--- a/a.lua",
      "+++ b/a.lua",
      "@@ -1,1 +1,2 @@",
      " existing",
      "+new",
      "diff --git a/b.lua b/b.lua",
      "--- a/b.lua",
      "+++ b/b.lua",
      "@@ -1,2 +1,1 @@",
      " keep",
      "-removed",
    }

    local result = vcs_utils.parse_diff(lines)
    assert.equals(2, #result)
    assert.equals("a.lua", result[1].path_new)
    assert.equals("b.lua", result[2].path_new)
  end)

  it("parses a rename with similarity", function()
    local lines = {
      "diff --git a/old.lua b/new.lua",
      "similarity index 95%",
      "rename from old.lua",
      "rename to new.lua",
      "--- a/old.lua",
      "+++ b/new.lua",
      "@@ -1,1 +1,1 @@",
      "-old content",
      "+new content",
    }

    local result = vcs_utils.parse_diff(lines)
    assert.equals(1, #result)
    assert.is_true(result[1].renamed)
    assert.equals("old.lua", result[1].path_old)
    assert.equals("new.lua", result[1].path_new)
    assert.equals(95, result[1].similarity)
  end)

  it("parses a new file", function()
    local lines = {
      "diff --git a/new.lua b/new.lua",
      "new file mode 100644",
      "index 0000000..abc1234",
      "--- /dev/null",
      "+++ b/new.lua",
      "@@ -0,0 +1,2 @@",
      "+line1",
      "+line2",
    }

    local result = vcs_utils.parse_diff(lines)
    assert.equals(1, #result)
    assert.is_nil(result[1].path_old)
    assert.equals("new.lua", result[1].path_new)
  end)

  it("parses a combined diff (--cc header)", function()
    local lines = {
      "diff --cc file.lua",
      "index abc1234,def5678..aef9012",
      "--- a/file.lua",
      "--- b/file.lua",
      "+++ b/file.lua",
      "@@ -1,3 -1,3 +1,4 @@",
      "  common line",
      "+ added by merge",
      "  another common",
      "  final line",
    }

    local result = vcs_utils.parse_diff(lines)
    assert.equals(1, #result)
    assert.equals("file.lua", result[1].path_old)
    assert.equals("file.lua", result[1].path_new)
    assert.equals(1, #result[1].hunks)
  end)

  it("parses a combined diff (--combined header)", function()
    local lines = {
      "diff --combined file.lua",
      "index abc1234,def5678..aef9012",
      "--- a/file.lua",
      "--- b/file.lua",
      "+++ b/file.lua",
      "@@ -1,2 -1,2 +1,3 @@",
      "  existing",
      "+ new line",
      "  end",
    }

    local result = vcs_utils.parse_diff(lines)
    assert.equals(1, #result)
    assert.equals("file.lua", result[1].path_new)
  end)

  it("parses a deleted file", function()
    local lines = {
      "diff --git a/gone.lua b/gone.lua",
      "deleted file mode 100644",
      "index abc1234..0000000",
      "--- a/gone.lua",
      "+++ /dev/null",
      "@@ -1,2 +0,0 @@",
      "-line1",
      "-line2",
    }

    local result = vcs_utils.parse_diff(lines)
    assert.equals(1, #result)
    assert.equals("gone.lua", result[1].path_old)
    assert.is_nil(result[1].path_new)
  end)

  it("handles combined diff index with comma-separated hashes", function()
    local lines = {
      "diff --cc file.lua",
      "index abc1234,def5678..aef9012 100644",
      "--- a/file.lua",
      "+++ b/file.lua",
      "@@ -1,1 -1,1 +1,1 @@",
      " line",
    }

    local result = vcs_utils.parse_diff(lines)
    assert.equals(1, #result)
    assert.equals("abc1234,def5678", result[1].index_old)
    assert.equals("aef9012", result[1].index_new)
    assert.equals("100644", result[1].mode)
  end)
end)
