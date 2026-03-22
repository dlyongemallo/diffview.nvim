local helpers = require("diffview.tests.helpers")
local VCSAdapter = require("diffview.vcs.adapter").VCSAdapter

local eq = helpers.eq

describe("diffview.vcs.adapter.bootstrap_preamble", function()
  local orig_executable
  local logged_messages

  before_each(function()
    orig_executable = vim.fn.executable
    logged_messages = {}
    -- Stub the global logger to capture error messages.
    DiffviewGlobal.logger.error = function(_, msg)
      logged_messages[#logged_messages + 1] = msg
    end
  end)

  after_each(function()
    vim.fn.executable = orig_executable
  end)

  it("returns the err function when the executable is found", function()
    vim.fn.executable = function() return 1 end

    local bs = { done = false, ok = false }
    local err = VCSAdapter.bootstrap_preamble(bs, { "git" }, "TestAdapter")

    assert.is_function(err)
    eq(true, bs.done)
    eq(nil, bs.err)
  end)

  it("returns nil and sets bs.err when executable is not found", function()
    vim.fn.executable = function() return 0 end

    local bs = { done = false, ok = false }
    local result = VCSAdapter.bootstrap_preamble(bs, { "nonexistent" }, "TestAdapter")

    eq(nil, result)
    eq(true, bs.done)
    assert.truthy(bs.err:find("not executable"))
    assert.is_true(#logged_messages > 0)
  end)

  it("sets bs.done = true regardless of outcome", function()
    vim.fn.executable = function() return 0 end

    local bs = { done = false, ok = false }
    VCSAdapter.bootstrap_preamble(bs, { "x" }, "Test")
    eq(true, bs.done)
  end)

  it("err function sets bs.err and logs", function()
    vim.fn.executable = function() return 1 end

    local bs = { done = false, ok = false }
    local err = VCSAdapter.bootstrap_preamble(bs, { "git" }, "TestAdapter")

    err("something went wrong")
    eq("something went wrong", bs.err)
    assert.is_true(#logged_messages > 0)
    assert.truthy(logged_messages[1]:find("TestAdapter"))
  end)
end)
