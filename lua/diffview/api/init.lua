-- Public API surface for diffview.nvim.
--
-- Usage:
--   local api = require("diffview.api")
--   api.selections.get()

local lazy = require("diffview.lazy")

local M = {}

M.selections = lazy.require("diffview.api.selections") ---@module "diffview.api.selections"

return M
