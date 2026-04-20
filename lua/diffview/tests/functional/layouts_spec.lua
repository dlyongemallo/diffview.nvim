local Diff1 = require("diffview.scene.layouts.diff_1").Diff1
local Diff2 = require("diffview.scene.layouts.diff_2").Diff2
local Diff2Hor = require("diffview.scene.layouts.diff_2_hor").Diff2Hor
local Diff2Ver = require("diffview.scene.layouts.diff_2_ver").Diff2Ver
local Diff3 = require("diffview.scene.layouts.diff_3").Diff3
local Diff3Mixed = require("diffview.scene.layouts.diff_3_mixed").Diff3Mixed
local Diff4 = require("diffview.scene.layouts.diff_4").Diff4
local Diff4Mixed = require("diffview.scene.layouts.diff_4_mixed").Diff4Mixed
local Layout = require("diffview.scene.layout").Layout
local RevType = require("diffview.vcs.rev").RevType
local async = require("diffview.async")
local helpers = require("diffview.tests.helpers")

local eq = helpers.eq

describe("diffview.layout null detection", function()
  it("treats COMMIT-side deletions as null in window b for Diff2", function()
    local rev = { type = RevType.COMMIT }

    assert.True(Diff2.should_null(rev, "D", "b"))
    assert.False(Diff2.should_null(rev, "M", "b"))
    assert.True(Diff2.should_null(rev, "A", "a"))
  end)

  it("keeps merge stages non-null in Diff3 and Diff4", function()
    local stage2 = { type = RevType.STAGE, stage = 2 }

    assert.False(Diff3.should_null(stage2, "U", "a"))
    assert.False(Diff4.should_null(stage2, "U", "a"))
  end)

  it("handles LOCAL/COMMIT nulling consistently in Diff3 and Diff4", function()
    local local_rev = { type = RevType.LOCAL }
    local commit_rev = { type = RevType.COMMIT }

    assert.True(Diff3.should_null(local_rev, "D", "b"))
    assert.True(Diff4.should_null(local_rev, "D", "b"))
    assert.True(Diff3.should_null(commit_rev, "D", "c"))
    assert.True(Diff4.should_null(commit_rev, "D", "d"))
    assert.True(Diff3.should_null(commit_rev, "A", "a"))
    assert.True(Diff4.should_null(commit_rev, "A", "a"))
  end)
end)

describe("diffview.layout symbols", function()
  it("Diff1 declares symbols { 'b' }", function() eq({ "b" }, Diff1.symbols) end)

  it("Diff1Inline inherits Diff1 and keeps symbols { 'b' }", function()
    -- Class-level relationship check avoids relying on the constructor's
    -- handling of empty/missing init args.
    local Diff1Inline = require("diffview.scene.layouts.diff_1_inline").Diff1Inline
    eq({ "b" }, Diff1Inline.symbols)
    eq(Diff1, Diff1Inline.super_class)
  end)

  it("Diff1Inline exposes a_file via owned_files and get_file_for('a')", function()
    local Diff1Inline = require("diffview.scene.layouts.diff_1_inline").Diff1Inline

    -- Drive the methods directly on a bare instance so we don't exercise the
    -- full constructor (see other Diff1Inline tests for rationale).
    local inst = setmetatable({}, { __index = Diff1Inline })
    inst.windows = { { file = { id = "b_file" } } }
    inst.a_file = { id = "a_file" }
    inst.b = inst.windows[1]

    eq(inst.a_file, inst:get_file_for("a"))
    eq(inst.b.file, inst:get_file_for("b"))
    eq({ inst.b.file, inst.a_file }, inst:owned_files())

    inst.a_file = nil
    eq({ inst.b.file }, inst:owned_files())
    assert.is_nil(inst:get_file_for("a"))
  end)

  it("Diff1Inline:teardown_render clears inline-diff extmarks from the b buffer", function()
    local Diff1Inline = require("diffview.scene.layouts.diff_1_inline").Diff1Inline
    local inline_diff = require("diffview.scene.inline_diff")
    local api = vim.api

    local bufnr = api.nvim_create_buf(false, true)
    api.nvim_buf_set_lines(bufnr, 0, -1, false, { "added", "context" })
    inline_diff.render(bufnr, { "context" }, { "added", "context" })
    assert.is_true(#api.nvim_buf_get_extmarks(bufnr, inline_diff.ns, 0, -1, {}) > 0)

    local inst = setmetatable({}, { __index = Diff1Inline })
    inst.b = { file = { bufnr = bufnr } }
    inst:teardown_render()

    eq(0, #api.nvim_buf_get_extmarks(bufnr, inline_diff.ns, 0, -1, {}))
    pcall(api.nvim_buf_delete, bufnr, { force = true })
  end)

  it("Diff1Inline:teardown_render closes the repaint debounce", function()
    local Diff1Inline = require("diffview.scene.layouts.diff_1_inline").Diff1Inline

    local closed = false
    local debounced = setmetatable({}, {
      __call = function() end,
      __index = {
        close = function() closed = true end,
        cancel = function() end,
      },
    })

    local inst = setmetatable({}, { __index = Diff1Inline })
    inst._repaint_debounced = debounced
    inst._repaint_bufnr = nil
    inst:teardown_render()

    assert.is_true(closed)
    assert.is_nil(inst._repaint_debounced)
  end)

  it(
    "Diff1Inline InsertLeave cancels a pending debounced repaint",
    helpers.async_test(function()
      local Diff1Inline = require("diffview.scene.layouts.diff_1_inline").Diff1Inline
      local api = vim.api

      -- Shadow `_repaint` on the instance so we count calls without mutating
      -- the class method shared with concurrent tests.
      local repaint_count = 0

      local bufnr = api.nvim_create_buf(false, true)
      api.nvim_buf_set_lines(bufnr, 0, -1, false, { "new content" })
      local winid = api.nvim_get_current_win()

      local inst = setmetatable({}, { __index = Diff1Inline })
      inst.b = {
        file = { bufnr = bufnr, is_valid = function() return true end },
        is_valid = function() return true end,
        id = winid,
      }
      inst._cached_old_lines = { "old content" }
      inst._repaint = function() repaint_count = repaint_count + 1 end

      async.await(inst:_render_inline())

      -- `TextChangedI` schedules a debounced repaint; `InsertLeave` should
      -- cancel it and fire the immediate repaint exactly once.
      api.nvim_exec_autocmds("TextChangedI", { buffer = bufnr })
      api.nvim_exec_autocmds("InsertLeave", { buffer = bufnr })

      eq(1, repaint_count)

      -- Wait past the debounce window (150ms). If the debounce hadn't been
      -- cancelled, the trailing call would bump the counter to 2.
      async.await(async.timeout(200))
      async.await(async.scheduler())

      eq(1, repaint_count)

      inst:teardown_render()
      pcall(api.nvim_buf_delete, bufnr, { force = true })
    end)
  )

  it(
    "Diff1Inline TextChangedI coalesces rapid edits into one repaint",
    helpers.async_test(function()
      local Diff1Inline = require("diffview.scene.layouts.diff_1_inline").Diff1Inline
      local api = vim.api

      local repaint_count = 0

      local bufnr = api.nvim_create_buf(false, true)
      api.nvim_buf_set_lines(bufnr, 0, -1, false, { "new content" })
      local winid = api.nvim_get_current_win()

      local inst = setmetatable({}, { __index = Diff1Inline })
      inst.b = {
        file = { bufnr = bufnr, is_valid = function() return true end },
        is_valid = function() return true end,
        id = winid,
      }
      inst._cached_old_lines = { "old content" }
      inst._repaint = function() repaint_count = repaint_count + 1 end

      async.await(inst:_render_inline())

      for _ = 1, 5 do
        api.nvim_exec_autocmds("TextChangedI", { buffer = bufnr })
      end

      -- Wait past the debounce window so the trailing fire has a chance to
      -- run (or not, if coalescing is broken).
      async.await(async.timeout(200))
      async.await(async.scheduler())

      eq(1, repaint_count)

      inst:teardown_render()
      pcall(api.nvim_buf_delete, bufnr, { force = true })
    end)
  )

  describe("Diff1Inline:diffget", function()
    local Diff1Inline = require("diffview.scene.layouts.diff_1_inline").Diff1Inline
    local inline_diff = require("diffview.scene.inline_diff")
    local api = vim.api

    -- Build a stub Diff1Inline instance with a live buffer whose old-side
    -- lines are cached and whose inline diff has been rendered, so the
    -- renderer's hunk cache mirrors the vim.diff output.
    ---@param old string[]
    ---@param new string[]
    ---@return table inst, integer bufnr
    local function prepare(old, new)
      local bufnr = api.nvim_create_buf(false, true)
      api.nvim_buf_set_lines(bufnr, 0, -1, false, new)
      inline_diff.render(bufnr, old, new)

      local win_mock = {
        file = { bufnr = bufnr, is_valid = function() return true end },
        is_valid = function() return true end,
      }
      local inst = setmetatable({
        b = win_mock,
        a_file = {},
        _cached_old_lines = old,
      }, { __index = Diff1Inline })
      return inst, bufnr
    end

    it("reverts a change hunk at the cursor line back to the old content", function()
      local inst, bufnr = prepare({ "alpha", "beta", "gamma" }, { "alpha", "BETA", "gamma" })

      eq(1, inst:diffget(2, 2))
      eq({ "alpha", "beta", "gamma" }, api.nvim_buf_get_lines(bufnr, 0, -1, false))

      pcall(api.nvim_buf_delete, bufnr, { force = true })
    end)

    it("drops added lines when the hunk under cursor is a pure addition", function()
      local inst, bufnr = prepare({ "alpha", "gamma" }, { "alpha", "beta", "gamma" })

      eq(1, inst:diffget(2, 2))
      eq({ "alpha", "gamma" }, api.nvim_buf_get_lines(bufnr, 0, -1, false))

      pcall(api.nvim_buf_delete, bufnr, { force = true })
    end)

    it("re-inserts deleted lines when the cursor sits on the anchor line", function()
      local inst, bufnr = prepare({ "alpha", "beta", "gamma" }, { "alpha", "gamma" })

      -- Pure deletion is anchored on the line preceding the gap, i.e. line 1
      -- ("alpha") since `new_start == 1` for the hole between the two lines.
      eq(1, inst:diffget(1, 1))
      eq({ "alpha", "beta", "gamma" }, api.nvim_buf_get_lines(bufnr, 0, -1, false))

      pcall(api.nvim_buf_delete, bufnr, { force = true })
    end)

    it("handles a BOF pure deletion by inserting at the top of the buffer", function()
      local inst, bufnr = prepare({ "alpha", "beta", "gamma" }, { "beta", "gamma" })

      -- Deletion at BOF has `new_start == 0`; the anchor is line 1.
      eq(1, inst:diffget(1, 1))
      eq({ "alpha", "beta", "gamma" }, api.nvim_buf_get_lines(bufnr, 0, -1, false))

      pcall(api.nvim_buf_delete, bufnr, { force = true })
    end)

    it("returns 0 when the cursor is not on a hunk", function()
      local inst, bufnr = prepare({ "alpha", "beta", "gamma" }, { "alpha", "BETA", "gamma" })

      eq(0, inst:diffget(1, 1))
      -- Buffer is unchanged.
      eq({ "alpha", "BETA", "gamma" }, api.nvim_buf_get_lines(bufnr, 0, -1, false))

      pcall(api.nvim_buf_delete, bufnr, { force = true })
    end)

    it("applies every hunk inside a multi-line visual range in one pass", function()
      local inst, bufnr = prepare(
        { "one", "two", "three", "four", "five" },
        { "ONE", "two", "THREE", "four", "FIVE" }
      )

      -- Range covers the first two change hunks (lines 1 and 3) but not
      -- the third (line 5), which should remain modified.
      eq(2, inst:diffget(1, 3))
      eq({ "one", "two", "three", "four", "FIVE" }, api.nvim_buf_get_lines(bufnr, 0, -1, false))

      pcall(api.nvim_buf_delete, bufnr, { force = true })
    end)

    it("applies hunks bottom-up so earlier splices don't shift later offsets", function()
      local inst, bufnr = prepare({ "a", "b", "c" }, { "a", "X", "Y", "b", "Z", "c" })

      -- Two pure-addition hunks: { "X", "Y" } at line 2 and { "Z" } at
      -- line 5. A visual range covering both must drop all three added
      -- lines, which only works if the later hunk is applied first.
      eq(2, inst:diffget(2, 5))
      eq({ "a", "b", "c" }, api.nvim_buf_get_lines(bufnr, 0, -1, false))

      pcall(api.nvim_buf_delete, bufnr, { force = true })
    end)

    it("returns 0 when the cached old-side lines are missing", function()
      local inst, bufnr = prepare({ "alpha" }, { "beta" })
      inst._cached_old_lines = nil

      eq(0, inst:diffget(1, 1))
      eq({ "beta" }, api.nvim_buf_get_lines(bufnr, 0, -1, false))

      pcall(api.nvim_buf_delete, bufnr, { force = true })
    end)

    it(
      "coalesces TextChanged repaints across a multi-hunk diffget into one",
      helpers.async_test(function()
        -- Install the real `TextChanged` autocmd via `_render_inline`, then
        -- spy on `inline_diff.render` to count how many repaints the batch
        -- triggers. Without suppression, each `nvim_buf_set_lines` call
        -- inside `diffget` fires `TextChanged` -> `_repaint` -> `render`,
        -- producing one render per hunk. With suppression, the batch is
        -- followed by a single trailing `_repaint` instead.
        local bufnr = api.nvim_create_buf(false, true)
        api.nvim_buf_set_lines(bufnr, 0, -1, false, {
          "ONE",
          "two",
          "THREE",
          "four",
          "five",
        })
        local winid = api.nvim_get_current_win()

        local inst = setmetatable({}, { __index = Diff1Inline })
        inst.b = {
          file = { bufnr = bufnr, is_valid = function() return true end },
          is_valid = function() return true end,
          id = winid,
        }
        inst._cached_old_lines = { "one", "two", "three", "four", "five" }

        async.await(inst:_render_inline())

        local original_render = inline_diff.render
        local render_count = 0
        inline_diff.render = function(...)
          render_count = render_count + 1
          return original_render(...)
        end

        local ok, err = pcall(function()
          -- Range covers both change hunks (lines 1 and 3); two splices.
          eq(2, inst:diffget(1, 3))
          eq(1, render_count)
        end)

        inline_diff.render = original_render
        inst:teardown_render()
        pcall(api.nvim_buf_delete, bufnr, { force = true })
        if not ok then error(err) end
      end)
    )
  end)

  it("Diff2 declares symbols { 'a', 'b' }", function() eq({ "a", "b" }, Diff2.symbols) end)

  it(
    "Diff3 declares symbols { 'a', 'b', 'c' }",
    function() eq({ "a", "b", "c" }, Diff3.symbols) end
  )

  it(
    "Diff4 declares symbols { 'a', 'b', 'c', 'd' }",
    function() eq({ "a", "b", "c", "d" }, Diff4.symbols) end
  )
end)

describe("diffview.scene.layouts.diff_1_inline diffopt forwarding", function()
  local Diff1Inline_mod = require("diffview.scene.layouts.diff_1_inline")
  local effective_diffopt = Diff1Inline_mod._test.effective_diffopt
  local inline_diff = require("diffview.scene.inline_diff")
  local api = vim.api

  local orig_diffopt

  before_each(function() orig_diffopt = vim.deepcopy(vim.opt.diffopt:get()) end)

  after_each(function() vim.opt.diffopt = vim.deepcopy(orig_diffopt) end)

  ---Reset `'diffopt'` to a fixed baseline so each test starts from the same
  ---state regardless of what the Neovim default (or a prior test) left behind.
  ---@param entries string[]
  local function set_diffopt(entries) vim.opt.diffopt = entries end

  it("maps iwhite to ignore_whitespace_change", function()
    set_diffopt({ "iwhite" })
    eq(true, effective_diffopt().ignore_whitespace_change)
  end)

  it("maps iwhiteall to ignore_whitespace", function()
    set_diffopt({ "iwhiteall" })
    eq(true, effective_diffopt().ignore_whitespace)
  end)

  it("maps iwhiteeol to ignore_whitespace_change_at_eol", function()
    set_diffopt({ "iwhiteeol" })
    eq(true, effective_diffopt().ignore_whitespace_change_at_eol)
  end)

  it("maps iblank to ignore_blank_lines", function()
    set_diffopt({ "iblank" })
    eq(true, effective_diffopt().ignore_blank_lines)
  end)

  it("does not forward icase (vim.diff has no case-insensitive option)", function()
    set_diffopt({ "icase" })
    local opts = effective_diffopt()
    assert.is_nil(opts.ignore_case)
  end)

  it("maps algorithm:<name> to algorithm", function()
    set_diffopt({ "algorithm:patience" })
    eq("patience", effective_diffopt().algorithm)
  end)

  it("sets indent_heuristic to false when absent from 'diffopt'", function()
    set_diffopt({ "internal" })
    eq(false, effective_diffopt().indent_heuristic)
  end)

  it("sets indent_heuristic to true when 'indent-heuristic' is in 'diffopt'", function()
    set_diffopt({ "indent-heuristic" })
    eq(true, effective_diffopt().indent_heuristic)
  end)

  it("never forwards linematch even when set in 'diffopt'", function()
    set_diffopt({ "linematch:60", "iblank" })
    local opts = effective_diffopt()
    assert.is_nil(opts.linematch)
    -- Sanity-check that other entries still parse (confirms the loop ran).
    eq(true, opts.ignore_blank_lines)
  end)

  it("leaves ignore flags nil when 'diffopt' has no corresponding entry", function()
    set_diffopt({ "internal" })
    local opts = effective_diffopt()
    assert.is_nil(opts.ignore_whitespace)
    assert.is_nil(opts.ignore_whitespace_change)
    assert.is_nil(opts.ignore_whitespace_change_at_eol)
    assert.is_nil(opts.ignore_blank_lines)
  end)

  it("changes inline diff output when iwhiteall is enabled", function()
    local bufnr = api.nvim_create_buf(false, true)
    api.nvim_buf_set_lines(bufnr, 0, -1, false, { "foo  bar" })

    set_diffopt({ "internal" })
    inline_diff.render(bufnr, { "foo bar" }, { "foo  bar" }, effective_diffopt())
    assert.is_true(#(inline_diff.get_hunks(bufnr) or {}) > 0)

    set_diffopt({ "internal", "iwhiteall" })
    inline_diff.render(bufnr, { "foo bar" }, { "foo  bar" }, effective_diffopt())
    eq(0, #(inline_diff.get_hunks(bufnr) or {}))

    pcall(api.nvim_buf_delete, bufnr, { force = true })
  end)
end)

describe("diffview.layout.set_file_for", function()
  it("sets the file on the window and tags it with the symbol", function()
    local stored_file
    local mock_win = { set_file = function(_, f) stored_file = f end }
    local mock_layout = { a = mock_win, windows = {}, symbols = { "a" } }
    setmetatable(mock_layout, { __index = Layout })

    local file = { path = "test.lua" }
    mock_layout:set_file_for("a", file)

    eq(file, stored_file)
    eq("a", file.symbol)
  end)
end)

describe("diffview.layout.create_wins", function()
  -- Mock vim.api and vim.cmd to verify the window creation sequence
  -- without needing real Neovim windows.
  local orig_win_call, orig_win_close, orig_get_cur_win, orig_win_is_valid, orig_cmd

  local cmds_recorded
  local next_win_id

  before_each(function()
    orig_win_call = vim.api.nvim_win_call
    orig_win_close = vim.api.nvim_win_close
    orig_get_cur_win = vim.api.nvim_get_current_win
    orig_win_is_valid = vim.api.nvim_win_is_valid
    orig_cmd = vim.cmd

    cmds_recorded = {}
    next_win_id = 100

    -- Execute the callback immediately (simulating nvim_win_call).
    vim.api.nvim_win_call = function(_, fn) fn() end
    vim.api.nvim_win_close = function() end
    vim.api.nvim_get_current_win = function()
      next_win_id = next_win_id + 1
      return next_win_id
    end
    vim.api.nvim_win_is_valid = function() return true end
    vim.cmd = function(c) cmds_recorded[#cmds_recorded + 1] = c end
  end)

  after_each(function()
    vim.api.nvim_win_call = orig_win_call
    vim.api.nvim_win_close = orig_win_close
    vim.api.nvim_get_current_win = orig_get_cur_win
    vim.api.nvim_win_is_valid = orig_win_is_valid
    vim.cmd = orig_cmd
  end)

  ---Build a mock layout with the given symbol-keyed windows.
  ---@param syms string[]
  ---@return table
  local function mock_layout(syms)
    local layout = {
      windows = {},
      state = {},
      create_pre = function(self) self.state.save_equalalways = vim.o.equalalways end,
      create_post = async.void(function() end),
      find_pivot = function() return 1 end,
    }
    for _, s in ipairs(syms) do
      layout[s] = { set_id = function(self, id) self.id = id end, close = function() end, id = nil }
    end
    setmetatable(layout, { __index = Layout })
    return layout
  end

  it(
    "issues vim.cmd calls in spec order",
    helpers.async_test(function()
      local layout = mock_layout({ "b", "a", "c" })
      async.await(layout:create_wins(1, {
        { "b", "belowright sp" },
        { "a", "aboveleft vsp" },
        { "c", "aboveleft vsp" },
      }, { "a", "b", "c" }))

      eq({ "belowright sp", "aboveleft vsp", "aboveleft vsp" }, cmds_recorded)
    end)
  )

  it(
    "builds self.windows in win_order, not creation order",
    helpers.async_test(function()
      local layout = mock_layout({ "a", "b", "c" })
      async.await(layout:create_wins(1, {
        { "b", "belowright sp" },
        { "a", "aboveleft vsp" },
        { "c", "aboveleft vsp" },
      }, { "a", "b", "c" }))

      -- Windows should be ordered a, b, c regardless of creation order.
      eq(layout.a, layout.windows[1])
      eq(layout.b, layout.windows[2])
      eq(layout.c, layout.windows[3])
    end)
  )

  it(
    "Diff4Mixed uses different creation order than window order",
    helpers.async_test(function()
      -- Diff4Mixed creates b, a, d, c but windows should be a, b, c, d.
      local layout = mock_layout({ "a", "b", "c", "d" })
      async.await(layout:create_wins(1, {
        { "b", "belowright sp" },
        { "a", "aboveleft vsp" },
        { "d", "aboveleft vsp" },
        { "c", "aboveleft vsp" },
      }, { "a", "b", "c", "d" }))

      eq(layout.a, layout.windows[1])
      eq(layout.b, layout.windows[2])
      eq(layout.c, layout.windows[3])
      eq(layout.d, layout.windows[4])
      eq({ "belowright sp", "aboveleft vsp", "aboveleft vsp", "aboveleft vsp" }, cmds_recorded)
    end)
  )

  it(
    "assigns window IDs from nvim_get_current_win to each symbol",
    helpers.async_test(function()
      local layout = mock_layout({ "a", "b" })
      async.await(layout:create_wins(1, {
        { "a", "aboveleft vsp" },
        { "b", "aboveleft vsp" },
      }, { "a", "b" }))

      -- IDs should be 101 and 102 (starting from next_win_id = 100 + 1).
      eq(101, layout.a.id)
      eq(102, layout.b.id)
    end)
  )
end)

describe("diffview.layout.create_wins integration", function()
  -- Test with real Neovim windows to verify splits actually work.

  ---Build a layout that stubs create_post so we only test window creation.
  local function real_layout(syms)
    local layout = {
      windows = {},
      state = {},
      emitter = require("diffview.events").EventEmitter(),
    }
    setmetatable(layout, { __index = Layout })
    for _, s in ipairs(syms) do
      layout[s] = { set_id = function(self, id) self.id = id end, close = function() end, id = nil }
    end
    -- Override create_post to skip file loading (no files to open).
    layout.create_post = async.void(
      function(self) vim.opt.equalalways = self.state.save_equalalways end
    )
    return layout
  end

  it(
    "creates real window splits and produces valid window IDs",
    helpers.async_test(function()
      local pivot = vim.api.nvim_get_current_win()
      assert.True(vim.api.nvim_win_is_valid(pivot))

      local layout = real_layout({ "a", "b" })
      async.await(layout:create_wins(pivot, {
        { "a", "aboveleft vsp" },
        { "b", "aboveleft vsp" },
      }, { "a", "b" }))

      -- The pivot should have been closed.
      assert.False(vim.api.nvim_win_is_valid(pivot))

      -- Both windows should be valid and distinct.
      assert.True(vim.api.nvim_win_is_valid(layout.a.id))
      assert.True(vim.api.nvim_win_is_valid(layout.b.id))
      assert.are_not.equal(layout.a.id, layout.b.id)

      eq(layout.a, layout.windows[1])
      eq(layout.b, layout.windows[2])
      eq(2, #layout.windows)

      -- Clean up: close extra windows, keeping at least one.
      local wins = vim.api.nvim_tabpage_list_wins(0)
      for i = 2, #wins do
        if vim.api.nvim_win_is_valid(wins[i]) then vim.api.nvim_win_close(wins[i], true) end
      end
    end)
  )

  it(
    "Diff3Mixed-style split: creation order differs from window order",
    helpers.async_test(function()
      local pivot = vim.api.nvim_get_current_win()
      local layout = real_layout({ "a", "b", "c" })

      async.await(layout:create_wins(pivot, {
        { "b", "belowright sp" },
        { "a", "aboveleft vsp" },
        { "c", "aboveleft vsp" },
      }, { "a", "b", "c" }))

      for _, sym in ipairs({ "a", "b", "c" }) do
        assert.True(vim.api.nvim_win_is_valid(layout[sym].id), sym .. " should be valid")
      end

      eq(layout.a, layout.windows[1])
      eq(layout.b, layout.windows[2])
      eq(layout.c, layout.windows[3])

      local wins = vim.api.nvim_tabpage_list_wins(0)
      for i = 2, #wins do
        if vim.api.nvim_win_is_valid(wins[i]) then vim.api.nvim_win_close(wins[i], true) end
      end
    end)
  )
end)
