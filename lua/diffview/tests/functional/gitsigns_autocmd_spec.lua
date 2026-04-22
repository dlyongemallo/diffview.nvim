local api = vim.api
local Signal = require("diffview.control").Signal

-- Tests for the GitSignsChanged User autocmd registered in DiffView:post_open.
--
-- The autocmd callback calls update_files() only when the view is not closing
-- AND the view's tabpage is the current one. These tests replicate that
-- callback logic with a lightweight mock view and a real autocmd group.

---Build a minimal mock view with the fields the callback depends on.
---@param opts? { closing_sent?: boolean, tabpage?: integer }
local function make_mock_view(opts)
  opts = opts or {}
  local closing = Signal("closing")
  if opts.closing_sent then
    closing:send()
  end

  return {
    closing = closing,
    tabpage = opts.tabpage or api.nvim_get_current_tabpage(),
    update_files_called = false,
    update_files = function(self)
      self.update_files_called = true
    end,
  }
end

---Register the GitSignsChanged autocmd exactly as the production code does,
---wiring it to the mock view.
---@param view table  Mock view from make_mock_view.
---@return integer augroup_id
local function register_autocmd(view)
  local augroup =
    api.nvim_create_augroup("diffview_gitsigns_test_" .. view.tabpage, { clear = true })
  api.nvim_create_autocmd("User", {
    group = augroup,
    pattern = "GitSignsChanged",
    callback = function()
      if not view.closing:check() and view:is_cur_tabpage() then
        view:update_files()
      end
    end,
  })

  -- Attach the same tabpage check the production code uses.
  function view:is_cur_tabpage()
    return self.tabpage == api.nvim_get_current_tabpage()
  end

  return augroup
end

describe("GitSignsChanged autocmd", function()
  local augroup

  after_each(function()
    if augroup then
      pcall(api.nvim_del_augroup_by_id, augroup)
      augroup = nil
    end
  end)

  it("calls update_files when tabpage is current and not closing", function()
    local view = make_mock_view()
    augroup = register_autocmd(view)

    vim.cmd("doautocmd User GitSignsChanged")

    assert.is_true(view.update_files_called)
  end)

  it("does not call update_files when the view is closing", function()
    local view = make_mock_view({ closing_sent = true })
    augroup = register_autocmd(view)

    vim.cmd("doautocmd User GitSignsChanged")

    assert.is_false(view.update_files_called)
  end)

  it("does not call update_files when on a different tabpage", function()
    local view = make_mock_view({ tabpage = -1 })
    augroup = register_autocmd(view)

    vim.cmd("doautocmd User GitSignsChanged")

    assert.is_false(view.update_files_called)
  end)

  it("removes the autocmd when the augroup is deleted", function()
    local view = make_mock_view()
    augroup = register_autocmd(view)

    api.nvim_del_augroup_by_id(augroup)

    -- Triggering the event after cleanup should not call update_files.
    vim.cmd("doautocmd User GitSignsChanged")
    assert.is_false(view.update_files_called)

    augroup = nil
  end)
end)
