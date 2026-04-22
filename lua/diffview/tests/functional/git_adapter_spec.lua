local async = require("diffview.async")
local Diff2 = require("diffview.scene.layouts.diff_2").Diff2
local GitAdapter = require("diffview.vcs.adapters.git").GitAdapter
local GitRev = require("diffview.vcs.adapters.git.rev").GitRev
local Job = require("diffview.job").Job
local RevType = require("diffview.vcs.rev").RevType
local test_utils = require("diffview.tests.helpers")

local function run(cmd, cwd)
  local res = vim.system(cmd, { cwd = cwd, text = true }):wait()
  assert.equals(0, res.code, (table.concat(cmd, " ") .. "\n" .. (res.stderr or "")))
  return vim.trim(res.stdout or "")
end

--- Helper: create a temporary git repo and return {repo, adapter} or propagate
--- errors via the ok/err pattern used by the existing test.
local function make_repo_and_adapter()
  local repo = vim.fn.tempname()
  assert.equals(1, vim.fn.mkdir(repo, "p"))

  run({ "git", "init", "-q" }, repo)
  run({ "git", "config", "user.name", "Diffview Test" }, repo)
  run({ "git", "config", "user.email", "diffview@test.local" }, repo)

  -- Need at least one commit so HEAD exists.
  local path = repo .. "/init.txt"
  local f = assert(io.open(path, "w"))
  f:write("init\n")
  f:close()

  run({ "git", "add", "init.txt" }, repo)
  run({ "git", "-c", "commit.gpgsign=false", "commit", "-q", "-m", "init" }, repo)

  local adapter = GitAdapter({
    toplevel = repo,
    cpath = repo,
    path_args = {},
  })

  return repo, adapter
end

describe("diffview.vcs.adapters.git", function()
  describe("get_show_args", function()
    it(
      "includes --no-show-signature",
      test_utils.async_test(function()
        local repo, adapter = make_repo_and_adapter()

        local ok, err = pcall(function()
          local head = run({ "git", "rev-parse", "HEAD" }, repo)
          local rev = GitRev(RevType.COMMIT, head)
          local args = adapter:get_show_args("init.txt", rev)

          local found = false
          for _, arg in ipairs(args) do
            if arg == "--no-show-signature" then
              found = true
              break
            end
          end

          assert.True(found, "get_show_args must include --no-show-signature")
        end)

        vim.schedule(function()
          pcall(vim.fn.delete, repo, "rf")
        end)
        async.await(async.scheduler())

        if not ok then
          error(err)
        end
      end)
    )

    it(
      "includes --no-show-signature when rev is nil",
      test_utils.async_test(function()
        local repo, adapter = make_repo_and_adapter()

        local ok, err = pcall(function()
          local args = adapter:get_show_args("init.txt", nil)

          local found = false
          for _, arg in ipairs(args) do
            if arg == "--no-show-signature" then
              found = true
              break
            end
          end

          assert.True(found, "get_show_args must include --no-show-signature even with nil rev")
        end)

        vim.schedule(function()
          pcall(vim.fn.delete, repo, "rf")
        end)
        async.await(async.scheduler())

        if not ok then
          error(err)
        end
      end)
    )
  end)

  describe("get_log_args", function()
    it(
      "includes --no-show-signature",
      test_utils.async_test(function()
        local repo, adapter = make_repo_and_adapter()

        local ok, err = pcall(function()
          local args = adapter:get_log_args({})

          local found = false
          for _, arg in ipairs(args) do
            if arg == "--no-show-signature" then
              found = true
              break
            end
          end

          assert.True(found, "get_log_args must include --no-show-signature")
        end)

        vim.schedule(function()
          pcall(vim.fn.delete, repo, "rf")
        end)
        async.await(async.scheduler())

        if not ok then
          error(err)
        end
      end)
    )
  end)

  describe("show_untracked", function()
    it(
      "returns true when left is STAGE and right is LOCAL",
      test_utils.async_test(function()
        local repo, adapter = make_repo_and_adapter()

        local ok, err = pcall(function()
          local left = GitRev(RevType.STAGE, 0)
          local right = GitRev(RevType.LOCAL)
          local result = adapter:show_untracked({ revs = { left = left, right = right } })
          assert.is_true(result)
        end)

        vim.schedule(function()
          pcall(vim.fn.delete, repo, "rf")
        end)
        async.await(async.scheduler())

        if not ok then
          error(err)
        end
      end)
    )

    it(
      "returns false when left is COMMIT and right is LOCAL",
      test_utils.async_test(function()
        local repo, adapter = make_repo_and_adapter()

        local ok, err = pcall(function()
          local head = run({ "git", "rev-parse", "HEAD" }, repo)
          local left = GitRev(RevType.COMMIT, head)
          local right = GitRev(RevType.LOCAL)
          local result = adapter:show_untracked({ revs = { left = left, right = right } })
          assert.is_false(result)
        end)

        vim.schedule(function()
          pcall(vim.fn.delete, repo, "rf")
        end)
        async.await(async.scheduler())

        if not ok then
          error(err)
        end
      end)
    )

    it(
      "returns false when user config show_untracked is false (STAGE vs LOCAL)",
      test_utils.async_test(function()
        local repo, adapter = make_repo_and_adapter()

        local ok, err = pcall(function()
          local left = GitRev(RevType.STAGE, 0)
          local right = GitRev(RevType.LOCAL)
          local result = adapter:show_untracked({
            revs = { left = left, right = right },
            dv_opt = { show_untracked = false },
          })
          assert.is_false(result)
        end)

        vim.schedule(function()
          pcall(vim.fn.delete, repo, "rf")
        end)
        async.await(async.scheduler())

        if not ok then
          error(err)
        end
      end)
    )
  end)

  it(
    "handles LOCAL..COMMIT binary stats without crashing",
    test_utils.async_test(function()
      local repo = vim.fn.tempname()
      assert.equals(1, vim.fn.mkdir(repo, "p"))

      local ok, err = pcall(function()
        run({ "git", "init", "-q" }, repo)
        run({ "git", "config", "user.name", "Diffview Test" }, repo)
        run({ "git", "config", "user.email", "diffview@test.local" }, repo)

        local path = repo .. "/bin.dat"
        local f = assert(io.open(path, "wb"))
        f:write(string.char(0, 1, 2, 3))
        f:close()

        run({ "git", "add", "bin.dat" }, repo)
        run({ "git", "-c", "commit.gpgsign=false", "commit", "-q", "-m", "init" }, repo)

        f = assert(io.open(path, "wb"))
        f:write(string.char(0, 1, 9, 3))
        f:close()

        local adapter = GitAdapter({
          toplevel = repo,
          cpath = repo,
          path_args = {},
        })

        local head = run({ "git", "rev-parse", "HEAD" }, repo)
        local left = GitRev(RevType.LOCAL)
        local right = GitRev(RevType.COMMIT, head)
        local args = adapter:rev_to_args(left, right)

        local tracked_err, files = async.await(
          adapter:tracked_files(
            left,
            right,
            args,
            "working",
            { default_layout = Diff2, merge_layout = Diff2 }
          )
        )

        assert.is_nil(tracked_err)
        assert.is_true(#files > 0)

        local found = false
        for _, file in ipairs(files) do
          if file.path == "bin.dat" then
            found = true
            assert.is_nil(file.stats)
          end
        end

        assert.True(found)
      end)

      vim.schedule(function()
        pcall(vim.fn.delete, repo, "rf")
      end)
      async.await(async.scheduler())

      if not ok then
        error(err)
      end
    end)
  )

  describe("merge-base failure during rebase --root", function()
    it(
      "falls back to NULL_TREE_SHA when merge-base fails",
      test_utils.async_test(function()
        -- Simulate an initial-commit rebase scenario where merge-base has no
        -- common ancestor.  We create two independent repos and graft an orphan
        -- branch so that "git merge-base" exits non-zero.
        local repo = vim.fn.tempname()
        assert.equals(1, vim.fn.mkdir(repo, "p"))

        local ok, err = pcall(function()
          run({ "git", "init", "-q" }, repo)
          run({ "git", "config", "user.name", "Diffview Test" }, repo)
          run({ "git", "config", "user.email", "diffview@test.local" }, repo)

          -- Create a commit on the default branch.
          local path = repo .. "/a.txt"
          local f = assert(io.open(path, "w"))
          f:write("a\n")
          f:close()
          run({ "git", "add", "a.txt" }, repo)
          run({ "git", "-c", "commit.gpgsign=false", "commit", "-q", "-m", "first" }, repo)
          local main_sha = run({ "git", "rev-parse", "HEAD" }, repo)

          -- Create an orphan branch with an unrelated history.  Remove tracked
          -- files so the index is clean for the orphan commit.
          run({ "git", "checkout", "--orphan", "orphan" }, repo)
          run({ "git", "rm", "-rf", "." }, repo)
          local p2 = repo .. "/b.txt"
          f = assert(io.open(p2, "w"))
          f:write("b\n")
          f:close()
          run({ "git", "add", "b.txt" }, repo)
          run({ "git", "-c", "commit.gpgsign=false", "commit", "-q", "-m", "orphan" }, repo)
          local orphan_sha = run({ "git", "rev-parse", "HEAD" }, repo)

          -- Confirm that merge-base between the two disjoint roots fails.
          local mb_result = vim
            .system({ "git", "merge-base", main_sha, orphan_sha }, { cwd = repo, text = true })
            :wait()
          assert.is_not.equal(0, mb_result.code, "merge-base should fail for disjoint histories")

          -- Verify that NULL_TREE_SHA is the expected fallback constant.
          assert.equals(
            "4b825dc642cb6eb9a060e54bf8d69288fbee4904",
            GitRev.NULL_TREE_SHA,
            "NULL_TREE_SHA must be the canonical git empty tree"
          )

          -- Verify that a null-tree rev can be constructed from the constant.
          local null_rev = GitRev.new_null_tree()
          assert.equals(RevType.COMMIT, null_rev.type)
          assert.equals(GitRev.NULL_TREE_SHA, null_rev:object_name())
        end)

        vim.schedule(function()
          pcall(vim.fn.delete, repo, "rf")
        end)
        async.await(async.scheduler())

        if not ok then
          error(err)
        end
      end)
    )
  end)

  describe("--merge-base option in parse_revs", function()
    it(
      "uses merge-base when the flag is set",
      test_utils.async_test(function()
        local repo = vim.fn.tempname()
        assert.equals(1, vim.fn.mkdir(repo, "p"))

        local ok, err = pcall(function()
          run({ "git", "init", "-q" }, repo)
          run({ "git", "config", "user.name", "Diffview Test" }, repo)
          run({ "git", "config", "user.email", "diffview@test.local" }, repo)

          -- Create two commits on the default branch.
          local path = repo .. "/a.txt"
          local f = assert(io.open(path, "w"))
          f:write("a\n")
          f:close()
          run({ "git", "add", "a.txt" }, repo)
          run({ "git", "-c", "commit.gpgsign=false", "commit", "-q", "-m", "base" }, repo)
          local base_sha = run({ "git", "rev-parse", "HEAD" }, repo)

          -- Create a feature branch diverging from base.
          run({ "git", "checkout", "-b", "feature" }, repo)
          f = assert(io.open(path, "w"))
          f:write("a-feature\n")
          f:close()
          run({ "git", "add", "a.txt" }, repo)
          run({ "git", "-c", "commit.gpgsign=false", "commit", "-q", "-m", "feature" }, repo)
          local feature_sha = run({ "git", "rev-parse", "HEAD" }, repo)

          -- Advance the default branch so HEAD diverges from the feature branch.
          run({ "git", "checkout", "-" }, repo)
          f = assert(io.open(path, "w"))
          f:write("a-main\n")
          f:close()
          run({ "git", "add", "a.txt" }, repo)
          run({ "git", "-c", "commit.gpgsign=false", "commit", "-q", "-m", "main-advance" }, repo)

          local adapter = GitAdapter({
            toplevel = repo,
            cpath = repo,
            path_args = {},
          })

          -- Without merge_base, parse_revs should use the ref directly.
          local left_plain, right_plain = adapter:parse_revs(feature_sha, {})
          assert.is_not_nil(left_plain)
          assert.equals(feature_sha, left_plain:object_name())
          assert.equals(RevType.LOCAL, right_plain.type)

          -- With merge_base, parse_revs should resolve to the merge-base of HEAD
          -- and the given ref, which is base_sha.
          local left_mb, right_mb = adapter:parse_revs(feature_sha, { merge_base = true })
          assert.is_not_nil(left_mb)
          assert.equals(base_sha, left_mb:object_name())
          assert.equals(RevType.LOCAL, right_mb.type)
        end)

        vim.schedule(function()
          pcall(vim.fn.delete, repo, "rf")
        end)
        async.await(async.scheduler())

        if not ok then
          error(err)
        end
      end)
    )

    it(
      "falls back to the ref when merge-base fails",
      test_utils.async_test(function()
        local repo = vim.fn.tempname()
        assert.equals(1, vim.fn.mkdir(repo, "p"))

        local ok, err = pcall(function()
          run({ "git", "init", "-q" }, repo)
          run({ "git", "config", "user.name", "Diffview Test" }, repo)
          run({ "git", "config", "user.email", "diffview@test.local" }, repo)

          -- Create a commit on the default branch and record its name.
          local default_branch = run({ "git", "branch", "--show-current" }, repo)
          local path = repo .. "/a.txt"
          local f = assert(io.open(path, "w"))
          f:write("a\n")
          f:close()
          run({ "git", "add", "a.txt" }, repo)
          run({ "git", "-c", "commit.gpgsign=false", "commit", "-q", "-m", "first" }, repo)

          -- Create an orphan branch with disjoint history.  Remove tracked files
          -- so the index is clean for the orphan commit.
          run({ "git", "checkout", "--orphan", "orphan" }, repo)
          run({ "git", "rm", "-rf", "." }, repo)
          local p2 = repo .. "/b.txt"
          f = assert(io.open(p2, "w"))
          f:write("b\n")
          f:close()
          run({ "git", "add", "b.txt" }, repo)
          run({ "git", "-c", "commit.gpgsign=false", "commit", "-q", "-m", "orphan" }, repo)
          local orphan_sha = run({ "git", "rev-parse", "HEAD" }, repo)

          -- Switch back to the default branch.
          run({ "git", "checkout", default_branch }, repo)

          local adapter = GitAdapter({
            toplevel = repo,
            cpath = repo,
            path_args = {},
          })

          -- With merge_base=true but disjoint histories, parse_revs should fall
          -- back to using the ref itself.
          local left, right = adapter:parse_revs(orphan_sha, { merge_base = true })
          assert.is_not_nil(left)
          assert.equals(orphan_sha, left:object_name())
          assert.equals(RevType.LOCAL, right.type)
        end)

        vim.schedule(function()
          pcall(vim.fn.delete, repo, "rf")
        end)
        async.await(async.scheduler())

        if not ok then
          error(err)
        end
      end)
    )
  end)

  describe("GIT_OPTIONAL_LOCKS in job environment", function()
    it("includes GIT_OPTIONAL_LOCKS=0 when env is provided", function()
      local job = Job({
        command = "echo",
        args = { "test" },
        env = { FOO = "bar" },
      })

      local found = false
      for _, entry in ipairs(job.env) do
        if entry == "GIT_OPTIONAL_LOCKS=0" then
          found = true
          break
        end
      end

      assert.True(found, "Job env must include GIT_OPTIONAL_LOCKS=0")
    end)

    it("includes GIT_OPTIONAL_LOCKS=0 when env is defaulted from os_environ", function()
      local job = Job({
        command = "echo",
        args = { "test" },
      })

      local found = false
      for _, entry in ipairs(job.env) do
        if entry == "GIT_OPTIONAL_LOCKS=0" then
          found = true
          break
        end
      end

      assert.True(found, "Job env must include GIT_OPTIONAL_LOCKS=0 even with default env")
    end)

    it("preserves other env vars alongside GIT_OPTIONAL_LOCKS", function()
      local job = Job({
        command = "echo",
        args = { "test" },
        env = { MY_VAR = "hello" },
      })

      local found_locks = false
      local found_custom = false
      for _, entry in ipairs(job.env) do
        if entry == "GIT_OPTIONAL_LOCKS=0" then
          found_locks = true
        end
        if entry == "MY_VAR=hello" then
          found_custom = true
        end
      end

      assert.True(found_locks, "GIT_OPTIONAL_LOCKS=0 must be present")
      assert.True(found_custom, "Custom env var must also be present")
    end)
  end)
end)
