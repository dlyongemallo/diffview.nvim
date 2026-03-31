local async = require("diffview.async")
local Diff2 = require("diffview.scene.layouts.diff_2").Diff2
local GitAdapter = require("diffview.vcs.adapters.git").GitAdapter
local GitRev = require("diffview.vcs.adapters.git.rev").GitRev
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
    it("includes --no-show-signature", test_utils.async_test(function()
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

      if not ok then error(err) end
    end))

    it("includes --no-show-signature when rev is nil", test_utils.async_test(function()
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

      if not ok then error(err) end
    end))
  end)

  describe("get_log_args", function()
    it("includes --no-show-signature", test_utils.async_test(function()
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

      if not ok then error(err) end
    end))
  end)

  describe("show_untracked", function()
    it("returns true when left is STAGE and right is LOCAL", test_utils.async_test(function()
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

      if not ok then error(err) end
    end))

    it("returns false when left is COMMIT and right is LOCAL", test_utils.async_test(function()
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

      if not ok then error(err) end
    end))

    it("returns false when user config show_untracked is false (STAGE vs LOCAL)", test_utils.async_test(function()
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

      if not ok then error(err) end
    end))
  end)

  it("handles LOCAL..COMMIT binary stats without crashing", test_utils.async_test(function()
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

      local tracked_err, files = async.await(adapter:tracked_files(
        left,
        right,
        args,
        "working",
        { default_layout = Diff2, merge_layout = Diff2 }
      ))

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

    if not ok then error(err) end
  end))
end)
