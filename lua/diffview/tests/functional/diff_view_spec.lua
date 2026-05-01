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
  if not view then
    return
  end
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
    it(
      "refreshes left when track_head is set and HEAD moves, even when right is STAGE",
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
            update_files = function()
              return make_files()
            end,
            get_file_data = function()
              return {}
            end,
          })

          view:open()
          vim.wait(2000, function()
            return view.initialized
          end, 10)
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
          vim.wait(2000, function()
            return view.left.commit == new_head
          end, 10)

          eq(new_head, view.left.commit)
        end)

        close_view(view)
        cleanup_repo(repo)
        if not ok then
          error(err)
        end
      end)
    )

    -- Regression: the wrapped impl signature were changed from
    -- (self, callback) to (self, opts, callback). Legacy callers using
    -- update_files(callback) would otherwise dereference opts.force on a
    -- function and crash; the wrapper normalizes the args.
    it(
      "accepts the legacy update_files(callback) signature",
      test_utils.async_test(function()
        local repo = make_repo()
        local view

        local ok, err = pcall(function()
          view = CDiffView({
            git_root = repo,
            left = Rev(RevType.COMMIT, run({ "git", "rev-parse", "HEAD" }, repo), true),
            right = Rev(RevType.STAGE, 0),
            files = make_files(),
            update_files = function()
              return make_files()
            end,
            get_file_data = function()
              return {}
            end,
          })

          view:open()
          vim.wait(2000, function()
            return view.initialized
          end, 10)

          local cb_called = false
          view:update_files(function()
            cb_called = true
          end)
          vim.wait(2000, function()
            return cb_called
          end, 10)

          assert.is_true(cb_called)
        end)

        close_view(view)
        cleanup_repo(repo)
        if not ok then
          error(err)
        end
      end)
    )
  end)

  -- actions.refresh_files({ force = true }) re-creates the entry for files
  -- whose layout includes a STAGE-rev side, so unsaved edits in the virtual
  -- stage buffer are dropped. Entries without a STAGE side (LOCAL/COMMIT
  -- only) are left untouched, and force is a no-op without the flag. This
  -- block exercises the decision in isolation, mirroring the pattern in
  -- nil_guards_spec.lua.
  describe("force-refresh stage buffers (1ad47af)", function()
    ---Decision lifted from DiffView:update_files: should the entry be
    ---force-replaced because it includes a STAGE-rev side?
    ---@param old_file table
    ---@param opts { force?: boolean }?
    local function should_force_replace(old_file, opts)
      opts = opts or {}
      if not opts.force then
        return false
      end
      for _, f in ipairs(old_file.layout:files()) do
        if f.rev.type == RevType.STAGE then
          return true
        end
      end
      return false
    end

    ---@param rev_types table
    local function mock_entry(rev_types)
      local files = {}
      for _, t in ipairs(rev_types) do
        files[#files + 1] = { rev = { type = t } }
      end
      return {
        layout = {
          files = function()
            return files
          end,
        },
      }
    end

    it("force=true triggers replacement when a STAGE-rev side is present", function()
      local entry = mock_entry({ RevType.LOCAL, RevType.STAGE })
      eq(true, should_force_replace(entry, { force = true }))
    end)

    it("force=true is a no-op when no STAGE-rev side is present", function()
      local entry = mock_entry({ RevType.LOCAL, RevType.COMMIT })
      eq(false, should_force_replace(entry, { force = true }))
    end)

    it("force=false leaves STAGE entries alone", function()
      local entry = mock_entry({ RevType.STAGE })
      eq(false, should_force_replace(entry, { force = false }))
    end)

    it("opts=nil defaults to no replacement (default R behaviour)", function()
      local entry = mock_entry({ RevType.STAGE })
      eq(false, should_force_replace(entry, nil))
    end)
  end)

  -- Regression: EventEmitter calls listeners as `callback(event, ...)`, so
  -- the `refresh_files` listener must accept the leading event arg before
  -- `opts`; otherwise `actions.refresh_files({ force = true })` silently
  -- drops the opts table on the floor.
  describe("refresh_files listener event-arg shape", function()
    it("forwards opts (not the Event object) to view:update_files", function()
      local listeners_factory = require("diffview.scene.views.diff.listeners")

      local captured_opts
      local view_stub = {
        update_files = function(_self, opts)
          captured_opts = opts
        end,
        panel = {},
        adapter = {},
      }

      local listeners = listeners_factory(view_stub)
      local emitter = require("diffview.events").EventEmitter()
      emitter:on("refresh_files", listeners.refresh_files)

      emitter:emit("refresh_files", { force = true })

      assert.is_table(captured_opts)
      eq(true, captured_opts.force)
    end)

    it("passes nil opts through cleanly when none are emitted", function()
      local listeners_factory = require("diffview.scene.views.diff.listeners")

      local update_called = false
      local captured_opts = "untouched"
      local view_stub = {
        update_files = function(_self, opts)
          update_called = true
          captured_opts = opts
        end,
        panel = {},
        adapter = {},
      }

      local listeners = listeners_factory(view_stub)
      local emitter = require("diffview.events").EventEmitter()
      emitter:on("refresh_files", listeners.refresh_files)

      emitter:emit("refresh_files")

      assert.is_true(update_called)
      eq(nil, captured_opts)
    end)
  end)
end)
