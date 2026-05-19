local Diff1 = require("diffview.scene.layouts.diff_1").Diff1
local oop = require("diffview.oop")

local M = {}

---@class Diff1Pinned : Diff1
---A single-window Diff1 whose b-window pins to a working-tree LOCAL buffer
---across log navigation. The b-side `vcs.File` is owned by the
---FileHistoryView (its pin_local cache), not by individual FileEntries.
---Listing "b" in `shared_symbols` keeps `Layout:owned_files()` from
---returning it, so `FileEntry:destroy` and `FileEntry:set_active` walk past
---the borrowed file. The view tears it down in `close()` once.
local Diff1Pinned = oop.create_class("Diff1Pinned", Diff1)

Diff1Pinned.name = "diff1_plain_pinned"
Diff1Pinned.shared_symbols = { "b" }

---@param opt Diff1.init.Opt
function Diff1Pinned:init(opt)
  self:super(opt)
end

M.Diff1Pinned = Diff1Pinned
return M
