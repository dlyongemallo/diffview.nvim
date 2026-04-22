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

describe("mark_placement", function()
  local original

  before_each(function()
    original = vim.deepcopy(config.get_config())
  end)

  after_each(function()
    config.setup(original)
  end)

  it("defaults to 'inline'", function()
    local conf = setup_with({})
    assert.equals("inline", conf.file_panel.mark_placement)
  end)

  it("survives setup() when set to 'sign_column'", function()
    local conf = setup_with({ file_panel = { mark_placement = "sign_column" } })
    assert.equals("sign_column", conf.file_panel.mark_placement)
  end)
end)

describe("view.inline.style", function()
  local original
  local utils = require("diffview.utils")
  local orig_err
  local orig_warn

  before_each(function()
    original = vim.deepcopy(config.get_config())
    orig_err = utils.err
    orig_warn = utils.warn
    utils.err = function() end
    utils.warn = function() end
  end)

  after_each(function()
    config.setup(original)
    utils.err = orig_err
    utils.warn = orig_warn
  end)

  it("defaults to 'unified'", function()
    local conf = setup_with({})
    assert.equals("unified", conf.view.inline.style)
  end)

  it("accepts 'overleaf'", function()
    local conf = setup_with({ view = { inline = { style = "overleaf" } } })
    assert.equals("overleaf", conf.view.inline.style)
  end)

  it("rejects unknown values and falls back to 'unified'", function()
    local conf = setup_with({ view = { inline = { style = "bogus" } } })
    assert.equals("unified", conf.view.inline.style)
  end)

  it("treats omitted style (e.g. view.inline = {}) as 'use default'", function()
    local err_called = false
    utils.err = function()
      err_called = true
    end

    local conf = setup_with({ view = { inline = {} } })

    assert.equals("unified", conf.view.inline.style)
    assert.is_false(err_called, "omitting style should not produce a validation error")
  end)

  it("warns and falls back when view.inline is a non-table value", function()
    local warned = false
    utils.warn = function()
      warned = true
    end

    -- A truthy non-table (e.g. user typo'd `view.inline = "overleaf"`) would
    -- crash on `view.inline.style` without the type guard.
    local conf = setup_with({ view = { inline = "overleaf" } })

    assert.is_true(warned, "expected a warning about non-table view.inline")
    assert.equals("unified", conf.view.inline.style)
  end)
end)
