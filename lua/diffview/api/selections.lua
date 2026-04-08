-- Public API for programmatic file selection manipulation.
--
-- All functions support an optional view override: simple query functions
-- take it as a positional `view` parameter, while functions that also
-- accept a `path`/`paths` argument take it as `opts.view`. When omitted
-- the current view is used (via `lib.get_current_view()`). When a view is
-- supplied it must be a DiffView instance (the only view type that has a
-- file panel with selections).

local lazy = require("diffview.lazy")

local lib = lazy.require("diffview.lib") ---@module "diffview.lib"

local M = {}

---Resolve the view to operate on.
---@param view View?
---@return DiffView?
local function resolve_view(view)
  if view then return view end
  return lib.get_current_view()
end

---Return the panel from the given view, or nil if the view is not a DiffView.
---@param view View?
---@return FilePanel?
local function get_panel(view)
  view = resolve_view(view)
  if not view then return nil end
  -- Only DiffView has a file panel with selections.
  if not view.panel or not view.panel.selected_files then return nil end
  return view.panel
end

---Get all currently selected files.
---
---Returns a list of tables with `path` and `kind` fields.
---@param view View? View to query (defaults to current view).
---@return { path: string, kind: vcs.FileKind }[]
function M.get(view)
  local panel = get_panel(view)
  if not panel then return {} end
  local result = {}
  for _, file in ipairs(panel:get_selected_files()) do
    result[#result + 1] = { path = file.path, kind = file.kind }
  end
  return result
end

---Get just the paths of all currently selected files.
---@param view View? View to query (defaults to current view).
---@return string[]
function M.get_paths(view)
  local panel = get_panel(view)
  if not panel then return {} end
  local result = {}
  for _, file in ipairs(panel:get_selected_files()) do
    result[#result + 1] = file.path
  end
  return result
end

---Check whether a file is selected.
---@param path string File path relative to the VCS root (repo-relative).
---@param opts? { kind?: vcs.FileKind, view?: View }
---@return boolean
function M.is_selected(path, opts)
  opts = opts or {}
  local panel = get_panel(opts.view)
  if not panel then return false end
  -- A file may appear under multiple kinds (e.g. working + staged).
  -- Return true if *any* matching entry is selected.
  for _, file in panel.files:iter() do
    if file.path == path and (opts.kind == nil or file.kind == opts.kind) then
      if panel:is_selected(file) then
        return true
      end
    end
  end
  return false
end

---Select files by path. Paths that do not match any file entry are ignored.
---@param paths string[] Paths to select (relative to VCS root).
---@param opts? { kind?: vcs.FileKind, view?: View }
function M.select(paths, opts)
  opts = opts or {}
  local panel = get_panel(opts.view)
  if not panel then return end
  local path_set = {}
  for _, p in ipairs(paths) do
    path_set[p] = true
  end
  panel:batch_selection(function()
    for _, file in panel.files:iter() do
      if path_set[file.path] and (opts.kind == nil or file.kind == opts.kind) then
        if not panel:is_selected(file) then
          panel:select_file(file)
        end
      end
    end
  end)
end

---Deselect files by path. Paths that do not match any file entry are ignored.
---@param paths string[] Paths to deselect (relative to VCS root).
---@param opts? { kind?: vcs.FileKind, view?: View }
function M.deselect(paths, opts)
  opts = opts or {}
  local panel = get_panel(opts.view)
  if not panel then return end
  local path_set = {}
  for _, p in ipairs(paths) do
    path_set[p] = true
  end
  panel:batch_selection(function()
    for _, file in panel.files:iter() do
      if path_set[file.path] and (opts.kind == nil or file.kind == opts.kind) then
        if panel:is_selected(file) then
          panel:deselect_file(file)
        end
      end
    end
  end)
end

---Replace the selection set for the targeted files. Only the given paths
---will be selected afterwards. When `opts.kind` is provided, this applies
---only to files of that kind; files of other kinds keep their current
---selection state.
---@param paths string[] Paths that should be selected (relative to VCS root).
---@param opts? { kind?: vcs.FileKind, view?: View }
function M.set(paths, opts)
  opts = opts or {}
  local panel = get_panel(opts.view)
  if not panel then return end
  local path_set = {}
  for _, p in ipairs(paths) do
    path_set[p] = true
  end
  panel:batch_selection(function()
    for _, file in panel.files:iter() do
      -- When a kind filter is active, skip files of other kinds entirely.
      if opts.kind and file.kind ~= opts.kind then
        goto continue
      end
      local want = path_set[file.path] ~= nil
      local have = panel:is_selected(file)
      if want and not have then
        panel:select_file(file)
      elseif not want and have then
        panel:deselect_file(file)
      end
      ::continue::
    end
  end)
end

---Clear all selections.
---@param view View? View to operate on (defaults to current view).
function M.clear(view)
  local panel = get_panel(view)
  if not panel then return end
  panel:clear_selections()
end

---Return true when at least one file is selected.
---@param view View? View to query (defaults to current view).
---@return boolean
function M.any(view)
  local panel = get_panel(view)
  if not panel then return false end
  return panel:has_any_selections()
end

---Return the total number of selected files.
---@param view View? View to query (defaults to current view).
---@return integer
function M.count(view)
  local panel = get_panel(view)
  if not panel then return 0 end
  return #panel:get_selected_files()
end

return M
