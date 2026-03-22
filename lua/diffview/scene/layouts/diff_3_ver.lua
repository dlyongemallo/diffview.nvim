local async = require("diffview.async")
local Diff3 = require("diffview.scene.layouts.diff_3").Diff3
local oop = require("diffview.oop")

local await = async.await

local M = {}

---@class Diff3Ver : Diff3
local Diff3Ver = oop.create_class("Diff3Ver", Diff3)

Diff3Ver.name = "diff3_vertical"

function Diff3Ver:init(opt)
  self:super(opt)
end

---@override
---@param self Diff3Ver
---@param pivot integer?
Diff3Ver.create = async.void(function(self, pivot)
  await(self:create_wins(pivot, {
    { "a", "aboveleft sp" },
    { "b", "aboveleft sp" },
    { "c", "aboveleft sp" },
  }, { "a", "b", "c" }))
end)

M.Diff3Ver = Diff3Ver
return M
