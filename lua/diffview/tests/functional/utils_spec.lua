local helpers = require("diffview.tests.helpers")
local utils = require("diffview.utils")

local eq = helpers.eq

describe("diffview.utils.set_win_buf", function()
  it("does not retry when setting the window buffer succeeds", function()
    local original_set_win_buf = vim.api.nvim_win_set_buf
    local original_no_win_event_call = utils.no_win_event_call

    local calls = 0
    local ok, err = pcall(function()
      vim.api.nvim_win_set_buf = function() calls = calls + 1 end
      utils.no_win_event_call = function() error("should not be called") end

      local success, msg, recovered = utils.set_win_buf(1, 1)

      eq(true, success)
      eq(nil, msg)
      eq(false, recovered)
      eq(1, calls)
    end)

    vim.api.nvim_win_set_buf = original_set_win_buf
    utils.no_win_event_call = original_no_win_event_call

    if not ok then error(err) end
  end)

  it("retries with ignored events when the first set fails", function()
    local original_set_win_buf = vim.api.nvim_win_set_buf
    local original_no_win_event_call = utils.no_win_event_call

    local calls = 0
    local no_event_calls = 0
    local ok, err = pcall(function()
      vim.api.nvim_win_set_buf = function()
        calls = calls + 1
        if calls == 1 then
          error(
            'BufEnter Autocommands for "*": Vim:E903: Process failed to start: too many open files'
          )
        end
      end
      utils.no_win_event_call = function(f)
        no_event_calls = no_event_calls + 1
        local success, inner_err = pcall(f)
        return success, inner_err
      end

      local success, msg, recovered = utils.set_win_buf(1, 1)

      eq(true, success)
      eq(true, recovered)
      eq(2, calls)
      eq(1, no_event_calls)
      assert.True(msg and msg:find("too many open files", 1, true) ~= nil)
    end)

    vim.api.nvim_win_set_buf = original_set_win_buf
    utils.no_win_event_call = original_no_win_event_call

    if not ok then error(err) end
  end)

  it("returns an error when both attempts fail", function()
    local original_set_win_buf = vim.api.nvim_win_set_buf
    local original_no_win_event_call = utils.no_win_event_call

    local calls = 0
    local no_event_calls = 0
    local ok, err = pcall(function()
      vim.api.nvim_win_set_buf = function()
        calls = calls + 1
        if calls == 1 then
          error("first failure")
        end

        error("second failure")
      end
      utils.no_win_event_call = function(f)
        no_event_calls = no_event_calls + 1
        local success, inner_err = pcall(f)
        if not success then
          return false, "retry failure"
        end
        return success, inner_err
      end

      local success, msg, recovered = utils.set_win_buf(1, 1)

      eq(false, success)
      eq(false, recovered)
      eq(2, calls)
      eq(1, no_event_calls)
      eq("retry failure", msg)
    end)

    vim.api.nvim_win_set_buf = original_set_win_buf
    utils.no_win_event_call = original_no_win_event_call

    if not ok then error(err) end
  end)
end)
