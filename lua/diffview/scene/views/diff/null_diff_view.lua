local lazy = require("diffview.lazy")
local oop = require("diffview.oop")

local DiffView = lazy.access("diffview.scene.views.diff.diff_view", "DiffView") ---@type DiffView|LazyModule

local fmt = string.format

local M = {}

---`NullDiffView` is the shared base for diff views that don't query a VCS:
---the file list is static, every buffer source comes from disk (via
---`RevType.LOCAL` for editable sides or `RevType.CUSTOM` + a `get_data`
---reader for read-only ones), and the adapter is a `NullAdapter`. The
---concrete subclasses (`FileDiffView`, `FileMergeView`, `FileDirDiffView`)
---only differ in how they shape the initial `FileEntry` list inside their
---own `init`; the rest of the lifecycle is consolidated here.
---
---Subclasses are expected to:
---  * Call `self:super(opt)` with the standard `DiffView` opts (no rev arg,
---    no path args, an adapter that's a `NullAdapter`).
---  * Populate `self.files` (working / conflicting / staged buckets) before
---    returning from `init`. `post_open` reads the panel's ordered file
---    list and focuses the first entry.
---  * Override `init_layout` only if they need the file panel visible. The
---    default hides the panel (a one-entry view has nothing useful to show
---    there); `FileDirDiffView` overrides to keep it because its list has
---    N entries.
---@class NullDiffView : DiffView
---@operator call : NullDiffView
local NullDiffView = oop.create_class("NullDiffView", DiffView.__get())

---@param opt table # Forwarded verbatim to `DiffView:init`.
function NullDiffView:init(opt)
  -- Explicit super-call required even though we add no behaviour: the OOP
  -- system's `super` chain walks `__init_caller.super_class`, so a missing
  -- `init` on this layer would cause `DiffView:init`'s own `self:super(...)`
  -- to resolve back to `DiffView` (and call it twice with the wrong opts).
  self:super(opt)
end

---Read a file from disk into a list of lines. Returns an empty table when
---the path is missing — external diff/merge drivers (jj, git mergetool, ...)
---can hand us `/dev/null`-style paths for add/delete sides, and a missing
---input should render as an empty buffer rather than error.
---@param path string
---@return string[]
function NullDiffView.read_lines(path)
  if vim.fn.filereadable(path) ~= 1 then
    return {}
  end
  return vim.fn.readfile(path)
end

---@override
---Common post-open scaffolding for static-file-list views:
---  * Force a redraw so the temp layout doesn't linger.
---  * Wire up event listeners.
---  * Create the `CommitLogPanel` that `DiffView:close` and a few listeners
---    expect to exist (even though there's no commit log for these views).
---  * Schedule the loading-state teardown + focus the first entry.
function NullDiffView:post_open()
  vim.cmd("redraw")

  self:init_event_listeners()

  local CommitLogPanel = require("diffview.ui.panels.commit_log_panel").CommitLogPanel
  self.commit_log_panel = CommitLogPanel(self, self.adapter, {
    name = fmt("diffview://%s/log/%d/%s", self.adapter.ctx.dir, self.tabpage, "commit_log"),
  })

  vim.schedule(function()
    self:file_safeguard()
    self.is_loading = false
    self.panel.is_loading = false
    self.panel:render()
    self.panel:redraw()

    local files = self.panel:ordered_file_list()
    if files and files[1] then
      self:set_file(files[1], false, true)
    end

    self.ready = true
  end)
end

---@override
---Hide the file panel: a single-entry view has no useful VCS metadata to
---surface there. Subclasses with N entries (e.g. `FileDirDiffView`)
---override this to fall back to `StandardView:init_layout`.
function NullDiffView:init_layout()
  local curwin = vim.api.nvim_get_current_win()

  self:use_layout(NullDiffView.get_temp_layout())
  self.cur_layout:create()

  if not vim.t[self.tabpage].diffview_view_initialized then
    vim.api.nvim_win_close(curwin, false)
    vim.t[self.tabpage].diffview_view_initialized = true
  end

  self.panel:focus(true)
  self.emitter:emit("post_layout")
end

---@override
---No-op: the file list is static; there is no VCS state to re-query.
function NullDiffView:update_files() end

M.NullDiffView = NullDiffView

return M
