local async = require("diffview.async")
local control = require("diffview.control")
local File = require("diffview.vcs.file").File
local GitRev = require("diffview.vcs.adapters.git.rev").GitRev
local RevType = require("diffview.vcs.rev").RevType
local helpers = require("diffview.tests.helpers")

local Signal = control.Signal

describe("diffview.vcs.file", function()
  it("uses the null buffer when a conflict stage blob is missing", function()
    local show_called = false

    local adapter = {
      ctx = {
        toplevel = vim.uv.cwd(),
        dir = vim.uv.cwd(),
      },
      file_blob_hash = function(_, _, rev_arg)
        assert.equals(":2", rev_arg)
        return nil
      end,
      is_binary = function()
        return false
      end,
      show = function(_, _, _, callback)
        show_called = true
        callback(nil, { "unexpected" })
      end,
    }

    local file = File({
      adapter = adapter,
      path = "README.md",
      kind = "conflicting",
      rev = GitRev(RevType.STAGE, 2),
    })

    local bufnr = async.await(file:create_buffer())

    assert.equals(File._get_null_buffer(), bufnr)
    assert.False(show_called)
  end)

  it("bails out of create_buffer if deactivated before produce_data", helpers.async_test(function()
    local show_called = false

    local adapter = {
      ctx = {
        toplevel = vim.uv.cwd(),
        dir = vim.uv.cwd(),
      },
      is_binary = function()
        return false
      end,
      show = async.wrap(function(_, _, _, callback)
        show_called = true
        callback(nil, { "some data" })
      end),
    }

    local file = File({
      adapter = adapter,
      path = "README.md",
      kind = "working",
      rev = GitRev(RevType.COMMIT, "abc1234"),
    })

    -- Deactivate the file before create_buffer runs.
    file.active = false

    local ok, err = async.pawait(file.create_buffer, file)

    assert.False(ok)
    assert.is_string(err)
    assert.is_not_nil(err:find(File.CANCELLED, 1, true))
    -- produce_data (and thus show) should never have been called.
    assert.False(show_called)
    assert.is_nil(file.bufnr)
  end))

  it("bails out of create_buffer if deactivated during produce_data", helpers.async_test(function()
    local yield_signal = Signal("yield")
    local produce_data_started = Signal("produce_data_started")
    local show_called = false

    local adapter = {
      ctx = {
        toplevel = vim.uv.cwd(),
        dir = vim.uv.cwd(),
      },
      is_binary = function()
        return false
      end,
      show = async.wrap(function(_, _, _, callback)
        show_called = true
        produce_data_started:send()
        async.await(yield_signal)
        callback(nil, { "some data" })
      end),
    }

    local file = File({
      adapter = adapter,
      path = "README.md",
      kind = "working",
      rev = GitRev(RevType.COMMIT, "abc1234"),
    })

    -- Capture results from the thread so we can assert outside it.
    -- Assertions inside async.void coroutines fail silently.
    local thread_ok, thread_err

    local create_buffer_thread = async.void(function()
      thread_ok, thread_err = async.pawait(file.create_buffer, file)
    end)

    create_buffer_thread()

    -- Wait for produce_data to start, confirming the show job was invoked.
    async.await(produce_data_started)
    assert.is_not_nil(file.bufnr)
    assert.is_true(vim.api.nvim_buf_is_valid(file.bufnr))
    local pre_cancel_bufnr = file.bufnr

    -- Deactivate the file while produce_data is yielded, then resume it.
    file.active = false
    yield_signal:send()

    -- Let the thread finish.
    async.await(async.scheduler())

    -- The pre-allocated buffer should have been cleaned up.
    assert.is_true(show_called)
    assert.False(thread_ok)
    assert.is_string(thread_err)
    assert.is_not_nil(thread_err:find(File.CANCELLED, 1, true))
    assert.is_nil(file.bufnr)
    assert.is_false(vim.api.nvim_buf_is_valid(pre_cancel_bufnr))
  end))
end)
