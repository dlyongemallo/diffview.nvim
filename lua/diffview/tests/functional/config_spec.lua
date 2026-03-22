local config = require("diffview.config")
local utils = require("diffview.utils")

describe("diffview.config", function()
  it("validates rename_threshold", function()
    local original = vim.deepcopy(config.get_config())
    local old_warn = utils.warn
    utils.warn = function() end

    local ok, err = pcall(function()
      config.setup({ rename_threshold = "40" })
      assert.equals(40, config.get_config().rename_threshold)

      config.setup({ rename_threshold = 101 })
      assert.is_nil(config.get_config().rename_threshold)

      config.setup({ rename_threshold = 12.5 })
      assert.is_nil(config.get_config().rename_threshold)
    end)

    utils.warn = old_warn
    config.setup(original)

    if not ok then error(err) end
  end)
end)

describe("diffview.config default keymaps", function()
  ---Search a keymap table for an entry with the given lhs binding.
  local function find_keymap(keymaps, lhs)
    for _, km in ipairs(keymaps) do
      if km[2] == lhs then return km end
    end
    return nil
  end

  it("shared nav keymaps appear in view section", function()
    local keymaps = config.defaults.keymaps
    -- <tab> is a common nav keymap that should be in view.
    assert.truthy(find_keymap(keymaps.view, "<tab>"))
    assert.truthy(find_keymap(keymaps.view, "gf"))
    assert.truthy(find_keymap(keymaps.view, "<leader>e"))
  end)

  it("shared nav keymaps appear in file_panel section", function()
    local keymaps = config.defaults.keymaps
    assert.truthy(find_keymap(keymaps.file_panel, "<tab>"))
    assert.truthy(find_keymap(keymaps.file_panel, "gf"))
    assert.truthy(find_keymap(keymaps.file_panel, "<leader>b"))
  end)

  it("shared nav keymaps appear in file_history_panel section", function()
    local keymaps = config.defaults.keymaps
    assert.truthy(find_keymap(keymaps.file_history_panel, "<tab>"))
    assert.truthy(find_keymap(keymaps.file_history_panel, "gf"))
    assert.truthy(find_keymap(keymaps.file_history_panel, "<leader>e"))
  end)

  it("shared panel keymaps appear in both panel sections", function()
    local keymaps = config.defaults.keymaps
    -- j, <cr>, zo are common panel keymaps.
    for _, lhs in ipairs({ "j", "<cr>", "zo", "zM" }) do
      assert.truthy(find_keymap(keymaps.file_panel, lhs), "file_panel missing " .. lhs)
      assert.truthy(find_keymap(keymaps.file_history_panel, lhs), "file_history_panel missing " .. lhs)
    end
  end)

  it("section-specific keymaps are not leaked to other sections", function()
    local keymaps = config.defaults.keymaps
    -- "s" (stage) is file_panel-only.
    assert.truthy(find_keymap(keymaps.file_panel, "s"))
    assert.falsy(find_keymap(keymaps.file_history_panel, "s"))

    -- "g!" (options) is file_history_panel-only.
    assert.truthy(find_keymap(keymaps.file_history_panel, "g!"))
    assert.falsy(find_keymap(keymaps.file_panel, "g!"))
  end)

  it("view section still contains conflict keymaps", function()
    local keymaps = config.defaults.keymaps
    assert.truthy(find_keymap(keymaps.view, "<leader>co"))
    assert.truthy(find_keymap(keymaps.view, "dx"))
  end)
end)
