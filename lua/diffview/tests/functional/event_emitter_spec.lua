local helpers = require("diffview.tests.helpers")

local eq = helpers.eq

describe("diffview.events", function()
  local EventEmitter = require("diffview.events").EventEmitter

  describe("EventEmitter", function()
    it("accumulates listeners when they are not unsubscribed", function()
      local emitter = EventEmitter()

      for _ = 1, 5 do
        emitter:on("test_event", function() end)
      end

      eq(5, #emitter:get("test_event"))
    end)

    it("removes a listener via off()", function()
      local emitter = EventEmitter()
      local cb = function() end

      emitter:on("test_event", cb)
      eq(1, #emitter:get("test_event"))

      emitter:off(cb, "test_event")
      eq(0, #(emitter:get("test_event") or {}))
    end)

    it("clears all listeners for a specific event", function()
      local emitter = EventEmitter()

      emitter:on("evt_a", function() end)
      emitter:on("evt_a", function() end)
      emitter:on("evt_b", function() end)

      emitter:clear("evt_a")

      eq(nil, emitter:get("evt_a"))
      eq(1, #emitter:get("evt_b"))
    end)

    it("clears all listeners when no event is given", function()
      local emitter = EventEmitter()

      emitter:on("evt_a", function() end)
      emitter:on("evt_b", function() end)

      emitter:clear()

      eq(nil, emitter:get("evt_a"))
      eq(nil, emitter:get("evt_b"))
    end)

    -- Simulates the View lifecycle: register a closure on a long-lived emitter,
    -- then unsubscribe on close. Verifies the listener count returns to baseline.
    it("returns to baseline listener count after view-like lifecycle", function()
      local global_emitter = EventEmitter()

      local function simulate_view_lifecycle()
        local callbacks = {}

        -- Simulate View:init() -- register a closure on the global emitter.
        local cb = function() end
        callbacks["view_closed"] = cb
        global_emitter:on("view_closed", cb)

        -- Simulate View:close() -- unsubscribe all callbacks.
        for event, fn in pairs(callbacks) do
          global_emitter:off(fn, event)
        end
      end

      -- Baseline: no listeners.
      eq(0, #(global_emitter:get("view_closed") or {}))

      for _ = 1, 10 do
        simulate_view_lifecycle()
      end

      -- After 10 open/close cycles, the listener count should be zero.
      eq(0, #(global_emitter:get("view_closed") or {}))
    end)

    -- Shows that without unsubscribing, listeners accumulate -- the pre-fix behaviour.
    it("leaks listeners when callbacks are not unsubscribed", function()
      local global_emitter = EventEmitter()

      for i = 1, 10 do
        -- Simulate View:init() without the corresponding off() call.
        global_emitter:on("view_closed", function() end)
        eq(i, #global_emitter:get("view_closed"))
      end
    end)
  end)

  -- Regression test: exercises the real View init/close lifecycle to ensure
  -- global emitter listeners are properly unsubscribed on close.
  describe("View lifecycle", function()
    local View = require("diffview.scene.view").View

    it("does not accumulate global emitter listeners after repeated init/close", function()
      -- Swap in a fresh global emitter so the test is isolated.
      local orig_emitter = DiffviewGlobal.emitter
      DiffviewGlobal.emitter = EventEmitter()

      for _ = 1, 10 do
        local view = View({ default_layout = {} })
        view:close()
      end

      eq(0, #(DiffviewGlobal.emitter:get("view_closed") or {}))

      DiffviewGlobal.emitter = orig_emitter
    end)
  end)
end)
