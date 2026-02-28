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

    -- Exercises the close path when local listeners are registered on the
    -- view's emitter, mirroring how DiffView/FileHistoryView register
    -- listeners via init_event_listeners().
    it("does not crash when local listeners exist during close", function()
      local orig_emitter = DiffviewGlobal.emitter
      DiffviewGlobal.emitter = EventEmitter()

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

      DiffviewGlobal.emitter = orig_emitter
    end)

    -- Verifies that the on_any listener path (used by bootstrap.lua to
    -- forward global events via diffview.nore_emit) does not crash when
    -- view_closed is emitted during close.
    it("does not crash when global emitter has on_any listener during close", function()
      local orig_emitter = DiffviewGlobal.emitter
      DiffviewGlobal.emitter = EventEmitter()

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

      DiffviewGlobal.emitter = orig_emitter
    end)

    -- Verifies that a listener emitting another event during close does
    -- not crash (reentrant emit on a soon-to-be-cleared emitter).
    it("survives reentrant emit on local emitter during close", function()
      local orig_emitter = DiffviewGlobal.emitter
      DiffviewGlobal.emitter = EventEmitter()

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

      DiffviewGlobal.emitter = orig_emitter
    end)

    -- Verifies that when two views exist, closing one does not affect
    -- the other's listeners.
    it("closing one view does not remove another view's global listeners", function()
      local orig_emitter = DiffviewGlobal.emitter
      DiffviewGlobal.emitter = EventEmitter()

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

      DiffviewGlobal.emitter = orig_emitter
    end)
  end)
end)
