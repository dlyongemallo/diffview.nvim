local config = require("diffview.config")
local File = require("diffview.vcs.file").File
local GitRev = require("diffview.vcs.adapters.git.rev").GitRev
local RevType = require("diffview.vcs.rev").RevType

local api = vim.api

---Create a scratch buffer and return its number.
---@return integer
local function scratch_buf()
  local bufnr = api.nvim_create_buf(false, true)
  assert.is_true(api.nvim_buf_is_valid(bufnr))
  return bufnr
end

---Create a File object wired to a pre-existing buffer.
---@param bufnr integer
---@return vcs.File
local function make_file(bufnr)
  local adapter = {
    ctx = {
      toplevel = vim.uv.cwd(),
      dir = vim.uv.cwd(),
    },
    is_binary = function() return false end,
  }

  local file = File({
    adapter = adapter,
    path = "README.md",
    kind = "working",
    rev = GitRev(RevType.COMMIT, "abc1234"),
  })

  -- Inject the buffer so attach_buffer can operate on it.
  file.bufnr = bufnr
  return file
end

---Collect the buffer-local keymaps for the given mode into a lookup table
---keyed by lhs.
---@param bufnr integer
---@param mode string
---@return table<string, table>
local function buf_keymaps(bufnr, mode)
  local result = {}
  for _, km in ipairs(api.nvim_buf_get_keymap(bufnr, mode)) do
    result[km.lhs] = km
  end
  return result
end

describe("keymap save/restore on attach/detach", function()
  -- Ensure config is initialised so extend_keymaps and friends work,
  -- while avoiding global side effects on the rest of the test suite.
  local original_config

  before_each(function()
    original_config = vim.deepcopy(config.get_config())
    config.setup({})
  end)

  after_each(function()
    if original_config ~= nil then
      config.setup(original_config)
      original_config = nil
    end
  end)

  -- We attach with a single known mapping so tests stay deterministic.
  -- Use a plain lhs to avoid leader-key normalisation issues in headless tests.
  local test_lhs = "gz"
  local test_rhs = "<Cmd>echo 'diffview'<CR>"

  ---Attach a File with one keymap that maps `test_lhs`.
  ---@param file vcs.File
  local function attach_with_test_keymap(file)
    file:attach_buffer(true, {
      keymaps = {
        { "n", test_lhs, test_rhs, { desc = "test diffview mapping" } },
      },
    })
  end

  it("saves an existing buffer-local keymap during attach", function()
    local bufnr = scratch_buf()
    local original_rhs = "<Cmd>echo 'original'<CR>"

    -- Set a keymap on the buffer before diffview touches it.
    vim.keymap.set("n", test_lhs, original_rhs, {
      buffer = bufnr,
      desc = "original mapping",
      silent = true,
    })

    -- Verify it exists.
    local before = buf_keymaps(bufnr, "n")
    assert.is_not_nil(before[test_lhs])

    local file = make_file(bufnr)
    attach_with_test_keymap(file)

    -- The saved_keymaps table should contain the original mapping.
    local state = File.attached[bufnr]
    assert.is_not_nil(state)
    assert.is_not_nil(state.saved_keymaps)

    local saved = state.saved_keymaps["n " .. test_lhs]
    assert.is_not_nil(saved)
    assert.equals("n", saved.mode)
    assert.equals(test_lhs, saved.lhs)
    assert.equals(original_rhs, saved.rhs)
    assert.is_true(saved.opts.silent)

    -- Clean up.
    file:detach_buffer()
    api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("saves callback-based keymaps correctly", function()
    local bufnr = scratch_buf()
    local called = false
    local original_cb = function() called = true end

    vim.keymap.set("n", test_lhs, original_cb, {
      buffer = bufnr,
      desc = "callback mapping",
    })

    local file = make_file(bufnr)
    attach_with_test_keymap(file)

    local state = File.attached[bufnr]
    local saved = state.saved_keymaps["n " .. test_lhs]
    assert.is_not_nil(saved)
    assert.is_function(saved.callback)

    file:detach_buffer()
    api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("does not save a keymap that does not exist", function()
    local bufnr = scratch_buf()

    -- Do not set any keymap for test_lhs; the buffer is clean.
    local file = make_file(bufnr)
    attach_with_test_keymap(file)

    local state = File.attached[bufnr]
    assert.is_not_nil(state)
    assert.is_not_nil(state.saved_keymaps)

    -- Nothing should have been saved for our lhs.
    assert.is_nil(state.saved_keymaps["n " .. test_lhs])

    file:detach_buffer()
    api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("restores an overwritten keymap on detach", function()
    local bufnr = scratch_buf()
    local original_rhs = "<Cmd>echo 'original'<CR>"

    -- Set the original keymap.
    vim.keymap.set("n", test_lhs, original_rhs, {
      buffer = bufnr,
      desc = "original mapping",
      silent = true,
      noremap = true,
    })

    local file = make_file(bufnr)
    attach_with_test_keymap(file)

    -- After attach, the keymap should now point to the diffview mapping.
    local during = buf_keymaps(bufnr, "n")
    assert.is_not_nil(during[test_lhs])
    assert.equals(test_rhs, during[test_lhs].rhs)

    -- Detach should restore the original.
    file:detach_buffer()

    local after = buf_keymaps(bufnr, "n")
    assert.is_not_nil(after[test_lhs])
    assert.equals(original_rhs, after[test_lhs].rhs)
    assert.equals("original mapping", after[test_lhs].desc)

    api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("restores a callback-based keymap on detach", function()
    local bufnr = scratch_buf()
    local call_count = 0
    local original_cb = function() call_count = call_count + 1 end

    vim.keymap.set("n", test_lhs, original_cb, { buffer = bufnr })

    local file = make_file(bufnr)
    attach_with_test_keymap(file)

    -- After attach the callback should be replaced.
    local during = buf_keymaps(bufnr, "n")
    assert.is_not_nil(during[test_lhs])
    assert.is_nil(during[test_lhs].callback)

    -- Detach and verify the callback was restored.
    file:detach_buffer()

    local after = buf_keymaps(bufnr, "n")
    assert.is_not_nil(after[test_lhs])
    assert.is_not_nil(after[test_lhs].callback)

    -- Execute the restored mapping to confirm it is the original.
    after[test_lhs].callback()
    assert.equals(1, call_count)

    api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("removes diffview keymaps on detach when no prior mapping existed", function()
    local bufnr = scratch_buf()

    -- No prior keymap for test_lhs.
    local file = make_file(bufnr)
    attach_with_test_keymap(file)

    -- The diffview keymap should be present.
    local during = buf_keymaps(bufnr, "n")
    assert.is_not_nil(during[test_lhs])

    file:detach_buffer()

    -- After detach the keymap should be gone.
    local after = buf_keymaps(bufnr, "n")
    assert.is_nil(after[test_lhs])

    api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("preserves saved keymap opts (noremap, nowait, expr)", function()
    local bufnr = scratch_buf()

    vim.keymap.set("n", test_lhs, "<Cmd>echo 'orig'<CR>", {
      buffer = bufnr,
      noremap = true,
      nowait = true,
      expr = false,
      silent = false,
    })

    local file = make_file(bufnr)
    attach_with_test_keymap(file)

    local state = File.attached[bufnr]
    local saved = state.saved_keymaps["n " .. test_lhs]
    assert.is_not_nil(saved)
    assert.is_true(saved.opts.noremap)
    assert.is_true(saved.opts.nowait)
    assert.is_false(saved.opts.expr)

    file:detach_buffer()
    api.nvim_buf_delete(bufnr, { force = true })
  end)
end)
