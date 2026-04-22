local helpers = require("diffview.tests.helpers")
local job_utils = require("diffview.job_utils")

local eq = helpers.eq

describe("diffview.job_utils.resolve_fail_cond", function()
  local mock_table = {
    non_zero = function()
      return true
    end,
    on_empty = function()
      return false
    end,
  }

  it("returns the named function for a string key", function()
    eq(mock_table.non_zero, job_utils.resolve_fail_cond("non_zero", mock_table))
    eq(mock_table.on_empty, job_utils.resolve_fail_cond("on_empty", mock_table))
  end)

  it("returns the function directly when given a function", function()
    local fn = function() end
    eq(fn, job_utils.resolve_fail_cond(fn, mock_table))
  end)

  it("returns the default (non_zero) when given nil", function()
    eq(mock_table.non_zero, job_utils.resolve_fail_cond(nil, mock_table))
  end)

  it("asserts on an unknown string key", function()
    assert.has_error(function()
      job_utils.resolve_fail_cond("bogus", mock_table)
    end)
  end)

  it("errors on an invalid type", function()
    assert.has_error(function()
      job_utils.resolve_fail_cond(42, mock_table)
    end)
  end)
end)

describe("diffview.job_utils.default_log_opt", function()
  it("returns a table with expected default fields", function()
    local result = job_utils.default_log_opt(nil, 1)
    eq("debug", result.func)
    eq(true, result.no_stdout)
    assert.is_table(result.debuginfo)
  end)

  it("merges user options without overriding them", function()
    local result = job_utils.default_log_opt({ func = "warn", custom = true }, 1)
    eq("warn", result.func)
    eq(true, result.custom)
    eq(true, result.no_stdout) -- default still present
  end)
end)
