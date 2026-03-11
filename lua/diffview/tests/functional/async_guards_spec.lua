local async = require("diffview.async")
local control = require("diffview.control")
local debounce = require("diffview.debounce")
local test_utils = require("diffview.tests.helpers")

local await = async.await
local Signal = control.Signal

describe("diffview.async guards", function()
  describe("Signal", function()
    it("starts in un-emitted state", function()
      local signal = Signal("test")
      assert.is_false(signal:check())
    end)

    it("reports emitted after send", function()
      local signal = Signal("test")
      signal:send()
      assert.is_true(signal:check())
    end)

    it("can be reset and re-sent", function()
      local signal = Signal("test")
      signal:send()
      assert.is_true(signal:check())

      signal:reset()
      assert.is_false(signal:check())

      signal:send()
      assert.is_true(signal:check())
    end)

    it("invokes listeners on send", function()
      local signal = Signal("test")
      local called = false

      signal:listen(function()
        called = true
      end)

      assert.is_false(called)
      signal:send()
      assert.is_true(called)
    end)

    it("invokes listener immediately if already emitted", function()
      local signal = Signal("test")
      signal:send()

      local called = false
      signal:listen(function()
        called = true
      end)

      assert.is_true(called)
    end)

    it("does not double-send", function()
      local signal = Signal("test")
      local count = 0

      signal:listen(function()
        count = count + 1
      end)

      signal:send()
      signal:send()
      assert.equals(1, count)
    end)
  end)

  describe("closing signal guard", function()
    -- Simulates the pattern used in DiffView:update_files where a
    -- closing signal aborts an in-flight async update.

    it("aborts when closing is signalled before the update runs", test_utils.async_test(function()
      local closing = Signal("closing")
      local update_ran = false

      local update = async.void(function()
        if closing:check() then return end
        await(async.scheduler())
        if closing:check() then return end
        update_ran = true
      end)

      closing:send()
      update()
      await(async.scheduler())
      assert.is_false(update_ran)
    end))

    it("aborts when closing is signalled during the update", test_utils.async_test(function()
      local closing = Signal("closing")
      local update_reached_yield = Signal("update_reached_yield")
      local update_completed = false

      local update = async.void(function()
        if closing:check() then return end
        -- Notify the test that we have reached the yield point.
        update_reached_yield:send()
        await(async.timeout(20))
        if closing:check() then return end
        update_completed = true
      end)

      update()
      -- Wait until the update has reached its yield point.
      await(update_reached_yield)

      -- Signal closing while the update is suspended at the timeout.
      closing:send()

      -- Wait for the update's timeout to expire.
      await(async.timeout(30))
      await(async.scheduler())

      assert.is_false(update_completed)
    end))
  end)

  describe("debounce_trailing", function()
    it("collapses rapid calls into a single execution", test_utils.async_test(function()
      local call_count = 0
      local fn = debounce.debounce_trailing(10, false, function(callback)
        call_count = call_count + 1
        if callback then callback() end
      end)

      -- Fire rapidly.
      fn()
      fn()
      fn()

      -- Wait for the debounce window to close.
      await(async.timeout(50))
      await(async.scheduler())

      assert.equals(1, call_count)
    end))

    it("allows a second call after the debounce window", test_utils.async_test(function()
      local call_count = 0
      local fn = debounce.debounce_trailing(10, false, function(callback)
        call_count = call_count + 1
        if callback then callback() end
      end)

      fn()
      await(async.timeout(50))
      await(async.scheduler())

      fn()
      await(async.timeout(50))
      await(async.scheduler())

      assert.equals(2, call_count)
    end))
  end)
end)
