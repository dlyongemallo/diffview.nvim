local config = require("diffview.config")
local hl = require("diffview.hl")

-- Helper: run setup() with the given overrides and return the live config.
local function setup_with(overrides)
  config.setup(overrides or {})
  return config.get_config()
end

describe("always_show_sections", function()
  local original

  before_each(function()
    original = vim.deepcopy(config.get_config())
  end)

  after_each(function()
    config.setup(original)
  end)

  it("defaults to false", function()
    local conf = setup_with({})
    assert.is_false(conf.file_panel.always_show_sections)
  end)

  it("survives setup() when set to true", function()
    local conf = setup_with({ file_panel = { always_show_sections = true } })
    assert.is_true(conf.file_panel.always_show_sections)
  end)
end)

describe("auto_close_on_empty", function()
  local original

  before_each(function()
    original = vim.deepcopy(config.get_config())
  end)

  after_each(function()
    config.setup(original)
  end)

  it("defaults to false", function()
    local conf = setup_with({})
    assert.is_false(conf.auto_close_on_empty)
  end)

  it("survives setup() when set to true", function()
    local conf = setup_with({ auto_close_on_empty = true })
    assert.is_true(conf.auto_close_on_empty)
  end)
end)

describe("commit_subject_max_length", function()
  local original

  before_each(function()
    original = vim.deepcopy(config.get_config())
  end)

  after_each(function()
    config.setup(original)
  end)

  it("defaults to 72", function()
    local conf = setup_with({})
    assert.equals(72, conf.file_history_panel.commit_subject_max_length)
  end)

  it("survives setup() with a custom value", function()
    local conf = setup_with({ file_history_panel = { commit_subject_max_length = 50 } })
    assert.equals(50, conf.file_history_panel.commit_subject_max_length)
  end)
end)

describe("status_icons", function()
  local original

  before_each(function()
    original = vim.deepcopy(config.get_config())
  end)

  after_each(function()
    config.setup(original)
  end)

  it("default table contains expected status keys", function()
    local conf = setup_with({})
    local expected_keys = { "A", "?", "M", "R", "C", "T", "U", "X", "D", "B", "!" }
    for _, key in ipairs(expected_keys) do
      assert.not_nil(conf.status_icons[key], "missing status_icons key: " .. key)
    end
  end)

  it("hl.get_status_icon() returns the configured icon for a known status", function()
    setup_with({ status_icons = { ["M"] = "~" } })
    assert.equals("~", hl.get_status_icon("M"))
  end)

  it("hl.get_status_icon() falls back to the raw status letter for unknown statuses", function()
    setup_with({})
    assert.equals("Z", hl.get_status_icon("Z"))
  end)
end)
