local async = require("diffview.async")
local Diff3 = require("diffview.scene.layouts.diff_3").Diff3
local oop = require("diffview.oop")

local await = async.await

local M = {}

---@class Diff3Hor : Diff3
local Diff3Hor = oop.create_class("Diff3Hor", Diff3)

Diff3Hor.name = "diff3_horizontal"

function Diff3Hor:init(opt)
  self:super(opt)
end

---@override
---@param self Diff3Hor
---@param pivot integer?
Diff3Hor.create = async.void(function(self, pivot)
  await(self:create_wins(pivot, {
    { "a", "aboveleft vsp" },
    { "b", "aboveleft vsp" },
    { "c", "aboveleft vsp" },
  }, { "a", "b", "c" }))
end)

M.Diff3Hor = Diff3Hor
return M
