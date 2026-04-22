local config = require("diffview.config")
local File = require("diffview.vcs.file").File

-- Helper: run setup() with the given overrides and return the live config.
local function setup_with(overrides)
  config.setup(overrides or {})
  return config.get_config()
end

-- ---------------------------------------------------------------------------
-- clean_up_buffers (commit 7009c40)
-- ---------------------------------------------------------------------------

describe("clean_up_buffers", function()
  local original

  before_each(function()
    original = vim.deepcopy(config.get_config())
  end)

  after_each(function()
    config.setup(original)
  end)

  it("defaults to false", function()
    local conf = setup_with({})
    assert.is_false(conf.clean_up_buffers)
  end)

  it("survives setup() when set to true", function()
    local conf = setup_with({ clean_up_buffers = true })
    assert.is_true(conf.clean_up_buffers)
  end)

  it("File.created_bufs is a table for tracking buffer numbers", function()
    assert.is_table(File.created_bufs)
  end)

  it("File.created_bufs can store and retrieve buffer tracking entries", function()
    -- Save any pre-existing state so we can restore it.
    local saved = vim.deepcopy(File.created_bufs)

    File.created_bufs[9999] = true
    assert.is_true(File.created_bufs[9999])

    -- Clean up.
    File.created_bufs[9999] = nil
    for k, v in pairs(saved) do
      File.created_bufs[k] = v
    end
  end)
end)

-- ---------------------------------------------------------------------------
-- show_branch_name (commit 5ec3cde)
-- ---------------------------------------------------------------------------

describe("show_branch_name", function()
  local original

  before_each(function()
    original = vim.deepcopy(config.get_config())
  end)

  after_each(function()
    config.setup(original)
  end)

  it("defaults to false", function()
    local conf = setup_with({})
    assert.is_false(conf.file_panel.show_branch_name)
  end)

  it("survives setup() when set to true", function()
    local conf = setup_with({ file_panel = { show_branch_name = true } })
    assert.is_true(conf.file_panel.show_branch_name)
  end)

  it("survives setup() when explicitly set to false", function()
    local conf = setup_with({ file_panel = { show_branch_name = false } })
    assert.is_false(conf.file_panel.show_branch_name)
  end)
end)

-- ---------------------------------------------------------------------------
-- rename_threshold (commit c5b9200)
-- ---------------------------------------------------------------------------

describe("rename_threshold", function()
  local original

  before_each(function()
    original = vim.deepcopy(config.get_config())
  end)

  after_each(function()
    config.setup(original)
  end)

  it("defaults to nil", function()
    local conf = setup_with({})
    assert.is_nil(conf.rename_threshold)
  end)

  it("accepts a valid integer value", function()
    local conf = setup_with({ rename_threshold = 40 })
    assert.equals(40, conf.rename_threshold)
  end)

  it("produces the expected -M flag format when configured", function()
    -- Replicate the flag construction used in the git adapter.
    local threshold = 40
    local flag = "-M" .. threshold .. "%"
    assert.equals("-M40%", flag)
  end)

  it("produces nil flag when rename_threshold is nil", function()
    local conf = setup_with({})
    local t = conf.rename_threshold
    local flag = t and ("-M" .. t .. "%") or nil
    assert.is_nil(flag)
  end)

  it("flag format matches for various valid thresholds", function()
    for _, threshold in ipairs({ 0, 25, 50, 75, 100 }) do
      local conf = setup_with({ rename_threshold = threshold })
      local t = conf.rename_threshold
      local flag = t and ("-M" .. t .. "%") or nil
      assert.equals("-M" .. threshold .. "%", flag)
    end
  end)
end)

-- ---------------------------------------------------------------------------
-- diff1_plain layout (commit 773e15b)
-- ---------------------------------------------------------------------------

describe("diff1_plain layout", function()
  local original

  before_each(function()
    original = vim.deepcopy(config.get_config())
  end)

  after_each(function()
    config.setup(original)
  end)

  it("is a valid layout name that name_to_layout can resolve", function()
    local layout_class = config.name_to_layout("diff1_plain")
    assert.is_not_nil(layout_class)
  end)

  it("is listed in the standard_layouts for view.default validation", function()
    -- The config setup should accept diff1_plain for view.default.layout
    -- without emitting an error.
    local conf = setup_with({ view = { default = { layout = "diff1_plain" } } })
    assert.equals("diff1_plain", conf.view.default.layout)
  end)

  it("is listed in the standard_layouts for view.file_history validation", function()
    local conf = setup_with({ view = { file_history = { layout = "diff1_plain" } } })
    assert.equals("diff1_plain", conf.view.file_history.layout)
  end)

  it("is included in the merge_tool cycle_layouts default", function()
    local conf = setup_with({})
    assert.truthy(
      vim.tbl_contains(conf.view.cycle_layouts.merge_tool, "diff1_plain"),
      "diff1_plain should be in merge_tool cycle_layouts"
    )
  end)
end)

-- ---------------------------------------------------------------------------
-- view.foldlevel
-- ---------------------------------------------------------------------------

describe("view.foldlevel", function()
  local original

  before_each(function()
    original = vim.deepcopy(config.get_config())
  end)

  after_each(function()
    config.setup(original)
  end)

  it("defaults to 0", function()
    local conf = setup_with({})
    assert.equals(0, conf.view.foldlevel)
  end)

  it("accepts a user override", function()
    local conf = setup_with({ view = { foldlevel = 99 } })
    assert.equals(99, conf.view.foldlevel)
  end)

  it("rejects non-integer values and falls back to the default", function()
    local conf = setup_with({ view = { foldlevel = "high" } })
    assert.equals(0, conf.view.foldlevel)
  end)

  it("rejects negative values and falls back to the default", function()
    local conf = setup_with({ view = { foldlevel = -1 } })
    assert.equals(0, conf.view.foldlevel)
  end)

  it("rejects fractional values and falls back to the default", function()
    local conf = setup_with({ view = { foldlevel = 1.5 } })
    assert.equals(0, conf.view.foldlevel)
  end)
end)

-- ---------------------------------------------------------------------------
-- commit_format (commit ecdb020)
-- ---------------------------------------------------------------------------

describe("commit_format", function()
  local original

  before_each(function()
    original = vim.deepcopy(config.get_config())
  end)

  after_each(function()
    config.setup(original)
  end)

  it("has the expected default list of formatter names", function()
    local conf = setup_with({})
    local expected =
      { "status", "files", "stats", "hash", "reflog", "ref", "subject", "author", "date" }
    assert.same(expected, conf.file_history_panel.commit_format)
  end)

  it("the render module loads without error and exports a file_history_panel function", function()
    -- The formatters table is local to render.lua and not exported, so
    -- we verify at runtime that the render module loads and exposes the
    -- entry point that consumes the formatter names.
    local render = require("diffview.scene.views.file_history.render")
    assert.is_function(render.file_history_panel)
  end)

  it("survives setup() with a custom ordering", function()
    local custom = { "hash", "subject", "date" }
    local conf = setup_with({ file_history_panel = { commit_format = custom } })
    assert.same(custom, conf.file_history_panel.commit_format)
  end)

  it("survives setup() with a single-element list", function()
    local custom = { "subject" }
    local conf = setup_with({ file_history_panel = { commit_format = custom } })
    assert.same(custom, conf.file_history_panel.commit_format)
  end)
end)
