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
