local api = vim.api
local async = require("diffview.async")
local config = require("diffview.config")
local test_utils = require("diffview.tests.helpers")
local EventEmitter = require("diffview.events").EventEmitter

local CDiffView = require("diffview.api.views.diff.diff_view").CDiffView
local Rev = require("diffview.api.views.diff.diff_view").Rev
local RevType = require("diffview.api.views.diff.diff_view").RevType

local eq = test_utils.eq

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function run(cmd, cwd)
  local res = vim.system(cmd, { cwd = cwd, text = true }):wait()
  assert.equals(0, res.code, (table.concat(cmd, " ") .. "\n" .. (res.stderr or "")))
  return vim.trim(res.stdout or "")
end

--- Create a temporary git repo with one commit.
local function make_repo()
  local repo = vim.fn.tempname()
  assert.equals(1, vim.fn.mkdir(repo, "p"))

  run({ "git", "init", "-q" }, repo)
  run({ "git", "config", "user.name", "Diffview Test" }, repo)
  run({ "git", "config", "user.email", "diffview@test.local" }, repo)

  local path = repo .. "/init.txt"
  local f = assert(io.open(path, "w"))
  f:write("init\n")
  f:close()

  run({ "git", "add", "init.txt" }, repo)
  run({ "git", "-c", "commit.gpgsign=false", "commit", "-q", "-m", "init" }, repo)

  return repo
end

local function cleanup_repo(repo)
  vim.schedule(function()
    pcall(vim.fn.delete, repo, "rf")
  end)
  async.await(async.scheduler())
end

local function close_view(view)
  if not view then return end
  if view.tabpage and api.nvim_tabpage_is_valid(view.tabpage) then
    view:close()
  end
  require("diffview.lib").dispose_view(view)
end

local function make_files()
  return { working = {}, staged = {}, conflicting = {} }
end

-- ---------------------------------------------------------------------------
-- Tests
-- ---------------------------------------------------------------------------

describe("diffview.scene.views.diff.DiffView", function()
  local orig_emitter, original_config

  before_each(function()
    orig_emitter = DiffviewGlobal.emitter
    DiffviewGlobal.emitter = EventEmitter()
    original_config = vim.deepcopy(config.get_config())
    -- Disable icons so render does not require nvim-web-devicons.
    config.get_config().use_icons = false
  end)

  after_each(function()
    DiffviewGlobal.emitter = orig_emitter
    config.setup(original_config)
  end)

  describe("update_files", function()
    -- Regression: cached/staged views (right = STAGE) used to skip the
    -- HEAD-tracking refresh, so committing while such a view stayed open
    -- left `self.left` pinned to the stale HEAD and the file diff was
    -- computed against the wrong base.
    it("refreshes left when track_head is set and HEAD moves, even when right is STAGE",
      test_utils.async_test(function()
        local repo = make_repo()
        local view

        local ok, err = pcall(function()
          local initial_head = run({ "git", "rev-parse", "HEAD" }, repo)

          view = CDiffView({
            git_root = repo,
            -- Mirror what `parse_revs(nil, {cached=true})` produces for Git:
            -- left = head_rev() with track_head=true, right = STAGE 0.
            left = Rev(RevType.COMMIT, initial_head, true),
            right = Rev(RevType.STAGE, 0),
            files = make_files(),
            update_files = function() return make_files() end,
            get_file_data = function() return {} end,
          })

          view:open()
          vim.wait(2000, function() return view.initialized end, 10)
          eq(initial_head, view.left.commit)

          -- Advance HEAD by committing a new file outside the view.
          local f = assert(io.open(repo .. "/foo.txt", "w"))
          f:write("foo\n")
          f:close()
          run({ "git", "add", "foo.txt" }, repo)
          run({ "git", "-c", "commit.gpgsign=false", "commit", "-q", "-m", "foo" }, repo)
          local new_head = run({ "git", "rev-parse", "HEAD" }, repo)
          assert.are_not.equal(initial_head, new_head)

          -- Trigger a refresh; the track_head block in update_files must
          -- pick up the new HEAD.
          view:update_files()
          vim.wait(2000, function() return view.left.commit == new_head end, 10)

          eq(new_head, view.left.commit)
        end)

        close_view(view)
        cleanup_repo(repo)
        if not ok then error(err) end
      end))
  end)
end)
