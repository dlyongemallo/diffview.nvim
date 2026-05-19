local Diff1 = require("diffview.scene.layouts.diff_1").Diff1
local Layout = require("diffview.scene.layout").Layout
local oop = require("diffview.oop")

local M = {}

---Single-window layout that shows the file as a plain (non-diff) buffer. Used
---by `view.single_pane_for_one_sided` when a file's diff would be one-sided
---(status `A`/`?` or `D`). Window opts disabling `diff`, `scrollbind`, and
---diff folding are merged in by `StandardView` via the `diff1_raw` winopts
---key; the layout itself just wires the single `b` window.
---@class Diff1Raw : Diff1
---@field a_file vcs.File? Old-side file kept for ownership / `convert_layout` round-tripping; never windowed.
---@field _b_substituted boolean True when `b`'s `vcs.File` was rewritten to point at `revs.a` (status `D` round-trip) so `convert_layout` doesn't promote the wrong-rev file back into a Diff2.
local Diff1Raw = oop.create_class("Diff1Raw", Diff1)

---@class Diff1Raw.init.Opt : Diff1.init.Opt
---@field a vcs.File? Unwindowed a-side file (constructed by `FileEntry.with_layout`).
---@field b_substituted? boolean When true, `b.file.rev` is `revs.a`, not `revs.b`; `get_file_for("b")` then returns nil so conversion rebuilds a natural b-side.

Diff1Raw.name = "diff1_raw"
Diff1Raw.symbols = { "b" }

---@param opt Diff1Raw.init.Opt
function Diff1Raw:init(opt)
  self:super(opt)
  self.a_file = opt and opt.a or nil
  if self.a_file then
    self.a_file.symbol = "a"
  end
  self._b_substituted = opt and opt.b_substituted or false
end

---@override
---@return Diff1Raw
function Diff1Raw:clone()
  local clone = Layout.clone(self) --[[@as Diff1Raw ]]
  clone.a_file = self.a_file
  clone._b_substituted = self._b_substituted
  return clone
end

---@override
---The single `b` window always holds the side with content (either the
---natural `b` rev for additions, or the substituted `a` rev for deletions),
---so it is never nulled at this layer. The selection logic in
---`FileEntry.with_layout` is the gatekeeper for when `Diff1Raw` is chosen.
---@param rev Rev
---@param status string
---@param sym Diff1.WindowSymbol
---@diagnostic disable-next-line: unused-local
function Diff1Raw.should_null(rev, status, sym)
  assert(sym == "b")
  return false
end

---@override
---Expose `a_file` so `FileEntry:destroy` tears it down alongside the windowed
---`b`. Same pattern as `Diff1Inline`.
---@return vcs.File[]
function Diff1Raw:owned_files()
  local out = Layout.owned_files(self)
  if self.a_file and not vim.tbl_contains(out, self.a_file) then
    out[#out + 1] = self.a_file
  end
  return out
end

---@override
---Expose `a_file` under the `"a"` slot so `convert_layout` reuses it when
---transitioning to a 2-way layout. For `"b"`, return nil when the windowed
---file was rewritten (status `D` substitution) so conversion rebuilds the
---natural b-side via `try_should_null`; otherwise defer to the base.
---@param sym string
---@return vcs.File?
function Diff1Raw:get_file_for(sym)
  if sym == "a" then
    return self.a_file
  end
  if sym == "b" and self._b_substituted then
    return nil
  end
  return Layout.get_file_for(self, sym)
end

M.Diff1Raw = Diff1Raw
return M
