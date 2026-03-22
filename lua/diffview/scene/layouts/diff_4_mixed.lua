local async = require("diffview.async")
local Diff4 = require("diffview.scene.layouts.diff_4").Diff4
local oop = require("diffview.oop")

local M = {}

---@class Diff4Mixed : Diff4
local Diff4Mixed = oop.create_class("Diff4Mixed", Diff4)

Diff4Mixed.name = "diff4_mixed"

function Diff4Mixed:init(opt)
  self:super(opt)
end

---@override
---@param self Diff4Mixed
---@param pivot integer?
Diff4Mixed.create = async.void(function(self, pivot)
  self:create_wins(pivot, {
    { "b", "belowright sp" },
    { "a", "aboveleft vsp" },
    { "d", "aboveleft vsp" },
    { "c", "aboveleft vsp" },
  }, { "a", "b", "c", "d" })
end)

M.Diff4Mixed = Diff4Mixed
return M
