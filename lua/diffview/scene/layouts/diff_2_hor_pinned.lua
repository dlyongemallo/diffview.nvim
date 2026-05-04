local Diff2 = require("diffview.scene.layouts.diff_2").Diff2
local Diff2Hor = require("diffview.scene.layouts.diff_2_hor").Diff2Hor
local RevType = require("diffview.vcs.rev").RevType
local oop = require("diffview.oop")

local M = {}

---@class Diff2HorPinned : Diff2Hor
---A horizontal Diff2 whose b-window pins to a working-tree LOCAL buffer
---across log navigation. Every pinned-mode `FileEntry` constructed by the
---adapter receives the same `vcs.File` instance for the b-side (resolved
---through `vcs.adapter.LayoutOpt.pinned_b_file_for` against the view's
---per-path cache), so the b-window's underlying buffer, edits, undo
---history, and cursor position survive every entry swap and refresh. The
---view is the sole owner of those `vcs.File` instances; entry teardown
---skips them via `shared_symbols`, and the view destroys them in `close()`.
local Diff2HorPinned = oop.create_class("Diff2HorPinned", Diff2Hor)

Diff2HorPinned.name = "diff2_horizontal_pinned"

-- The b-side `vcs.File` is owned by the FileHistoryView (its pin_local
-- cache), not by individual FileEntries. Listing "b" here keeps
-- `Layout:owned_files()` from returning it, so `FileEntry:destroy` and
-- `FileEntry:set_active` walk past the borrowed file. The view tears it
-- down in `close()` once.
Diff2HorPinned.shared_symbols = { "b" }

---@param opt Diff2.init.Opt
function Diff2HorPinned:init(opt)
  self:super(opt)
end

-- `Diff2.should_null` interprets `revs.a` as the *parent* of the commit, so
-- a fresh-add ("A") nulls the a-side. In pin_local mode `revs.a` IS the
-- commit, which means "A" implies the file exists on the a-side too. We
-- only null the a-side when the file is absent from the commit ("D").
-- The b-side is never constructed via `with_layout` in this mode (the view
-- supplies a pre-built `pinned_b_file`), so `try_should_null` never reaches
-- this code with `sym == "b"`; we leave the LOCAL/STAGE branches to the
-- parent.
--
-- The synthetic top-of-history "Working tree" entry is the exception: its
-- `revs.a` is HEAD (parent-of-working-tree), and its statuses come from
-- `diff HEAD`, so the standard parent-vs-child semantics apply. The adapter
-- tags that rev with `pin_local_synthetic`, which routes us back to
-- `Diff2.should_null` for the a-side as well.
---@override
---@param rev Rev
---@param status string
---@param sym Diff2.WindowSymbol
function Diff2HorPinned.should_null(rev, status, sym)
  if sym == "a" and rev.type == RevType.COMMIT and not rev.pin_local_synthetic then
    return status == "D"
  end

  return Diff2.should_null(rev, status, sym)
end

-- Within the FH view, skip detaching window b across entry swaps when the
-- next entry's b is the same `vcs.File` instance, so the pinned LOCAL
-- buffer's diffview keymaps and edits survive. In multi-file pinning a
-- row change can swap b to a different working-tree File (each path has
-- its own view-owned File); detach the old one in that case so its buffer
-- doesn't keep stale diffview state attached. The inherited
-- `detach_files()` still runs on tab-leave / view-close and detaches
-- everything (including b), so we don't leak diffview state into the
-- user's normal editing windows.
---@override
---@param next_entry? FileEntry
function Diff2HorPinned:detach_files_for_swap(next_entry)
  if self.a then
    self.a:detach_file()
  end
  if self.b and next_entry then
    -- Without a next entry we have no comparison; preserve the old
    -- "skip detach" behaviour for callers that haven't migrated to the
    -- new signature.
    local next_layout = next_entry.layout --[[@as Diff2HorPinned ]]
    local next_b = next_layout and next_layout.b and next_layout.b.file
    if next_b ~= self.b.file then
      self.b:detach_file()
    end
  end
end

M.Diff2HorPinned = Diff2HorPinned
return M
