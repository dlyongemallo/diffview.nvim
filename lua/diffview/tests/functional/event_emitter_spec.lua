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

    -- Swap in a fresh global emitter so tests are isolated. Using
    -- before_each/after_each ensures restoration even if assertions fail.
    local orig_emitter

    before_each(function()
      orig_emitter = DiffviewGlobal.emitter
      DiffviewGlobal.emitter = EventEmitter()
    end)

    after_each(function()
      DiffviewGlobal.emitter = orig_emitter
    end)

    it("does not accumulate global emitter listeners after repeated init/close", function()
      for _ = 1, 10 do
        local view = View({ default_layout = {} })
        view:close()
      end

      eq(0, #(DiffviewGlobal.emitter:get("view_closed") or {}))
    end)

    -- Exercises the close path when local listeners are registered on the
    -- view's emitter, mirroring how DiffView/FileHistoryView register
    -- listeners via init_event_listeners().
    it("does not crash when local listeners exist during close", function()
      local call_log = {}

      local view = View({ default_layout = {} })

      -- Register listeners similar to those from diff/listeners.lua.
      view.emitter:on("tab_enter", function()
        table.insert(call_log, "tab_enter")
      end)
      view.emitter:on("tab_leave", function()
        table.insert(call_log, "tab_leave")
      end)

      view:close()

      -- After close, the local emitter should be empty.
      eq(nil, view.emitter:get("tab_enter"))
      eq(nil, view.emitter:get("tab_leave"))

      -- Emitting on a cleared emitter should be a no-op, not a crash.
      view.emitter:emit("tab_enter")
    end)

    -- Verifies that the on_any listener path (used by bootstrap.lua to
    -- forward global events via diffview.nore_emit) does not crash when
    -- view_closed is emitted during close.
    it("does not crash when global emitter has on_any listener during close", function()
      local any_events = {}
      DiffviewGlobal.emitter:on_any(function(e, args)
        table.insert(any_events, e.id)
      end)

      local view = View({ default_layout = {} })
      view:close()

      -- The on_any listener should have seen "view_closed".
      assert(vim.tbl_contains(any_events, "view_closed"),
        "on_any listener should see view_closed event")

      -- No listeners should remain on the global emitter.
      eq(0, #(DiffviewGlobal.emitter:get("view_closed") or {}))
    end)

    -- Verifies that a listener emitting another event during close does
    -- not crash (reentrant emit on a soon-to-be-cleared emitter).
    it("survives reentrant emit on local emitter during close", function()
      local inner_fired = false

      local view = View({ default_layout = {} })

      -- Register a view_closed listener on the local emitter that
      -- emits another event during the close sequence.
      view.emitter:on("view_closed", function()
        view.emitter:emit("custom_event")
      end)
      view.emitter:on("custom_event", function()
        inner_fired = true
      end)

      view:close()

      -- The nested emit should have fired before clear().
      eq(true, inner_fired)
      eq(nil, view.emitter:get("view_closed"))
      eq(nil, view.emitter:get("custom_event"))
    end)

    -- Verifies that when two views exist, closing one does not affect
    -- the other's listeners.
    it("closing one view does not remove another view's global listeners", function()
      local view_a = View({ default_layout = {} })
      local view_b = View({ default_layout = {} })

      -- Both views should have registered a view_closed wrapper.
      eq(2, #(DiffviewGlobal.emitter:get("view_closed") or {}))

      view_a:close()

      -- Only view_a's wrapper should have been removed.
      eq(1, #(DiffviewGlobal.emitter:get("view_closed") or {}))

      -- View B's wrapper should still work.
      local forwarded = false
      view_b.emitter:on("view_closed", function()
        forwarded = true
      end)
      DiffviewGlobal.emitter:emit("view_closed", view_b)
      eq(true, forwarded)

      view_b:close()
      eq(0, #(DiffviewGlobal.emitter:get("view_closed") or {}))
    end)
  end)

  -- Regression: closing a floating panel (commit log, help) must not close
  -- the entire view. The fix relies on two layers:
  --   1. Listener ordering: sub-panel listener registered last so it runs
  --      first (EventEmitter:on inserts at position 1).
  --   2. Float guard: the view's close listener skips view:close() when the
  --      focused window is a float.
  -- These tests exercise the emitter-level mechanics without needing real
  -- Neovim windows.
  describe("close event propagation with sub-panel listeners", function()
    it("sub-panel listener registered AFTER view listener stops propagation", function()
      local emitter = EventEmitter()
      local view_closed = false

      -- Simulate view close listener (registered first).
      emitter:on("close", function()
        view_closed = true
      end)

      -- Simulate sub-panel close listener (registered second, so it runs first
      -- due to LIFO insertion).
      emitter:on("close", function(e)
        e:stop_propagation()
      end)

      emitter:emit("close")
      eq(false, view_closed)
    end)

    it("sub-panel listener registered BEFORE view listener does NOT stop propagation in time", function()
      local emitter = EventEmitter()
      local view_closed = false

      -- Simulate the buggy ordering: sub-panel registered first (pushed to
      -- position 2), view listener registered second (inserted at position 1).
      emitter:on("close", function(e)
        e:stop_propagation()
      end)

      emitter:on("close", function()
        view_closed = true
      end)

      emitter:emit("close")

      -- The view listener ran first because it was at position 1; stop_propagation
      -- came too late. This is the original bug.
      eq(true, view_closed)
    end)
  end)
end)
