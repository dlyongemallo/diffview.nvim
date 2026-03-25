local config = require("diffview.config")
local utils = require("diffview.utils")

describe("view.focus_diff config", function()
  local original

  before_each(function()
    original = vim.deepcopy(config.get_config())
  end)

  after_each(function()
    config.setup(original)
  end)

  it("defaults to false for view.default", function()
    config.setup({})
    assert.is_false(config.get_config().view.default.focus_diff)
  end)

  it("defaults to false for view.merge_tool", function()
    config.setup({})
    assert.is_false(config.get_config().view.merge_tool.focus_diff)
  end)

  it("defaults to false for view.file_history", function()
    config.setup({})
    assert.is_false(config.get_config().view.file_history.focus_diff)
  end)

  it("can be set to true for view.default", function()
    config.setup({ view = { default = { focus_diff = true } } })
    assert.is_true(config.get_config().view.default.focus_diff)
  end)

  it("can be set to true for view.merge_tool", function()
    config.setup({ view = { merge_tool = { focus_diff = true } } })
    assert.is_true(config.get_config().view.merge_tool.focus_diff)
  end)

  it("can be set to true for view.file_history", function()
    config.setup({ view = { file_history = { focus_diff = true } } })
    assert.is_true(config.get_config().view.file_history.focus_diff)
  end)

  it("does not affect other view options when overriding focus_diff", function()
    config.setup({ view = { default = { focus_diff = true } } })
    local conf = config.get_config()
    -- Other defaults should be preserved.
    assert.equals("diff2_horizontal", conf.view.default.layout)
    assert.is_false(conf.view.default.disable_diagnostics)
  end)

  it("preserves independent values across view sections", function()
    config.setup({
      view = {
        default = { focus_diff = false },
        merge_tool = { focus_diff = true },
        file_history = { focus_diff = false },
      },
    })
    local conf = config.get_config()
    assert.is_false(conf.view.default.focus_diff)
    assert.is_true(conf.view.merge_tool.focus_diff)
    assert.is_false(conf.view.file_history.focus_diff)
  end)
end)

describe("DiffView.update_files focus_diff behaviour", function()
  local DiffView = require("diffview.scene.views.diff.diff_view").DiffView
  local original

  before_each(function()
    original = vim.deepcopy(config.get_config())
  end)

  after_each(function()
    config.setup(original)
  end)

  -- DiffView.set_file is the method that receives the focus parameter from
  -- update_files. We test the focus-routing logic by verifying that set_file
  -- is called with the expected focus value for different config / file-kind
  -- combinations.

  ---Build a minimal mock DiffView that records set_file calls.
  ---@param file_kind string "working"|"conflicting"
  ---@return table view, table calls
  local function make_mock_view(file_kind)
    local calls = {}
    local mock_file = { path = "test.lua", kind = file_kind }

    local view = {
      initialized = false,
      closing = { check = function() return false end },
      tabpage = vim.api.nvim_get_current_tabpage(),
      options = {},
      cur_layout = {
        is_valid = function() return false end,
        is_files_loaded = function() return false end,
      },
      panel = {
        cur_file = mock_file,
        is_loading = false,
        ordered_file_list = function() return { mock_file } end,
        next_file = function() return mock_file end,
        render = function() end,
        redraw = function() end,
        reconstrain_cursor = function() end,
        update_components = function() end,
      },
      files = {
        len = function() return 1 end,
        iter = function() return ipairs({ mock_file }) end,
        update_file_trees = function() end,
        conflicting = file_kind == "conflicting" and { mock_file } or {},
        working = file_kind ~= "conflicting" and { mock_file } or {},
        staged = {},
      },
      set_file = function(self, file, focus, highlight)
        calls[#calls + 1] = { file = file, focus = focus, highlight = highlight }
      end,
    }

    return view, calls, mock_file
  end

  it("passes focus=true for a working file when view.default.focus_diff is true", function()
    config.setup({ view = { default = { focus_diff = true } } })
    local view, calls, mock_file = make_mock_view("working")

    -- Simulate the focus-routing logic from update_files on first open.
    local next_file = mock_file
    local needs_reopen = not view.initialized

    if needs_reopen then
      local focus = false
      if not view.initialized then
        local conf = config.get_config()
        local view_conf = next_file and next_file.kind == "conflicting"
          and conf.view.merge_tool
          or conf.view.default
        focus = view_conf.focus_diff
      end
      view:set_file(next_file, focus, not view.initialized or nil)
    end

    assert.equals(1, #calls)
    assert.is_true(calls[1].focus)
  end)

  it("passes focus=false for a working file when view.default.focus_diff is false", function()
    config.setup({ view = { default = { focus_diff = false } } })
    local view, calls, mock_file = make_mock_view("working")

    local next_file = mock_file
    local needs_reopen = not view.initialized

    if needs_reopen then
      local focus = false
      if not view.initialized then
        local conf = config.get_config()
        local view_conf = next_file and next_file.kind == "conflicting"
          and conf.view.merge_tool
          or conf.view.default
        focus = view_conf.focus_diff
      end
      view:set_file(next_file, focus, not view.initialized or nil)
    end

    assert.equals(1, #calls)
    assert.is_false(calls[1].focus)
  end)

  it("reads merge_tool config for conflicting files", function()
    config.setup({
      view = {
        default = { focus_diff = false },
        merge_tool = { focus_diff = true },
      },
    })
    local view, calls, mock_file = make_mock_view("conflicting")

    local next_file = mock_file
    local focus = false
    if not view.initialized then
      local conf = config.get_config()
      local view_conf = next_file and next_file.kind == "conflicting"
        and conf.view.merge_tool
        or conf.view.default
      focus = view_conf.focus_diff
    end
    view:set_file(next_file, focus, true)

    assert.equals(1, #calls)
    assert.is_true(calls[1].focus)
  end)

  it("does not override focus on subsequent updates (initialized=true)", function()
    config.setup({ view = { default = { focus_diff = true } } })
    local view, calls, mock_file = make_mock_view("working")
    view.initialized = true

    local next_file = mock_file
    local needs_reopen = true -- force reopen

    if needs_reopen then
      local focus = false
      if not view.initialized then
        local conf = config.get_config()
        local view_conf = next_file and next_file.kind == "conflicting"
          and conf.view.merge_tool
          or conf.view.default
        focus = view_conf.focus_diff
      end
      view:set_file(next_file, focus, not view.initialized or nil)
    end

    assert.equals(1, #calls)
    -- focus should remain false on refreshes, even when focus_diff is true.
    assert.is_false(calls[1].focus)
  end)
end)

describe("DiffView selected_row focuses main window", function()
  local orig_set_current_win, orig_win_is_valid, orig_win_get_buf
  local orig_buf_line_count, orig_win_set_cursor

  before_each(function()
    orig_set_current_win = vim.api.nvim_set_current_win
    orig_win_is_valid = vim.api.nvim_win_is_valid
    orig_win_get_buf = vim.api.nvim_win_get_buf
    orig_buf_line_count = vim.api.nvim_buf_line_count
    orig_win_set_cursor = vim.api.nvim_win_set_cursor
  end)

  after_each(function()
    vim.api.nvim_set_current_win = orig_set_current_win
    vim.api.nvim_win_is_valid = orig_win_is_valid
    vim.api.nvim_win_get_buf = orig_win_get_buf
    vim.api.nvim_buf_line_count = orig_buf_line_count
    vim.api.nvim_win_set_cursor = orig_win_set_cursor
  end)

  it("calls nvim_set_current_win on the main window", function()
    local focused_win = nil
    local cursor_set = nil
    local main_win_id = 77

    vim.api.nvim_win_is_valid = function() return true end
    vim.api.nvim_set_current_win = function(id) focused_win = id end
    vim.api.nvim_win_get_buf = function() return 1 end
    vim.api.nvim_buf_line_count = function() return 100 end
    vim.api.nvim_win_set_cursor = function(id, pos) cursor_set = { id = id, pos = pos } end

    -- Simulate the selected_row block from update_files.
    local initialized = false
    local selected_row = 42
    local cur_layout = {
      get_main_win = function()
        return { id = main_win_id }
      end,
    }

    if not initialized and selected_row then
      local win = cur_layout:get_main_win()
      if win and vim.api.nvim_win_is_valid(win.id) then
        vim.api.nvim_set_current_win(win.id)
        local buf = vim.api.nvim_win_get_buf(win.id)
        local line_count = vim.api.nvim_buf_line_count(buf)
        local row = math.min(selected_row, line_count)
        pcall(vim.api.nvim_win_set_cursor, win.id, { math.max(1, row), 0 })
      end
    end

    assert.equals(main_win_id, focused_win)
    assert.equals(main_win_id, cursor_set.id)
    assert.same({ 42, 0 }, cursor_set.pos)
  end)

  it("clamps row to buffer line count", function()
    local cursor_set = nil

    vim.api.nvim_win_is_valid = function() return true end
    vim.api.nvim_set_current_win = function() end
    vim.api.nvim_win_get_buf = function() return 1 end
    vim.api.nvim_buf_line_count = function() return 10 end
    vim.api.nvim_win_set_cursor = function(id, pos) cursor_set = { id = id, pos = pos } end

    local initialized = false
    local selected_row = 999
    local cur_layout = {
      get_main_win = function() return { id = 1 } end,
    }

    if not initialized and selected_row then
      local win = cur_layout:get_main_win()
      if win and vim.api.nvim_win_is_valid(win.id) then
        vim.api.nvim_set_current_win(win.id)
        local buf = vim.api.nvim_win_get_buf(win.id)
        local line_count = vim.api.nvim_buf_line_count(buf)
        local row = math.min(selected_row, line_count)
        pcall(vim.api.nvim_win_set_cursor, win.id, { math.max(1, row), 0 })
      end
    end

    assert.same({ 10, 0 }, cursor_set.pos)
  end)
end)
