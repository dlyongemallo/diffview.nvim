local Diff2 = require("diffview.scene.layouts.diff_2").Diff2
local Diff2Ver = require("diffview.scene.layouts.diff_2_ver").Diff2Ver
local RevType = require("diffview.vcs.rev").RevType
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

-- See `Diff2HorPinned.should_null` for the rationale, including why the
-- synthetic top-of-history entry's a-side is routed back to `Diff2.should_null`.
---@override
---@param rev Rev
---@param status string
---@param sym Diff2.WindowSymbol
function Diff2VerPinned.should_null(rev, status, sym)
  if sym == "a" and rev.type == RevType.COMMIT and not rev.pin_local_synthetic then
    return status == "D"
  end

  return Diff2.should_null(rev, status, sym)
end

-- See `Diff2HorPinned:detach_files_for_swap` for the rationale.
---@override
---@param next_entry? FileEntry
function Diff2VerPinned:detach_files_for_swap(next_entry)
  if self.a then
    self.a:detach_file()
  end
  -- See `Diff2HorPinned:detach_files_for_swap` for the no-next-entry
  -- carve-out.
  if self.b and next_entry then
    local next_layout = next_entry.layout --[[@as Diff2VerPinned ]]
    local next_b = next_layout and next_layout.b and next_layout.b.file
    if next_b ~= self.b.file then
      self.b:detach_file()
    end
  end
end

M.Diff2VerPinned = Diff2VerPinned
return M
