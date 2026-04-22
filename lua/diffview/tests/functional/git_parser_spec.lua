local parser = require("diffview.vcs.adapters.git.parser")

describe("diffview.vcs.adapters.git.parser", function()
  describe("structure_stat_data", function()
    it("separates namestat and numstat lines", function()
      local data = {
        ":100644 100644 abc1234 def5678 M\tfile.lua",
        "1\t2\tfile.lua",
      }

      local namestat, numstat, data_end = parser.structure_stat_data(data)
      assert.equals(1, #namestat)
      assert.equals(1, #numstat)
      assert.equals(3, data_end)
    end)

    it("handles multiple entries", function()
      local data = {
        ":100644 100644 aaa1111 bbb2222 M\talpha.lua",
        ":100644 000000 ccc3333 0000000 D\tbeta.lua",
        "10\t5\talpha.lua",
        "-\t-\tbeta.lua",
      }

      local namestat, numstat = parser.structure_stat_data(data)
      assert.equals(2, #namestat)
      assert.equals(2, #numstat)
    end)

    it("stops at unrelated lines", function()
      local data = {
        ":100644 100644 aaa bbb M\tfile.lua",
        "1\t2\tfile.lua",
        "some other data",
        "more unrelated",
      }

      local namestat, numstat, data_end = parser.structure_stat_data(data)
      assert.equals(1, #namestat)
      assert.equals(1, #numstat)
      assert.equals(3, data_end)
    end)

    it("respects the seek parameter", function()
      local data = {
        "header line 1",
        "header line 2",
        ":100644 100644 abc def M\tfile.lua",
        "5\t3\tfile.lua",
      }

      local namestat, numstat = parser.structure_stat_data(data, 3)
      assert.equals(1, #namestat)
      assert.equals(1, #numstat)
    end)

    it("returns empty tables for empty input", function()
      local namestat, numstat, data_end = parser.structure_stat_data({})
      assert.equals(0, #namestat)
      assert.equals(0, #numstat)
      assert.equals(1, data_end)
    end)
  end)

  describe("structure_fh_data", function()
    -- The pretty format produces 8 header lines before stat data:
    -- [1] = "right_hash left_hash [merge_hash]"
    -- [2] = author
    -- [3] = epoch time
    -- [4] = "date date offset"
    -- [5] = relative date
    -- [6] = "::ref_names"
    -- [7] = "::reflog_selector"
    -- [8] = "::subject"

    local function make_stat_data(overrides)
      local defaults = {
        "abc123 def456", -- [1] right_hash left_hash
        "Test Author", -- [2] author
        "1700000000", -- [3] epoch
        "2023-11-14 12:00 +0100", -- [4] date with offset
        "2 days ago", -- [5] relative date
        "::HEAD -> main", -- [6] ref names
        "::", -- [7] reflog selector
        "::Fix a bug", -- [8] subject
      }

      if overrides then
        for k, v in pairs(overrides) do
          defaults[k] = v
        end
      end

      return defaults
    end

    it("parses commit metadata correctly", function()
      local data = make_stat_data()
      local result = parser.structure_fh_data(data)

      assert.equals("abc123", result.right_hash)
      assert.equals("def456", result.left_hash)
      assert.is_nil(result.merge_hash)
      assert.equals("Test Author", result.author)
      assert.equals(1700000000, result.time)
      assert.equals("+0100", result.time_offset)
      assert.equals("2 days ago", result.rel_date)
      assert.equals("HEAD -> main", result.ref_names)
      assert.equals("", result.reflog_selector)
      assert.equals("Fix a bug", result.subject)
      assert.is_true(result.valid)
    end)

    it("handles merge commits with three hashes", function()
      local data = make_stat_data({ [1] = "abc123 def456 merge789" })
      local result = parser.structure_fh_data(data)

      assert.equals("abc123", result.right_hash)
      assert.equals("def456", result.left_hash)
      assert.equals("merge789", result.merge_hash)
    end)

    it("handles missing left hash", function()
      local data = make_stat_data({ [1] = "abc123 " })
      local result = parser.structure_fh_data(data)

      assert.equals("abc123", result.right_hash)
      assert.is_nil(result.left_hash)
    end)

    it("includes stat data when present", function()
      local data = make_stat_data()
      -- Append namestat and numstat lines after the 8 header lines.
      data[9] = ":100644 100644 aaa bbb M\tfile.lua"
      data[10] = "3\t1\tfile.lua"

      local result = parser.structure_fh_data(data)
      assert.equals(1, #result.namestat)
      assert.equals(1, #result.numstat)
      assert.is_true(result.valid)
    end)

    it("marks data as invalid when namestat/numstat counts differ", function()
      local data = make_stat_data()
      data[9] = ":100644 100644 aaa bbb M\tfile.lua"
      -- Missing numstat line.

      local result = parser.structure_fh_data(data)
      assert.equals(1, #result.namestat)
      assert.equals(0, #result.numstat)
      assert.is_false(result.valid)
    end)
  end)

  describe("parse_namestat_entry", function()
    it("parses a simple modification", function()
      local namestat = ":100644 100644 abc1234 def5678 M\tfile.lua"
      local numstat = "10\t5\tfile.lua"

      local entry = parser.parse_namestat_entry(namestat, numstat)
      assert.equals("M", entry.status)
      assert.equals("file.lua", entry.name)
      assert.is_nil(entry.oldname)
      assert.equals(10, entry.stats.additions)
      assert.equals(5, entry.stats.deletions)
    end)

    it("parses a rename", function()
      local namestat = ":100644 100644 abc1234 def5678 R100\told/path.lua\tnew/path.lua"
      local numstat = "0\t0\told/path.lua"

      local entry = parser.parse_namestat_entry(namestat, numstat)
      assert.equals("R", entry.status)
      assert.equals("new/path.lua", entry.name)
      assert.equals("old/path.lua", entry.oldname)
    end)

    it("parses a deletion", function()
      local namestat = ":100644 000000 abc1234 0000000 D\tremoved.lua"
      local numstat = "-\t-\tremoved.lua"

      local entry = parser.parse_namestat_entry(namestat, numstat)
      assert.equals("D", entry.status)
      assert.equals("removed.lua", entry.name)
      assert.is_nil(entry.stats)
    end)

    it("parses a combined diff entry (two parents)", function()
      -- Combined diffs have double colons and extra mode/hash fields.
      local namestat = "::100644 100644 100644 abc1234 def5678 ghi9012 MM\tfile.lua"
      local numstat = "5\t2\tfile.lua"

      local entry = parser.parse_namestat_entry(namestat, numstat)
      assert.equals("MM", entry.status)
      assert.equals("file.lua", entry.name)
      assert.equals(5, entry.stats.additions)
      assert.equals(2, entry.stats.deletions)
    end)

    it("parses an addition", function()
      local namestat = ":000000 100644 0000000 abc1234 A\tnew_file.lua"
      local numstat = "42\t0\tnew_file.lua"

      local entry = parser.parse_namestat_entry(namestat, numstat)
      assert.equals("A", entry.status)
      assert.equals("new_file.lua", entry.name)
      assert.is_nil(entry.oldname)
      assert.equals(42, entry.stats.additions)
      assert.equals(0, entry.stats.deletions)
    end)
  end)
end)
