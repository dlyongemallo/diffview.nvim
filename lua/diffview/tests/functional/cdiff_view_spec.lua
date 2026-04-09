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

--- Remove a temporary repo, scheduled to avoid event-loop issues.
local function cleanup_repo(repo)
  vim.schedule(function()
    pcall(vim.fn.delete, repo, "rf")
  end)
  async.await(async.scheduler())
end

--- Close a view and its tabpage.
local function close_view(view)
  if not view then
    return
  end

  if view.tabpage and api.nvim_tabpage_is_valid(view.tabpage) then
    view:close()
  end

  local lib = require("diffview.lib")
  lib.dispose_view(view)
end

--- Build a minimal file list for CDiffView.
local function make_files()
  return {
    working = {},
    staged = {},
    conflicting = {},
  }
end

-- ---------------------------------------------------------------------------
-- Tests
-- ---------------------------------------------------------------------------

describe("diffview.api.CDiffView", function()
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

  -- -----------------------------------------------------------------------
  -- Auto-registration
  -- -----------------------------------------------------------------------

  describe("auto-registration", function()
    it("registers view in lib.views on open", test_utils.async_test(function()
      local repo = make_repo()
      local view
      local lib = require("diffview.lib")

      local ok, err = pcall(function()
        view = CDiffView({
          git_root = repo,
          left = Rev(RevType.STAGE),
          right = Rev(RevType.LOCAL),
          files = make_files(),
          update_files = function() return make_files() end,
          get_file_data = function() return {} end,
        })

        -- Not registered before open.
        assert.is_false(vim.tbl_contains(lib.views, view))

        view:open()

        -- Registered after open.
        assert.is_true(vim.tbl_contains(lib.views, view))
      end)

      close_view(view)
      cleanup_repo(repo)
      if not ok then error(err) end
    end))

    it("does not double-register when add_view is called before open", test_utils.async_test(function()
      local repo = make_repo()
      local view
      local lib = require("diffview.lib")

      local ok, err = pcall(function()
        view = CDiffView({
          git_root = repo,
          left = Rev(RevType.STAGE),
          right = Rev(RevType.LOCAL),
          files = make_files(),
          update_files = function() return make_files() end,
          get_file_data = function() return {} end,
        })

        -- Simulate old-style manual registration before open.
        lib.add_view(view)
        local count_before = 0
        for _, v in ipairs(lib.views) do
          if v == view then count_before = count_before + 1 end
        end
        eq(1, count_before)

        view:open()

        -- Should still only appear once.
        local count_after = 0
        for _, v in ipairs(lib.views) do
          if v == view then count_after = count_after + 1 end
        end
        eq(1, count_after)
      end)

      close_view(view)
      cleanup_repo(repo)
      if not ok then error(err) end
    end))
  end)
end)
