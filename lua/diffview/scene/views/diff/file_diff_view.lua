local lazy = require("diffview.lazy")
local oop = require("diffview.oop")

local Diff2Hor = lazy.access("diffview.scene.layouts.diff_2_hor", "Diff2Hor") ---@type Diff2Hor|LazyModule
local FileEntry = lazy.access("diffview.scene.file_entry", "FileEntry") ---@type FileEntry|LazyModule
local NullDiffView = lazy.access("diffview.scene.views.diff.null_diff_view", "NullDiffView") ---@type NullDiffView|LazyModule
local NullRev = lazy.access("diffview.vcs.adapters.null.rev", "NullRev") ---@type NullRev|LazyModule
local RevType = lazy.access("diffview.vcs.rev", "RevType") ---@type RevType|LazyModule
local utils = lazy.require("diffview.utils") ---@module "diffview.utils"

local fmt = string.format
local pl = lazy.access(utils, "path") --[[@as PathLib ]]

local M = {}

---@class FileDiffView : NullDiffView
---@operator call : FileDiffView
---@field left_path string Absolute path to the left file.
---@field right_path string Absolute path to the right file.
local FileDiffView = oop.create_class("FileDiffView", NullDiffView.__get())

---FileDiffView constructor
---@param opt { adapter: NullAdapter, left_path: string, right_path: string }
function FileDiffView:init(opt)
  local left = NullRev(RevType.LOCAL)
  local right = NullRev(RevType.LOCAL)

  -- Let DiffView:init() handle standard setup (FileDict, FilePanel, events, etc.).
  self:super({
    adapter = opt.adapter,
    path_args = {},
    rev_arg = nil,
    left = left,
    right = right,
    options = {},
  })

  self.left_path = opt.left_path
  self.right_path = opt.right_path

  -- Update the panel header to show the file names.
  local left_name = pl:basename(self.left_path)
  local right_name = pl:basename(self.right_path)
  self.panel.rev_pretty_name = fmt("%s \u{2194} %s", left_name, right_name)

  -- Default to side-by-side: this is the most natural layout for comparing
  -- two arbitrary files. Users can cycle layouts at runtime with g<C-x>.
  local layout_class = Diff2Hor.__get()

  local entry = FileEntry.with_layout(layout_class, {
    adapter = self.adapter,
    path = self.right_path,
    oldpath = self.left_path,
    status = "M",
    kind = "working",
    revs = {
      a = left,
      b = right,
    },
  })

  self.files:set_working({ entry })
  self.files:update_file_trees()
end

-- `post_open`, `init_layout`, and `update_files` are inherited from
-- `NullDiffView` -- this view has no per-view scaffolding beyond the entry
-- construction in `init`.

M.FileDiffView = FileDiffView

return M
