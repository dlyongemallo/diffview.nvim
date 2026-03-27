local async = require("diffview.async")
local Diff2 = require("diffview.scene.layouts.diff_2").Diff2
local oop = require("diffview.oop")

local await = async.await

local M = {}

---@class Diff2Hor : Diff2
local Diff2Hor = oop.create_class("Diff2Hor", Diff2)

Diff2Hor.name = "diff2_horizontal"

---@param opt Diff2.init.Opt
function Diff2Hor:init(opt)
  self:super(opt)
end

---@override
---@param self Diff2Hor
---@param pivot integer?
Diff2Hor.create = async.void(function(self, pivot)
  await(self:create_wins(pivot, {
    { "a", "aboveleft vsp" },
    { "b", "aboveleft vsp" },
  }, { "a", "b" }))
end)

M.Diff2Hor = Diff2Hor
return M
