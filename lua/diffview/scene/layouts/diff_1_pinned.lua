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

-- Mirror `Diff2HorPinned:detach_files_for_swap`: skip detaching window b
-- when the next entry's b is the same `vcs.File` instance so the pinned
-- LOCAL buffer's diffview keymaps and edits survive the swap. In
-- multi-file pinning a row change can swap b to a different working-tree
-- File (each path has its own view-owned File); detach the old one in
-- that case so its buffer doesn't keep stale diffview state attached.
-- The inherited `detach_files()` still runs on tab-leave / view-close.
---@override
---@param next_entry? FileEntry
function Diff1Pinned:detach_files_for_swap(next_entry)
  -- Without a next entry we have no comparison; preserve the old
  -- "skip detach" behaviour for callers that haven't migrated to the
  -- new signature.
  if self.b and next_entry then
    local next_layout = next_entry.layout --[[@as Diff1Pinned ]]
    local next_b = next_layout and next_layout.b and next_layout.b.file
    if next_b ~= self.b.file then
      self.b:detach_file()
    end
  end
end

M.Diff1Pinned = Diff1Pinned
return M
