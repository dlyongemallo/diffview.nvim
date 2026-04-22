local lazy = require("diffview.lazy")
local oop = require("diffview.oop")

local Diff2Hor = lazy.access("diffview.scene.layouts.diff_2_hor", "Diff2Hor") ---@type Diff2Hor|LazyModule
local DiffView = lazy.access("diffview.scene.views.diff.diff_view", "DiffView") ---@type DiffView|LazyModule
local FileEntry = lazy.access("diffview.scene.file_entry", "FileEntry") ---@type FileEntry|LazyModule
local NullRev = lazy.access("diffview.vcs.adapters.null.rev", "NullRev") ---@type NullRev|LazyModule
local RevType = lazy.access("diffview.vcs.rev", "RevType") ---@type RevType|LazyModule
local utils = lazy.require("diffview.utils") ---@module "diffview.utils"

local fmt = string.format
local pl = lazy.access(utils, "path") ---@type PathLib

local M = {}

---@class FileDiffView : DiffView
---@operator call : FileDiffView
---@field left_path string Absolute path to the left file.
---@field right_path string Absolute path to the right file.
local FileDiffView = oop.create_class("FileDiffView", DiffView.__get())

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

---@override
function FileDiffView:post_open()
  vim.cmd("redraw")

  self:init_event_listeners()

  -- Create the commit log panel (required by close() and by some listeners).
  local CommitLogPanel = require("diffview.ui.panels.commit_log_panel").CommitLogPanel
  self.commit_log_panel = CommitLogPanel(self, self.adapter, {
    name = fmt("diffview://%s/log/%d/%s", self.adapter.ctx.dir, self.tabpage, "commit_log"),
  })

  -- No index watcher needed for arbitrary file diffs.

  vim.schedule(function()
    self:file_safeguard()
    self.is_loading = false
    self.panel.is_loading = false
    self.panel:render()
    self.panel:redraw()

    -- Open the first (only) file entry.
    local files = self.panel:ordered_file_list()
    if files and files[1] then
      self:set_file(files[1], false, true)
    end

    self.ready = true
  end)
end

---@override
---Hide the file panel: it has no useful VCS information for file diffs.
function FileDiffView:init_layout()
  local curwin = vim.api.nvim_get_current_win()

  self:use_layout(FileDiffView.get_temp_layout())
  self.cur_layout:create()

  if not vim.t[self.tabpage].diffview_view_initialized then
    vim.api.nvim_win_close(curwin, false)
    vim.t[self.tabpage].diffview_view_initialized = true
  end

  -- Never show the file panel for file diffs.
  self.panel:focus(true)
  self.emitter:emit("post_layout")
end

---@override
---No-op: file list is static for arbitrary file diffs.
function FileDiffView:update_files() end

M.FileDiffView = FileDiffView

return M
