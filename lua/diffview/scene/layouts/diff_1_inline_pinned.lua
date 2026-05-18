local Diff1Inline = require("diffview.scene.layouts.diff_1_inline").Diff1Inline
local Diff1Pinned = require("diffview.scene.layouts.diff_1_pinned").Diff1Pinned
local oop = require("diffview.oop")

local M = {}

---@class Diff1InlinePinned : Diff1Inline
---Inline variant of `Diff1Pinned`: renders the diff inline against the
---view's shared working-tree b-file. The b-side `vcs.File` is owned by the
---FileHistoryView (its pin_local cache); `shared_symbols = { "b" }` keeps
---`Layout:owned_files()` from returning it, so `FileEntry:destroy` won't
---tear it down. The view destroys the cached b-file once in `close()`.
---Inherits the rest of `Diff1Inline`'s rendering and `Diff1Pinned`'s
---`detach_files_for_swap` semantics.
local Diff1InlinePinned = oop.create_class("Diff1InlinePinned", Diff1Inline)

Diff1InlinePinned.name = "diff1_inline_pinned"
Diff1InlinePinned.shared_symbols = { "b" }

---@param opt Diff1Inline.init.Opt
function Diff1InlinePinned:init(opt)
  self:super(opt)
end

Diff1InlinePinned.detach_files_for_swap = Diff1Pinned.detach_files_for_swap

M.Diff1InlinePinned = Diff1InlinePinned
return M
