local async = require("diffview.async")
local Diff2 = require("diffview.scene.layouts.diff_2").Diff2
local oop = require("diffview.oop")

local M = {}

---@class Diff2Ver : Diff2
local Diff2Ver = oop.create_class("Diff2Ver", Diff2)

Diff2Ver.name = "diff2_vertical"

---@param opt Diff2.init.Opt
function Diff2Ver:init(opt)
  self:super(opt)
end

---@override
---@param self Diff2Ver
---@param pivot integer?
Diff2Ver.create = async.void(function(self, pivot)
  self:create_wins(pivot, {
    { "a", "aboveleft sp" },
    { "b", "aboveleft sp" },
  }, { "a", "b" })
end)

M.Diff2Ver = Diff2Ver
return M
