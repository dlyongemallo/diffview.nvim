local async = require("diffview.async")
local debounce = require("diffview.debounce")
local test_utils = require("diffview.tests.helpers")

local await = async.await

describe("diffview.debounce", function()
  describe("debounce_trailing", function()
    it("eventually fires the debounced function", test_utils.async_test(function()
      local fired = false
      local fn = debounce.debounce_trailing(10, false, function()
        fired = true
      end)

      fn()

      await(async.timeout(50))
      await(async.scheduler())

      assert.is_true(fired)
      fn.close()
    end))

    it("runs callback inside the main loop", test_utils.async_test(function()
      local in_fast_event = true
      local fn = debounce.debounce_trailing(10, false, function()
        in_fast_event = vim.in_fast_event()
      end)

      fn()

      await(async.timeout(50))
      await(async.scheduler())

      assert.is_false(in_fast_event)
      fn.close()
    end))

    it("cancel drops a pending trailing call", test_utils.async_test(function()
      local count = 0
      local fn = debounce.debounce_trailing(10, false, function()
        count = count + 1
      end)

      fn()
      fn.cancel()

      await(async.timeout(50))
      await(async.scheduler())

      assert.equals(0, count)
      fn.close()
    end))

    it("can be re-scheduled after cancel", test_utils.async_test(function()
      local count = 0
      local fn = debounce.debounce_trailing(10, false, function()
        count = count + 1
      end)

      fn()
      fn.cancel()

      await(async.timeout(30))
      await(async.scheduler())
      assert.equals(0, count)

      fn()

      await(async.timeout(50))
      await(async.scheduler())
      assert.equals(1, count)

      fn.close()
    end))
  end)

  describe("throttle_trailing", function()
    it("fires after the throttle interval", test_utils.async_test(function()
      local fired = false
      local fn = debounce.throttle_trailing(10, false, function()
        fired = true
      end)

      fn()

      await(async.timeout(50))
      await(async.scheduler())

      assert.is_true(fired)
      fn.close()
    end))

    it("runs callback inside the main loop", test_utils.async_test(function()
      local in_fast_event = true
      local fn = debounce.throttle_trailing(10, false, function()
        in_fast_event = vim.in_fast_event()
      end)

      fn()

      await(async.timeout(50))
      await(async.scheduler())

      assert.is_false(in_fast_event)
      fn.close()
    end))
  end)

  describe("set_timeout", function()
    it("fires callback after the delay", test_utils.async_test(function()
      local fired = false

      local handle = debounce.set_timeout(function()
        fired = true
      end, 10)

      assert.is_false(fired)

      await(async.timeout(50))
      await(async.scheduler())

      assert.is_true(fired)
      handle.close()
    end))

    it("runs callback inside the main loop", test_utils.async_test(function()
      local in_fast_event = true

      local handle = debounce.set_timeout(function()
        in_fast_event = vim.in_fast_event()
      end, 10)

      await(async.timeout(50))
      await(async.scheduler())

      assert.is_false(in_fast_event)
      handle.close()
    end))
  end)

  describe("set_interval", function()
    it("fires callback multiple times", test_utils.async_test(function()
      local count = 0

      local handle = debounce.set_interval(function()
        count = count + 1
      end, 10)

      await(async.timeout(80))
      await(async.scheduler())

      assert.is_true(count >= 2)
      handle.close()
    end))

    it("runs callback inside the main loop", test_utils.async_test(function()
      local in_fast_event = true

      local handle = debounce.set_interval(function()
        in_fast_event = vim.in_fast_event()
      end, 10)

      await(async.timeout(50))
      await(async.scheduler())

      assert.is_false(in_fast_event)
      handle.close()
    end))
  end)
end)
