local helpers = require("diffview.tests.helpers")
local NullAdapter = require("diffview.vcs.adapters.null").NullAdapter
local NullRev = require("diffview.vcs.adapters.null.rev").NullRev
local RevType = require("diffview.vcs.rev").RevType

local eq = helpers.eq

describe("diffview.vcs.adapters.null", function()
  describe("NullAdapter", function()
    local adapter

    before_each(function() adapter = NullAdapter.create({ toplevel = "/tmp/test" }) end)

    it("sets ctx fields from toplevel", function()
      eq("/tmp/test", adapter.ctx.toplevel)
      eq("/tmp/test", adapter.ctx.dir)
      eq({}, adapter.ctx.path_args)
    end)

    it("is_binary always returns false", function()
      local rev = NullRev(RevType.LOCAL)
      assert.False(adapter:is_binary("any/file.txt", rev))
    end)

    it("head_rev returns nil", function() assert.is_nil(adapter:head_rev()) end)

    it("file_blob_hash returns nil", function()
      assert.is_nil(adapter:file_blob_hash("any/file.txt"))
      assert.is_nil(adapter:file_blob_hash("any/file.txt", ":0"))
    end)

    it("get_command returns a no-op binary", function()
      local cmd = adapter:get_command()
      assert.is_table(cmd)
      assert.True(#cmd >= 1)
    end)

    it("rev_to_pretty_string returns nil", function()
      local left = NullRev(RevType.LOCAL)
      local right = NullRev(RevType.LOCAL)
      assert.is_nil(adapter:rev_to_pretty_string(left, right))
    end)

    it("rev_to_args returns empty table", function()
      local left = NullRev(RevType.LOCAL)
      local right = NullRev(RevType.LOCAL)
      eq({}, adapter:rev_to_args(left, right))
    end)

    it("get_merge_context returns nil", function() assert.is_nil(adapter:get_merge_context()) end)

    it("show_untracked returns false", function() assert.False(adapter:show_untracked()) end)

    it("stage_index_file returns false", function() assert.False(adapter:stage_index_file({})) end)

    it("add_files returns false", function() assert.False(adapter:add_files({ "file.txt" })) end)

    it(
      "reset_files returns false",
      function() assert.False(adapter:reset_files({ "file.txt" })) end
    )

    it("force_entry_refresh_on_noop returns false", function()
      local left = NullRev(RevType.LOCAL)
      local right = NullRev(RevType.LOCAL)
      assert.False(adapter:force_entry_refresh_on_noop(left, right))
    end)

    it("rev_candidates returns empty table", function() eq({}, adapter:rev_candidates("")) end)

    it(
      "get_show_args returns empty table",
      function() eq({}, adapter:get_show_args("file.txt", NullRev(RevType.LOCAL))) end
    )

    it("get_log_args returns empty table", function() eq({}, adapter:get_log_args({})) end)

    it("bootstrap succeeds", function()
      NullAdapter.run_bootstrap()
      assert.True(NullAdapter.bootstrap.done)
      assert.True(NullAdapter.bootstrap.ok)
    end)
  end)

  describe("NullRev", function()
    it("creates a LOCAL rev", function()
      local rev = NullRev(RevType.LOCAL)
      eq(RevType.LOCAL, rev.type)
      assert.False(rev.track_head)
    end)

    it("to_range returns nil", function()
      local rev = NullRev(RevType.LOCAL)
      assert.is_nil(NullRev.to_range(rev))
    end)

    it("from_name returns nil", function() assert.is_nil(NullRev.from_name("HEAD")) end)

    it("earliest_commit returns nil", function() assert.is_nil(NullRev.earliest_commit({})) end)

    it("new_null_tree returns a LOCAL rev", function()
      local rev = NullRev.new_null_tree()
      eq(RevType.LOCAL, rev.type)
    end)

    it("is_head returns false", function()
      local rev = NullRev(RevType.LOCAL)
      assert.False(rev:is_head({}))
    end)

    it("object_name returns LOCAL for LOCAL type", function()
      local rev = NullRev(RevType.LOCAL)
      eq("LOCAL", rev:object_name())
    end)

    it("__tostring returns LOCAL for LOCAL type", function()
      local rev = NullRev(RevType.LOCAL)
      eq("LOCAL", tostring(rev))
    end)
  end)
end)
