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
---skips them via `shared_symbols`, and `Layout:detach_files_for_swap`
---reads the same set to keep the b-window attached unless the next
---entry's b is a different `vcs.File` (multi-file pinning crossing rows).
---The view destroys the cached b-file in `close()`.
local Diff2HorPinned = oop.create_class("Diff2HorPinned", Diff2Hor)

Diff2HorPinned.name = "diff2_horizontal_pinned"

Diff2HorPinned.shared_symbols = { "b" }

---@param opt Diff2.init.Opt
function Diff2HorPinned:init(opt)
  self:super(opt)
end

-- `Diff2.should_null` interprets `revs.a` as the *parent* of the commit, so
-- a fresh-add ("A") nulls the a-side. In pin_local mode `revs.a` IS the
-- commit, which means "A" implies the file exists on the a-side too. We
-- only null the a-side when the file is absent from the commit ("D").
-- The b-side normally reuses the view-owned `pinned_b_file`; `with_layout`
-- only consults this predicate for `sym == "b"` to decide whether to fall
-- back to a one-off nulled file when the LOCAL path is missing on disk.
-- We leave the LOCAL/STAGE branches to the parent for that case.
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

M.Diff2HorPinned = Diff2HorPinned
return M
