local Diff2HorPinned = require("diffview.scene.layouts.diff_2_hor_pinned").Diff2HorPinned
local Diff2Ver = require("diffview.scene.layouts.diff_2_ver").Diff2Ver
local oop = require("diffview.oop")

local M = {}

---@class Diff2VerPinned : Diff2Ver
---Vertical sibling of `Diff2HorPinned`. See that class for the pinning
---semantics; the only difference here is window orientation.
local Diff2VerPinned = oop.create_class("Diff2VerPinned", Diff2Ver)

Diff2VerPinned.name = "diff2_vertical_pinned"

Diff2VerPinned.shared_symbols = { "b" }

---@param opt Diff2.init.Opt
function Diff2VerPinned:init(opt)
  self:super(opt)
end

-- Identical to `Diff2HorPinned.should_null`; the override is orientation-
-- independent, so we just alias the function pointer to keep one source
-- of truth.
Diff2VerPinned.should_null = Diff2HorPinned.should_null

M.Diff2VerPinned = Diff2VerPinned
return M
