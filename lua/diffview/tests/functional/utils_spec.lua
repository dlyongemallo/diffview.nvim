local helpers = require("diffview.tests.helpers")
local utils = require("diffview.utils")

local eq = helpers.eq

describe("diffview.utils.job", function()
  it("returns stdout and exit code for a successful command", function()
    local stdout, code, stderr = utils.job({ "echo", "hello" })

    eq(0, code)
    assert.is_true(#stdout > 0)
    eq("hello", stdout[1])
  end)

  it("returns non-zero code for a failing command", function()
    local stdout, code, stderr = utils.job({ "false" })

    assert.is_true(code ~= 0)
  end)

  it("kills the process and returns non-zero code on timeout", function()
    local stdout, code, stderr = utils.job({ "sleep", "60" }, { timeout = 100 })

    eq(-1, code)
  end)

  it("captures output that arrives before a timeout", function()
    -- Use sh -c to echo then sleep, so some stdout is produced before timeout.
    local stdout, code, stderr = utils.job(
      { "sh", "-c", "echo partial; sleep 60" },
      { timeout = 500 }
    )

    eq(-1, code)
    assert.is_true(#stdout > 0)
    eq("partial", vim.trim(stdout[1]))
  end)

  it("respects the cwd option", function()
    local stdout, code = utils.job({ "pwd" }, { cwd = "/tmp" })

    eq(0, code)
    -- Resolve symlinks for comparison (e.g., /tmp -> /private/tmp on macOS).
    local expected = vim.fn.resolve("/tmp")
    local actual = vim.fn.resolve(stdout[1])
    eq(expected, actual)
  end)

  it("returns empty stdout for a command with no output", function()
    local stdout, code = utils.job({ "true" })

    eq(0, code)
    -- stdout is either empty or contains a single empty string.
    local text = table.concat(stdout)
    eq("", text)
  end)
end)

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
