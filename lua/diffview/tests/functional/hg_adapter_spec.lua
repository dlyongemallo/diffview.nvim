local async = require("diffview.async")
local Diff2 = require("diffview.scene.layouts.diff_2").Diff2
local HgAdapter = require("diffview.vcs.adapters.hg").HgAdapter
local RevType = require("diffview.vcs.rev").RevType
local helpers = require("diffview.tests.helpers")

local await = async.await
local eq = helpers.eq

local function run(cmd, cwd)
  local res = vim.system(cmd, { cwd = cwd, text = true }):wait()
  assert.equals(0, res.code, (table.concat(cmd, " ") .. "\n" .. (res.stderr or "")))
  return vim.trim(res.stdout or "")
end

local function hg_available()
  return vim.fn.executable("hg") == 1
end

local function create_hg_repo()
  local repo = vim.fn.tempname()
  vim.fn.mkdir(repo, "p")

  run({ "hg", "init" }, repo)

  return {
    dir = repo,
    hg = function(args)
      local cmd = { "hg" }
      vim.list_extend(cmd, args)
      return run(cmd, repo)
    end,
    write = function(relpath, content)
      local dir = vim.fn.fnamemodify(repo .. "/" .. relpath, ":h")
      vim.fn.mkdir(dir, "p")
      local f = assert(io.open(repo .. "/" .. relpath, "w"))
      f:write(content)
      f:close()
    end,
    adapter = function()
      HgAdapter.bootstrap.done = true
      HgAdapter.bootstrap.ok = true
      return HgAdapter({
        toplevel = repo,
        path_args = {},
      })
    end,
    cleanup = function()
      pcall(vim.fn.delete, repo, "rf")
    end,
  }
end

describe("diffview.vcs.adapters.hg", function()
  -- ------------------------------------------------------------------
  -- Unit tests (no Mercurial installation needed)
  -- ------------------------------------------------------------------
  describe("HgRev", function()
    local HgRev = require("diffview.vcs.adapters.hg.rev").HgRev

    it("object_name returns the commit hash for COMMIT revs", function()
      local rev = HgRev(RevType.COMMIT, "abc123")
      eq("abc123", rev:object_name())
    end)

    it("new_null_tree creates a null rev", function()
      local rev = HgRev.new_null_tree()
      eq(HgRev.NULL_TREE_SHA, rev:object_name())
    end)
  end)

  describe("get_show_args", function()
    it("uses --rev flag to separate revision from path", function()
      local adapter = HgAdapter({ toplevel = "/tmp", path_args = {} })
      local HgRev = require("diffview.vcs.adapters.hg.rev").HgRev
      local rev = HgRev(RevType.COMMIT, "abc123")
      local args = adapter:get_show_args("src/main.lua", rev)

      -- Should produce: { "cat", "--rev", "abc123", "--", "src/main.lua" }
      assert.is_true(vim.tbl_contains(args, "cat"))
      assert.is_true(vim.tbl_contains(args, "--rev"))
      assert.is_true(vim.tbl_contains(args, "abc123"))
      assert.is_true(vim.tbl_contains(args, "src/main.lua"))

      -- The path must not have a revision appended to it.
      for _, arg in ipairs(args) do
        if arg == "src/main.lua" then
          assert.is_nil(arg:match("#"), "path should not contain revision specifier")
        end
      end
    end)
  end)

  -- ------------------------------------------------------------------
  -- Integration tests: require hg
  -- ------------------------------------------------------------------
  describe("tracked_files", function()
    local repo

    before_each(function()
      if not hg_available() then
        pending("hg not installed")
        return
      end
      repo = create_hg_repo()
    end)

    after_each(function()
      if repo then
        repo.cleanup()
      end
    end)

    it(
      "lists modified, added, and removed files",
      helpers.async_test(function()
        if not hg_available() then
          pending("hg not installed")
          return
        end

        -- Initial commit.
        repo.write("src/main.lua", 'print("v1")\n')
        repo.write("src/utils.lua", "local M = {}\nreturn M\n")
        repo.hg({ "add", "src/main.lua", "src/utils.lua" })
        repo.hg({ "commit", "-m", "initial", "-u", "test <test@test.com>" })

        -- Working copy changes: modify, remove, add.
        repo.write("src/main.lua", 'print("v2")\n')
        repo.hg({ "remove", "src/utils.lua" })
        repo.write("src/new.lua", "new\n")
        repo.hg({ "add", "src/new.lua" })

        local adapter = repo.adapter()
        local HgRev = adapter.Rev
        local left = HgRev(RevType.COMMIT, "tip")
        local right = HgRev(RevType.LOCAL)

        local err, files = await(
          adapter:tracked_files(
            left,
            right,
            {},
            "working",
            { default_layout = Diff2, merge_layout = Diff2 }
          )
        )

        assert.is_nil(err)

        local by_name = {}
        for _, file in ipairs(files) do
          local name = file.path:match("[^/]+$")
          by_name[name] = file
        end

        assert.is_not_nil(by_name["main.lua"], "main.lua should appear (modified)")
        assert.equals("M", by_name["main.lua"].status)

        assert.is_not_nil(by_name["new.lua"], "new.lua should appear (added)")
        assert.equals("A", by_name["new.lua"].status)

        assert.is_not_nil(by_name["utils.lua"], "utils.lua should appear (removed)")
        assert.equals("R", by_name["utils.lua"].status)
      end)
    )

    it(
      "shows file content at a revision without errors",
      helpers.async_test(function()
        if not hg_available() then
          pending("hg not installed")
          return
        end

        repo.write("hello.txt", "hello world\n")
        repo.hg({ "add", "hello.txt" })
        repo.hg({ "commit", "-m", "add hello", "-u", "test <test@test.com>" })

        local adapter = repo.adapter()
        local HgRev = adapter.Rev
        local rev = HgRev(RevType.COMMIT, "tip")

        local err, content = await(adapter:show("hello.txt", rev))

        assert.is_nil(err)
        assert.is_not_nil(content)
        assert.equals("hello world", vim.trim(table.concat(content, "\n")))
      end)
    )

    it(
      "paths do not contain revision specifiers",
      helpers.async_test(function()
        if not hg_available() then
          pending("hg not installed")
          return
        end

        repo.write("file.lua", "content\n")
        repo.hg({ "add", "file.lua" })
        repo.hg({ "commit", "-m", "add file", "-u", "test <test@test.com>" })
        repo.write("file.lua", "updated\n")

        local adapter = repo.adapter()
        local HgRev = adapter.Rev
        local left = HgRev(RevType.COMMIT, "tip")
        local right = HgRev(RevType.LOCAL)

        local err, files = await(
          adapter:tracked_files(
            left,
            right,
            {},
            "working",
            { default_layout = Diff2, merge_layout = Diff2 }
          )
        )

        assert.is_nil(err)
        assert.is_true(#files > 0)

        for _, file in ipairs(files) do
          -- Mercurial paths should never contain revision specifiers.
          assert.is_nil(file.path:match("#%d+"), ("path %q contains #rev"):format(file.path))
          assert.is_nil(file.path:match("@%d+"), ("path %q contains @rev"):format(file.path))
        end
      end)
    )
  end)

  describe("parse_fh_data pin_local", function()
    -- Construct an HgAdapter without invoking `hg`. parse_fh_data only
    -- shells out via state.layout_opt.default_layout, which we control,
    -- so a tempdir toplevel and stubbed bootstrap state are sufficient.
    local function make_adapter()
      local repo = vim.fn.tempname()
      vim.fn.mkdir(repo, "p")

      HgAdapter.bootstrap.done = true
      HgAdapter.bootstrap.ok = true

      return HgAdapter({ toplevel = repo, path_args = {} }), repo
    end

    -- Mercurial's parse_fh_data iterates `#numstat - 1` times, so the
    -- numstat array carries a sentinel trailing entry. Status character
    -- comes from the first character of the matching `namestat[i]`.
    local function setup_state_and_data(layout_opt)
      local state = {
        path_args = { "foo.txt" },
        log_options = {},
        prepared_log_opts = { base = nil },
        layout_opt = layout_opt,
        single_file = true,
      }

      local data = {
        left_hash = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        right_hash = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        namestat = { "M foo.txt" },
        numstat = { "foo.txt | 2 +-", "" },
      }

      local commit = {}

      return state, data, commit
    end

    it("uses commit-side rev for b when pin_local is unset", function()
      local adapter, repo = make_adapter()

      local state, data, commit = setup_state_and_data({
        default_layout = Diff2,
      })

      local success, log_entry = adapter:parse_fh_data(data, commit, state)
      assert.True(success)
      ---@cast log_entry LogEntry

      local b_rev = log_entry.files[1].layout.b.file.rev
      assert.equals(RevType.COMMIT, b_rev.type)
      assert.equals(data.right_hash, b_rev.commit)

      pcall(vim.fn.delete, repo, "rf")
    end)

    it("sets revs.b to LOCAL when state.layout_opt.pin_local is true", function()
      local adapter, repo = make_adapter()

      local state, data, commit = setup_state_and_data({
        default_layout = Diff2,
        pin_local = true,
      })

      local success, log_entry = adapter:parse_fh_data(data, commit, state)
      assert.True(success)
      ---@cast log_entry LogEntry

      local b_file = log_entry.files[1].layout.b.file
      assert.equals(RevType.LOCAL, b_file.rev.type)
      assert.equals("foo.txt", b_file.path)

      -- pin_local diffs each changeset against the working tree, so the
      -- a-side reads from this changeset (not its parent).
      local a_rev = log_entry.files[1].layout.a.file.rev
      assert.equals(RevType.COMMIT, a_rev.type)
      assert.equals(data.right_hash, a_rev.commit)

      pcall(vim.fn.delete, repo, "rf")
    end)

    it("reuses the layout_opt.pinned_b_file_for File for the b-side", function()
      local adapter, repo = make_adapter()

      -- See `git_adapter_spec`'s mirror test for the rationale: the adapter
      -- looks up the b-side `vcs.File` through the view's cache (resolved
      -- via `pinned_path` when set), so identity is preserved across every
      -- entry the view will ever build.
      local shared = { path = "shared.txt", rev = adapter.Rev(RevType.LOCAL) }
      local lookups = {}
      local state, data, commit = setup_state_and_data({
        default_layout = Diff2,
        pin_local = true,
        pinned_path = "renamed/foo.txt",
        pinned_b_file_for = function(path)
          table.insert(lookups, path)
          return shared
        end,
      })

      local success, log_entry = adapter:parse_fh_data(data, commit, state)
      assert.True(success)
      ---@cast log_entry LogEntry

      assert.equals(shared, log_entry.files[1].layout.b.file)
      assert.same({ "renamed/foo.txt" }, lookups)

      pcall(vim.fn.delete, repo, "rf")
    end)
  end)
end)
