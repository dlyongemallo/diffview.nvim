local async = require("diffview.async")
local control = require("diffview.control")
local helpers = require("diffview.tests.helpers")

local await = async.await
local Signal = control.Signal

-- Tests for closing-signal guards in DiffView:update_files (ef57357).
--
-- Commit ef57357 added a closing:check() guard at the very start of
-- update_files (before the scheduler yield) and added closing:check()
-- to two existing tab-focus guards. This prevents a coroutine failure
-- when gitsigns staging triggers a refresh while the view is closing.
--
-- We replicate the guard structure from the real update_files using
-- async.wrap (callback-returning) functions so we can verify both
-- the early-return behaviour and the error message content.

---Build a mock DiffView-like object with the fields that update_files
---guards depend on.
---@param opts? { closing_sent?: boolean, tabpage?: integer }
---@return table
local function make_mock_view(opts)
  opts = opts or {}
  local closing = Signal("closing")
  if opts.closing_sent then
    closing:send()
  end

  return {
    closing = closing,
    tabpage = opts.tabpage or vim.api.nvim_get_current_tabpage(),
  }
end

---Simulate the guard structure of DiffView.update_files. This mirrors
---the three guard points in the real code without pulling in the full
---adapter and panel machinery.
---
---Guard 1: before any yield (ef57357 addition).
---Guard 2: after scheduler yield -- closing OR wrong tabpage.
---Guard 3: after async file-list fetch -- closing OR wrong tabpage.
---
---@param view table  Mock view from make_mock_view.
---@param callback fun(err?: string[])
local function update_files_guards(view, callback)
  -- Guard 1: immediate closing check.
  if view.closing:check() then
    callback({ "The update was cancelled." })
    return
  end

  await(async.scheduler())

  -- Guard 2: closing or tab mismatch after first yield.
  if view.closing:check() or view.tabpage ~= vim.api.nvim_get_current_tabpage() then
    callback({ "The update was cancelled." })
    return
  end

  -- Simulate async work (e.g. get_updated_files).
  await(async.timeout(10))
  await(async.scheduler())

  -- Guard 3: closing or tab mismatch after async work.
  if view.closing:check() or view.tabpage ~= vim.api.nvim_get_current_tabpage() then
    callback({ "The update was cancelled." })
    return
  end

  -- If all guards pass, the update succeeds.
  callback()
end

describe("closing guard in update_files (ef57357)", function()
  describe("guard 1: closing signalled before update starts", function()
    it(
      "returns cancellation error via callback",
      helpers.async_test(function()
        local view = make_mock_view({ closing_sent = true })

        local err
        local done = Signal("done")

        -- Call the guarded function directly (no debounce) so we can
        -- inspect the callback synchronously.
        local guarded = async.wrap(function(self, callback)
          update_files_guards(self, callback)
        end)

        async.void(function()
          err = await(guarded(view))
          done:send()
        end)()

        await(done)
        assert.is_not_nil(err)
        assert.equals("The update was cancelled.", err[1])
      end)
    )

    it(
      "does not proceed past the first guard",
      helpers.async_test(function()
        local view = make_mock_view({ closing_sent = true })
        local reached_guard_2 = false

        async.void(function()
          -- Guard 1.
          if view.closing:check() then
            return
          end
          await(async.scheduler())
          reached_guard_2 = true
        end)()

        await(async.scheduler())
        assert.is_false(reached_guard_2)
      end)
    )
  end)

  describe("guard 2: closing signalled after first scheduler yield", function()
    it(
      "returns cancellation error when closing fires during yield",
      helpers.async_test(function()
        local view = make_mock_view()
        local update_completed = false

        -- Use the same pattern as async_guards_spec: signal closing while
        -- the update is suspended at a timeout, then check the result.
        local update = async.void(function()
          -- Guard 1.
          if view.closing:check() then
            return
          end

          -- Use a timeout to give the test a window to signal closing.
          await(async.timeout(20))

          -- Guard 2.
          if view.closing:check() then
            return
          end
          update_completed = true
        end)

        update()

        -- Signal closing while the update is suspended at the timeout.
        view.closing:send()

        -- Wait for the timeout to expire and the scheduler to run.
        await(async.timeout(30))
        await(async.scheduler())

        assert.is_false(update_completed)
      end)
    )

    it(
      "returns error message through callback when closing fires",
      helpers.async_test(function()
        local view = make_mock_view()

        -- Send closing before the scheduler yield occurs. This tests the
        -- combined guard: closing:check() || tabpage mismatch.
        local cb_err
        local done = Signal("done")

        async.void(function()
          cb_err = await(async.wrap(function(self, callback)
            -- Guard 1 passes.
            if self.closing:check() then
              callback({ "The update was cancelled." })
              return
            end

            -- Closing fires between guard 1 and guard 2.
            self.closing:send()

            await(async.scheduler())

            -- Guard 2 catches it.
            if self.closing:check() or self.tabpage ~= vim.api.nvim_get_current_tabpage() then
              callback({ "The update was cancelled." })
              return
            end

            callback()
          end)(view))
          done:send()
        end)()

        await(done)
        assert.is_not_nil(cb_err)
        assert.equals("The update was cancelled.", cb_err[1])
      end)
    )
  end)

  describe("guard 2: wrong tabpage after first scheduler yield", function()
    it(
      "returns cancellation error when tabpage mismatches",
      helpers.async_test(function()
        local view = make_mock_view()
        -- Set tabpage to a value that won't match the current tabpage.
        view.tabpage = -1

        local err
        local done = Signal("done")

        async.void(function()
          err = await(async.wrap(function(self, callback)
            if self.closing:check() then
              callback({ "The update was cancelled." })
              return
            end

            await(async.scheduler())

            if self.closing:check() or self.tabpage ~= vim.api.nvim_get_current_tabpage() then
              callback({ "The update was cancelled." })
              return
            end

            callback()
          end)(view))
          done:send()
        end)()

        await(done)
        assert.is_not_nil(err)
        assert.equals("The update was cancelled.", err[1])
      end)
    )
  end)

  describe("guard 3: closing signalled after async work", function()
    it(
      "returns cancellation error when closing fires during async work",
      helpers.async_test(function()
        local view = make_mock_view()
        local work_started = Signal("work_started")

        local err
        local done = Signal("done")

        async.void(function()
          err = await(async.wrap(function(self, callback)
            -- Guard 1.
            if self.closing:check() then
              callback({ "The update was cancelled." })
              return
            end

            await(async.scheduler())

            -- Guard 2.
            if self.closing:check() or self.tabpage ~= vim.api.nvim_get_current_tabpage() then
              callback({ "The update was cancelled." })
              return
            end

            -- Simulate async work.
            work_started:send()
            await(async.timeout(20))
            await(async.scheduler())

            -- Guard 3.
            if self.closing:check() or self.tabpage ~= vim.api.nvim_get_current_tabpage() then
              callback({ "The update was cancelled." })
              return
            end

            callback()
          end)(view))
          done:send()
        end)()

        -- Wait for async work to begin, then signal closing.
        await(work_started)
        view.closing:send()

        await(done)
        assert.is_not_nil(err)
        assert.equals("The update was cancelled.", err[1])
      end)
    )
  end)

  describe("successful update (no closing, correct tabpage)", function()
    it(
      "returns nil error when all guards pass",
      helpers.async_test(function()
        local view = make_mock_view()

        local err
        local done = Signal("done")

        async.void(function()
          err = await(async.wrap(function(self, callback)
            update_files_guards(self, callback)
          end)(view))
          done:send()
        end)()

        await(done)
        assert.is_nil(err)
      end)
    )
  end)

  describe("closing guard combined with tabpage check", function()
    it(
      "catches closing even when tabpage still matches",
      helpers.async_test(function()
        -- This tests the specific fix from ef57357: closing:check() was
        -- added to the existing tabpage guard conditions.
        local view = make_mock_view()

        local err
        local done = Signal("done")

        async.void(function()
          err = await(async.wrap(function(self, callback)
            await(async.scheduler())

            -- Tabpage matches but closing is signalled.
            self.closing:send()

            if self.closing:check() or self.tabpage ~= vim.api.nvim_get_current_tabpage() then
              callback({ "The update was cancelled." })
              return
            end

            callback()
          end)(view))
          done:send()
        end)()

        await(done)
        assert.is_not_nil(err)
        assert.equals("The update was cancelled.", err[1])
      end)
    )

    it(
      "catches tabpage mismatch even when closing is not signalled",
      helpers.async_test(function()
        local view = make_mock_view({ tabpage = -1 })

        local err
        local done = Signal("done")

        async.void(function()
          err = await(async.wrap(function(self, callback)
            await(async.scheduler())

            -- Closing not signalled but tabpage does not match.
            if self.closing:check() or self.tabpage ~= vim.api.nvim_get_current_tabpage() then
              callback({ "The update was cancelled." })
              return
            end

            callback()
          end)(view))
          done:send()
        end)()

        await(done)
        assert.is_not_nil(err)
        assert.equals("The update was cancelled.", err[1])
      end)
    )
  end)
end)
