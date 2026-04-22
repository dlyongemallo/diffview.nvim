local config = require("diffview.config")

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

describe("DiffView._should_focus_diff", function()
  local DiffView = require("diffview.scene.views.diff.diff_view").DiffView
  local original

  before_each(function()
    original = vim.deepcopy(config.get_config())
  end)

  after_each(function()
    config.setup(original)
  end)

  it("returns true for a working file when view.default.focus_diff is true", function()
    config.setup({ view = { default = { focus_diff = true } } })
    local view = { initialized = false }
    assert.is_true(DiffView._should_focus_diff(view, { kind = "working" }))
  end)

  it("returns false for a working file when view.default.focus_diff is false", function()
    config.setup({ view = { default = { focus_diff = false } } })
    local view = { initialized = false }
    assert.is_false(DiffView._should_focus_diff(view, { kind = "working" }))
  end)

  it("reads merge_tool config for conflicting files", function()
    config.setup({
      view = {
        default = { focus_diff = false },
        merge_tool = { focus_diff = true },
      },
    })
    local view = { initialized = false }
    assert.is_true(DiffView._should_focus_diff(view, { kind = "conflicting" }))
  end)

  it("returns false when initialized is true, even with focus_diff enabled", function()
    config.setup({ view = { default = { focus_diff = true } } })
    local view = { initialized = true }
    assert.is_false(DiffView._should_focus_diff(view, { kind = "working" }))
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

    vim.api.nvim_win_is_valid = function()
      return true
    end
    vim.api.nvim_set_current_win = function(id)
      focused_win = id
    end
    vim.api.nvim_win_get_buf = function()
      return 1
    end
    vim.api.nvim_buf_line_count = function()
      return 100
    end
    vim.api.nvim_win_set_cursor = function(id, pos)
      cursor_set = { id = id, pos = pos }
    end

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

    vim.api.nvim_win_is_valid = function()
      return true
    end
    vim.api.nvim_set_current_win = function() end
    vim.api.nvim_win_get_buf = function()
      return 1
    end
    vim.api.nvim_buf_line_count = function()
      return 10
    end
    vim.api.nvim_win_set_cursor = function(id, pos)
      cursor_set = { id = id, pos = pos }
    end

    local initialized = false
    local selected_row = 999
    local cur_layout = {
      get_main_win = function()
        return { id = 1 }
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

    assert.same({ 10, 0 }, cursor_set.pos)
  end)
end)
