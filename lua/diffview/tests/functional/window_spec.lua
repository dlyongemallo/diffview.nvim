local async = require("diffview.async")
local control = require("diffview.control")
local File = require("diffview.vcs.file").File
local GitRev = require("diffview.vcs.adapters.git.rev").GitRev
local RevType = require("diffview.vcs.rev").RevType
local Window = require("diffview.scene.window").Window
local helpers = require("diffview.tests.helpers")

local Signal = control.Signal

---Create a mock adapter with optional overrides.
---@param overrides? table
---@return table
local function mock_adapter(overrides)
  return vim.tbl_deep_extend("force", {
    ctx = {
      toplevel = vim.uv.cwd(),
      dir = vim.uv.cwd(),
    },
    is_binary = function() return false end,
  }, overrides or {})
end

---Create a Window attached to a File with the given adapter.
---@param adapter table
---@param file_opts? table
---@return Window, vcs.File
local function make_window(adapter, file_opts)
  local file = File(vim.tbl_extend("force", {
    adapter = adapter,
    path = "README.md",
    kind = "working",
    rev = GitRev(RevType.COMMIT, "abc1234"),
  }, file_opts or {}))

  local win = Window({
    id = vim.api.nvim_get_current_win(),
  })
  win:set_file(file)

  return win, file
end

describe("diffview.scene.window", function()
  it("load_file bails out if the file is inactive", helpers.async_test(function()
    local show_called = false
    local adapter = mock_adapter({
      show = async.wrap(function(_, _, _, callback)
        show_called = true
        callback(nil, { "data" })
      end),
    })

    local win, file = make_window(adapter)
    file.active = false

    local ok = async.await(win:load_file())

    assert.False(ok)
    -- show should never have been called since we bailed before create_buffer.
    assert.False(show_called)
  end))

  it("load_file suppresses error when create_buffer is cancelled mid-async", helpers.async_test(function()
    local yield_signal = Signal("yield")
    local produce_data_started = Signal("produce_data_started")

    local adapter = mock_adapter({
      show = async.wrap(function(_, _, _, callback)
        produce_data_started:send()
        async.await(yield_signal)
        callback(nil, { "data" })
      end),
    })

    local win, file = make_window(adapter)

    -- Start load_file in a separate thread so we can deactivate mid-flight.
    local load_ok

    local load_thread = async.void(function()
      load_ok = async.await(win:load_file())
    end)

    load_thread()

    -- Wait until we're inside produce_data (the show mock).
    async.await(produce_data_started)

    -- Deactivate and let the show mock finish.
    file.active = false
    yield_signal:send()
    async.await(async.scheduler())

    -- load_file should report failure without a user-visible error.
    assert.False(load_ok)
    assert.is_nil(file.bufnr)
  end))
end)
