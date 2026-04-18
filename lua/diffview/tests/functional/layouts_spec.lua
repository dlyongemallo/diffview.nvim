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
