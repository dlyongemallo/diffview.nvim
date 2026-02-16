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

describe("diffview.vcs.adapters.git", function()
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
