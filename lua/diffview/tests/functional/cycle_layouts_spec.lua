local actions = require("diffview.actions")
local config = require("diffview.config")
local helpers = require("diffview.tests.helpers")
local utils = require("diffview.utils")

local Diff1 = require("diffview.scene.layouts.diff_1").Diff1
local Diff2Hor = require("diffview.scene.layouts.diff_2_hor").Diff2Hor
local Diff2Ver = require("diffview.scene.layouts.diff_2_ver").Diff2Ver
local Diff3Hor = require("diffview.scene.layouts.diff_3_hor").Diff3Hor
local Diff3Ver = require("diffview.scene.layouts.diff_3_ver").Diff3Ver
local Diff3Mixed = require("diffview.scene.layouts.diff_3_mixed").Diff3Mixed
local Diff4Mixed = require("diffview.scene.layouts.diff_4_mixed").Diff4Mixed

local eq = helpers.eq

describe("diffview.config cycle_layouts defaults", function()
  it("has a cycle_layouts section in view defaults", function()
    local defaults = config.defaults
    assert.truthy(defaults.view.cycle_layouts)
  end)

  it("default list contains diff2_horizontal and diff2_vertical", function()
    local default_list = config.defaults.view.cycle_layouts.default
    eq({ "diff2_horizontal", "diff2_vertical" }, default_list)
  end)

  it("merge_tool list contains the expected five layouts", function()
    local mt_list = config.defaults.view.cycle_layouts.merge_tool
    eq({
      "diff3_horizontal",
      "diff3_vertical",
      "diff3_mixed",
      "diff4_mixed",
      "diff1_plain",
    }, mt_list)
  end)

  it("cycle_layouts persists after setup with empty overrides", function()
    local original = vim.deepcopy(config.get_config())
    local old_warn = utils.warn
    utils.warn = function() end

    local ok, err = pcall(function()
      config.setup({})
      local conf = config.get_config()
      assert.truthy(conf.view.cycle_layouts)
      assert.truthy(conf.view.cycle_layouts.default)
      assert.truthy(conf.view.cycle_layouts.merge_tool)
    end)

    utils.warn = old_warn
    config.setup(original)

    if not ok then error(err) end
  end)
end)

describe("diffview.actions.set_layout name resolution", function()
  local lib = require("diffview.lib")
  local stubs = {}
  local err_messages

  local function stub(tbl, key, val)
    stubs[#stubs + 1] = { tbl, key, tbl[key] }
    tbl[key] = val
  end

  before_each(function()
    err_messages = {}
    stub(utils, "err", function(msg)
      err_messages[#err_messages + 1] = msg
    end)
    -- Ensure no view is active so set_layout returns early after resolving.
    stub(lib, "get_current_view", function() return nil end)
  end)

  after_each(function()
    for i = #stubs, 1, -1 do
      local s = stubs[i]
      s[1][s[2]] = s[3]
    end
    stubs = {}
  end)

  it("known layout names produce no error", function()
    local known_names = {
      "diff1_plain",
      "diff2_horizontal",
      "diff2_vertical",
      "diff3_horizontal",
      "diff3_vertical",
      "diff3_mixed",
      "diff4_mixed",
    }

    for _, name in ipairs(known_names) do
      err_messages = {}
      local fn = actions.set_layout(name)
      assert.is_function(fn)
      fn()
      eq(0, #err_messages, "unexpected error for layout: " .. name)
    end
  end)

  it("unknown layout name triggers an error message", function()
    local fn = actions.set_layout("nonexistent_layout")
    fn()
    eq(1, #err_messages)
    assert.truthy(err_messages[1]:find("Unknown layout"))
    assert.truthy(err_messages[1]:find("nonexistent_layout"))
  end)

  it("empty string layout name triggers an error message", function()
    local fn = actions.set_layout("")
    fn()
    eq(1, #err_messages)
    assert.truthy(err_messages[1]:find("Unknown layout"))
  end)
end)

describe("diffview.actions.cycle_layout cycling logic", function()
  local lib = require("diffview.lib")
  local DiffView_class = require("diffview.scene.views.diff.diff_view").DiffView

  local stubs = {}
  local converted_layouts

  local function stub(tbl, key, val)
    stubs[#stubs + 1] = { tbl, key, tbl[key] }
    tbl[key] = val
  end

  before_each(function()
    converted_layouts = {}
  end)

  after_each(function()
    for i = #stubs, 1, -1 do
      local s = stubs[i]
      s[1][s[2]] = s[3]
    end
    stubs = {}
  end)

  --- Build a mock file entry with a given layout class.
  local function mock_file_entry(layout_class, kind)
    return {
      layout = {
        class = layout_class,
        emitter = require("diffview.events").EventEmitter(),
      },
      kind = kind or "working",
      convert_layout = function(self, next_class)
        converted_layouts[#converted_layouts + 1] = next_class
        self.layout.class = next_class
      end,
    }
  end

  --- Build a mock DiffView.
  local function mock_diff_view(files, cur_entry)
    return {
      class = DiffView_class,
      instanceof = function(self, other) return self.class == other end,
      cur_entry = cur_entry,
      cur_layout = {
        get_main_win = function() return { id = 1 } end,
        is_focused = function() return false end,
        sync_scroll = function() end,
      },
      panel = {
        files = { working = files, staged = {} },
      },
      files = { conflicting = {} },
      set_file = function() end,
    }
  end

  it("returns early when no view is active", function()
    stub(lib, "get_current_view", function() return nil end)

    -- Should not error.
    actions.cycle_layout()
    eq(0, #converted_layouts)
  end)

  it("returns early when cur_entry is nil (empty diff)", function()
    local view = mock_diff_view({}, nil)

    stub(lib, "get_current_view", function() return view end)

    -- Should not error despite files being nil.
    actions.cycle_layout()
    eq(0, #converted_layouts)
  end)

  it("cycles from diff2_horizontal to diff2_vertical (default list)", function()
    local file = mock_file_entry(Diff2Hor)
    local view = mock_diff_view({ file }, file)

    stub(lib, "get_current_view", function() return view end)
    stub(vim.api, "nvim_win_get_cursor", function() return { 1, 0 } end)

    actions.cycle_layout()

    eq(1, #converted_layouts)
    eq(Diff2Ver, converted_layouts[1])
  end)

  it("wraps from diff2_vertical back to diff2_horizontal", function()
    local file = mock_file_entry(Diff2Ver)
    local view = mock_diff_view({ file }, file)

    stub(lib, "get_current_view", function() return view end)
    stub(vim.api, "nvim_win_get_cursor", function() return { 1, 0 } end)

    actions.cycle_layout()

    eq(1, #converted_layouts)
    eq(Diff2Hor, converted_layouts[1])
  end)

  it("cycles through merge_tool layouts for conflicting files", function()
    -- Expected merge_tool order: Diff3Hor -> Diff3Ver -> Diff3Mixed -> Diff4Mixed -> Diff1
    local expected_cycle = { Diff3Ver, Diff3Mixed, Diff4Mixed, Diff1, Diff3Hor }

    local current_class = Diff3Hor
    for i, expected_next in ipairs(expected_cycle) do
      converted_layouts = {}
      local file = mock_file_entry(current_class, "conflicting")
      local view = mock_diff_view({}, file)
      view.files.conflicting = { file }

      stub(lib, "get_current_view", function() return view end)
      stub(vim.api, "nvim_win_get_cursor", function() return { 1, 0 } end)

      actions.cycle_layout()

      eq(1, #converted_layouts, "step " .. i .. ": expected one conversion")
      eq(expected_next, converted_layouts[1], "step " .. i .. ": wrong next layout")

      current_class = expected_next

      -- Clean up stubs for next iteration.
      for j = #stubs, 1, -1 do
        local s = stubs[j]
        s[1][s[2]] = s[3]
      end
      stubs = {}
    end
  end)

  it("applies layout change to all files in the list", function()
    local file1 = mock_file_entry(Diff2Hor)
    local file2 = mock_file_entry(Diff2Hor)
    local file3 = mock_file_entry(Diff2Hor)
    local view = mock_diff_view({ file1, file2, file3 }, file1)

    stub(lib, "get_current_view", function() return view end)
    stub(vim.api, "nvim_win_get_cursor", function() return { 1, 0 } end)

    actions.cycle_layout()

    -- All three files should have been converted.
    eq(3, #converted_layouts)
    for _, layout in ipairs(converted_layouts) do
      eq(Diff2Ver, layout)
    end
  end)
end)

describe("diffview.actions.cycle_layout with custom config", function()
  local lib = require("diffview.lib")
  local DiffView_class = require("diffview.scene.views.diff.diff_view").DiffView

  local stubs = {}
  local converted_layouts

  local function stub(tbl, key, val)
    stubs[#stubs + 1] = { tbl, key, tbl[key] }
    tbl[key] = val
  end

  local function mock_file_entry(layout_class, kind)
    return {
      layout = {
        class = layout_class,
        emitter = require("diffview.events").EventEmitter(),
      },
      kind = kind or "working",
      convert_layout = function(self, next_class)
        converted_layouts[#converted_layouts + 1] = next_class
        self.layout.class = next_class
      end,
    }
  end

  local function mock_diff_view(files, cur_entry)
    return {
      class = DiffView_class,
      instanceof = function(self, other) return self.class == other end,
      cur_entry = cur_entry,
      cur_layout = {
        get_main_win = function() return { id = 1 } end,
        is_focused = function() return false end,
        sync_scroll = function() end,
      },
      panel = {
        files = { working = files, staged = {} },
      },
      files = { conflicting = {} },
      set_file = function() end,
    }
  end

  local original_config

  before_each(function()
    converted_layouts = {}
    original_config = vim.deepcopy(config.get_config())
  end)

  after_each(function()
    for i = #stubs, 1, -1 do
      local s = stubs[i]
      s[1][s[2]] = s[3]
    end
    stubs = {}

    -- Restore original config.
    local old_warn = utils.warn
    utils.warn = function() end
    config.setup(original_config)
    utils.warn = old_warn
  end)

  it("uses custom default cycle when configured", function()
    local old_warn = utils.warn
    utils.warn = function() end
    config.setup({
      view = {
        cycle_layouts = {
          default = { "diff1_plain", "diff2_horizontal", "diff2_vertical" },
        },
      },
    })
    utils.warn = old_warn

    -- Starting at Diff1, should cycle to Diff2Hor.
    local file = mock_file_entry(Diff1)
    local view = mock_diff_view({ file }, file)

    stub(lib, "get_current_view", function() return view end)
    stub(vim.api, "nvim_win_get_cursor", function() return { 1, 0 } end)

    actions.cycle_layout()

    eq(1, #converted_layouts)
    eq(Diff2Hor, converted_layouts[1])
  end)

  it("falls back to defaults when custom list has only unknown names", function()
    local old_warn = utils.warn
    utils.warn = function() end
    config.setup({
      view = {
        cycle_layouts = {
          default = { "bogus_layout", "another_fake" },
        },
      },
    })
    utils.warn = old_warn

    -- Resolved list will be empty, so fallback defaults apply.
    -- Default: Diff2Hor -> Diff2Ver.
    local file = mock_file_entry(Diff2Hor)
    local view = mock_diff_view({ file }, file)

    stub(lib, "get_current_view", function() return view end)
    stub(vim.api, "nvim_win_get_cursor", function() return { 1, 0 } end)

    actions.cycle_layout()

    eq(1, #converted_layouts)
    eq(Diff2Ver, converted_layouts[1])
  end)
end)
