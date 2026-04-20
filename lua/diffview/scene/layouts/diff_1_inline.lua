local async = require("diffview.async")
local debounce = require("diffview.debounce")
local lazy = require("diffview.lazy")
local Diff1 = require("diffview.scene.layouts.diff_1").Diff1
local Layout = require("diffview.scene.layout").Layout

local await, pawait = async.await, async.pawait
local oop = require("diffview.oop")

local config = lazy.require("diffview.config") ---@module "diffview.config"
local inline_diff = lazy.require("diffview.scene.inline_diff") ---@module "diffview.scene.inline_diff"

local api = vim.api
local M = {}

---Parse the currently-effective `vim.opt.diffopt` (after Diffview's
---`apply_diffopt` has merged any `view.diffopt` overrides) into the subset of
---options the inline renderer cares about. Reading the global option means the
---inline view honours both the user's existing `'diffopt'` and the per-view
---overrides applied by `scene/view.lua:apply_diffopt`.
---
---`indent_heuristic` is always set to an explicit boolean so its absence from
---`'diffopt'` forces `vim.diff` to disable the heuristic instead of falling
---back to whatever default the vim.diff implementation currently uses.
---
---`linematch` is intentionally not forwarded. In `result_type = "indices"`
---mode it splits a single modify-hunk into smaller hunks that pair lines by
---similarity rather than by position — e.g. an old `-- foo = X, -- comment`
---line gets paired with a new `-- bar = Y, -- comment` line further down
---because both share the `-- ` prefix and a `, -- ` separator, even though
---the natural (positional) pair is the new uncommented `foo = X` line. The
---inline renderer pairs lines positionally inside each hunk, so a non-zero
---linematch causes deletions to render anchored against the wrong new line.
---@return InlineDiffOpts
local function effective_diffopt()
  local out = { indent_heuristic = false }
  for _, v in ipairs(vim.opt.diffopt:get()) do
    local key, val = v:match("^([%w_-]+):(.+)$")
    if key == "algorithm" then
      out.algorithm = val
    elseif v == "indent-heuristic" then
      out.indent_heuristic = true
    elseif v == "iwhite" then
      out.ignore_whitespace_change = true
    elseif v == "iwhiteall" then
      out.ignore_whitespace = true
    elseif v == "iwhiteeol" then
      out.ignore_whitespace_change_at_eol = true
    elseif v == "iblank" then
      out.ignore_blank_lines = true
    end
  end
  return out
end

---The autocmd group for buffer-local repaint hooks. Shared across all
---Diff1Inline instances; individual buffers are cleaned up by clearing
---autocmds scoped to `{ group = ..., buffer = bufnr }`.
local repaint_augroup = api.nvim_create_augroup("diffview_inline_repaint", { clear = false })

---Debounce delay (ms) for `TextChangedI`-driven repaints. Long enough to
---coalesce bursts of keystrokes into a single diff pass, short enough that
---the deletion markers feel responsive while the user is still typing.
local INSERT_REPAINT_DEBOUNCE_MS = 150

---@class Diff1Inline : Diff1
---@field a_file vcs.File? Old-side file used only to compute the diff (never rendered in a window).
---@field _cached_old_lines string[]? Old-side content captured on first render; reused by repaints so each keystroke-level refresh doesn't re-fetch from disk.
---@field _repaint_bufnr integer? Buffer id the repaint autocmds are attached to (nil when no autocmds are installed).
---@field _repaint_debounced CancellableFn? Trailing-edge debounced `_repaint` used for the insert-mode `TextChangedI` hook.
---@field _suppress_repaint boolean? Set by batched buffer edits (e.g. a multi-hunk `diffget`) to turn `_repaint` into a no-op so a single trailing call covers the whole batch.
local Diff1Inline = oop.create_class("Diff1Inline", Diff1)

---@class Diff1Inline.init.Opt : Diff1.init.Opt
---@field a vcs.File?

Diff1Inline.name = "diff1_inline"
Diff1Inline.symbols = { "b" }

---@param opt Diff1Inline.init.Opt
function Diff1Inline:init(opt)
  self:super(opt)
  self:_set_a_file(opt and opt.a or nil)
end

---Assign the old-side file, tagging `symbol = "a"` so `vcs.File:produce_data()`
---resolves the left position when invoking a `get_data` producer.
---@param file vcs.File?
function Diff1Inline:_set_a_file(file)
  self.a_file = file
  if file then file.symbol = "a" end
end

---@override
---@return Diff1Inline
function Diff1Inline:clone()
  local clone = Layout.clone(self) --[[@as Diff1Inline ]]
  clone.a_file = self.a_file
  return clone
end

---@override
---@param self Diff1Inline
---@param pivot integer?
Diff1Inline.create = async.void(function(self, pivot)
  await(self:create_wins(pivot, {
    { "b", "aboveleft vsp" },
  }, { "b" }))
  await(self:_render_inline())
end)

---@override
---@param self Diff1Inline
---@param entry FileEntry
Diff1Inline.use_entry = async.void(function(self, entry)
  local src = entry.layout
  assert(src:instanceof(self.class))

  self:set_file_for("b", src.b.file)
  self:_set_a_file(src.a_file)
  -- File swap: invalidate cached old content so the next render re-fetches.
  self._cached_old_lines = nil

  if self:is_valid() then
    await(self:open_files())
    await(self:_render_inline())
  end
end)

---Fetch the raw lines of the old-side file for diff computation.
---@param self Diff1Inline
---@param callback fun(lines: string[])
Diff1Inline._load_old_lines = async.wrap(function(self, callback)
  if not self.a_file or self.a_file.nulled or self.a_file.binary then
    callback({})
    return
  end

  if self.a_file:is_valid() then
    callback(api.nvim_buf_get_lines(self.a_file.bufnr, 0, -1, false))
    return
  end

  local ok, err, data = pawait(self.a_file.produce_data, self.a_file)
  if not ok or err or not data then
    callback({})
    return
  end

  callback(data)
end)

---Build the options table forwarded to `inline_diff.render`. Merges the
---effective global `'diffopt'` with the configured inline style.
---@return InlineDiffOpts
local function render_opts()
  local opts = effective_diffopt()
  local inline_opt = config.get_config().view.inline or {}
  opts.style = inline_opt.style
  return opts
end

---Re-paint extmarks against the buffer's current contents. Called from
---`InsertLeave`/`TextChanged` autocmds so edits are reflected without a
---full view rebuild: the old-side content is frozen (it comes from the
---diff's left revision) and is cached by the initial `_render_inline`,
---so a repaint only re-reads the new-side buffer and calls
---`inline_diff.render` again.
---@param self Diff1Inline
function Diff1Inline:_repaint()
  -- Batched buffer edits toggle this flag so each intermediate `TextChanged`
  -- doesn't trigger a full `vim.diff` + extmark pass; the batch owner fires
  -- a single repaint once all edits are applied.
  if self._suppress_repaint then return end
  if not (self.b and self.b:is_valid() and self.b.file and self.b.file:is_valid()) then return end
  local bufnr = self.b.file.bufnr
  if not api.nvim_buf_is_valid(bufnr) then return end

  -- The cache is populated at the end of the initial `_render_inline`. If
  -- a repaint fires before that completes (e.g. a synthetic TextChanged
  -- during buffer setup), skip rather than double-fetch from disk.
  local old_lines = self._cached_old_lines
  if old_lines == nil then return end

  local new_lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  inline_diff.render(bufnr, old_lines, new_lines, render_opts())
end

---Install buffer-scoped autocmds that repaint on edits. Fires on any
---normal-mode text change (d/p/x/c/u/<C-r> …), on exit from insert mode,
---and on insert-mode changes via a trailing-edge debounced handler so
---bursts of keystrokes coalesce into a single diff pass instead of
---re-running the full diff on every character. The immediate
---`InsertLeave`/`TextChanged` handler drops any pending debounced call
---before repainting, so a `TextChangedI` followed promptly by
---`InsertLeave` doesn't queue a redundant second repaint. Idempotent:
---if autocmds are already installed for this buffer, this is a no-op.
---@param self Diff1Inline
---@param bufnr integer
local function register_repaint_autocmds(self, bufnr)
  if self._repaint_bufnr == bufnr then return end
  -- Different buffer than last time (or first install): clear any prior
  -- registration before attaching to the new one, and close any pending
  -- debounce timer so it doesn't fire against the old buffer.
  if self._repaint_bufnr and api.nvim_buf_is_valid(self._repaint_bufnr) then
    pcall(api.nvim_clear_autocmds, { group = repaint_augroup, buffer = self._repaint_bufnr })
  end
  if self._repaint_debounced then self._repaint_debounced:close() end
  self._repaint_bufnr = bufnr
  self._repaint_debounced = debounce.debounce_trailing(
    INSERT_REPAINT_DEBOUNCE_MS,
    false,
    function() self:_repaint() end
  )
  api.nvim_create_autocmd({ "InsertLeave", "TextChanged" }, {
    group = repaint_augroup,
    buffer = bufnr,
    callback = function()
      if self._repaint_debounced then self._repaint_debounced:cancel() end
      self:_repaint()
    end,
  })
  api.nvim_create_autocmd("TextChangedI", {
    group = repaint_augroup,
    buffer = bufnr,
    callback = function() self._repaint_debounced() end,
  })
end

---Apply inline-view winopts on the displayed window and render the unified
---diff as extmarks on the new-side buffer.
---@param self Diff1Inline
Diff1Inline._render_inline = async.void(function(self)
  if not (self.b and self.b:is_valid() and self.b.file and self.b.file:is_valid()) then return end

  local bufnr = self.b.file.bufnr
  local winid = self.b.id

  -- Turn off native diff mode on this window so the unified extmark rendering
  -- isn't fighting with diff folds/scrollbind.
  pcall(api.nvim_set_option_value, "diff", false, { win = winid })
  pcall(api.nvim_set_option_value, "scrollbind", false, { win = winid })
  pcall(api.nvim_set_option_value, "cursorbind", false, { win = winid })
  pcall(api.nvim_set_option_value, "foldmethod", "manual", { win = winid })
  pcall(api.nvim_set_option_value, "foldenable", false, { win = winid })

  local old_lines = self._cached_old_lines
  if old_lines == nil then
    old_lines = await(self:_load_old_lines())
    await(async.scheduler())
    if not (self.b and self.b:is_valid() and api.nvim_buf_is_valid(bufnr)) then return end
    self._cached_old_lines = old_lines
  end

  local new_lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  inline_diff.render(bufnr, old_lines, new_lines, render_opts())
  register_repaint_autocmds(self, bufnr)
end)

---Replace the new-side content of every hunk overlapping `[first, last]`
---(1-indexed, inclusive) with the corresponding old-side content from the
---cached diff. For a single-line range this matches vim's built-in `do`
---on a 2-way diff; for a multi-line visual range it applies every
---overlapping hunk in one pass.
---
---A hunk counts as overlapping when its new-side line range intersects
---`[first, last]`, or (for a pure deletion, where `new_count == 0`) when
---its anchor line is inside the range. Matches are applied bottom-up so
---earlier splices don't shift the anchor positions of later hunks.
---
---Returns the number of hunks applied. `TextChanged` repaints are
---suppressed during the splice and a single `_repaint` is fired at the
---end, so the extmarks are refreshed once regardless of hunk count.
---@param self Diff1Inline
---@param first integer
---@param last integer
---@return integer
function Diff1Inline:diffget(first, last)
  if not (self.b and self.b:is_valid() and self.b.file and self.b.file:is_valid()) then return 0 end
  local bufnr = self.b.file.bufnr
  if not api.nvim_buf_is_valid(bufnr) then return 0 end

  local old_lines = self._cached_old_lines
  if old_lines == nil then return 0 end

  local hunks = inline_diff.get_hunks(bufnr)
  if not hunks then return 0 end

  local matches = {}
  for _, h in ipairs(hunks) do
    local new_start, new_count = h[3], h[4]
    local overlaps
    if new_count > 0 then
      overlaps = not (new_start + new_count - 1 < first or new_start > last)
    else
      -- Pure deletion: the virt_lines are anchored at line `new_start`
      -- (or line 1 when the deletion is at BOF).
      local anchor = new_start == 0 and 1 or new_start
      overlaps = first <= anchor and anchor <= last
    end
    if overlaps then matches[#matches + 1] = h end
  end

  if #matches == 0 then return 0 end

  -- Suppress the per-edit `TextChanged` repaint so a multi-hunk batch
  -- doesn't trigger N full re-diffs; a single trailing repaint below
  -- refreshes the extmarks once.
  self._suppress_repaint = true
  local ok, err = pcall(function()
    for i = #matches, 1, -1 do
      local h = matches[i]
      local old_start, old_count, new_start, new_count = h[1], h[2], h[3], h[4]
      local repl = {}
      for k = old_start, old_start + old_count - 1 do
        repl[#repl + 1] = old_lines[k] or ""
      end
      local s, e
      if new_count > 0 then
        -- Add or change hunk: replace the new-side block in place.
        s = new_start - 1
        e = new_start - 1 + new_count
      else
        -- Pure deletion: insert after `new_start`, or at BOF when
        -- `new_start == 0`.
        s = new_start
        e = new_start
      end
      api.nvim_buf_set_lines(bufnr, s, e, false, repl)
    end
  end)
  self._suppress_repaint = nil
  if not ok then error(err) end

  self:_repaint()

  return #matches
end

---@override
---Diff1Inline owns `a_file` even though it isn't attached to a window, so
---expose it through `owned_files()` so `FileEntry:destroy()` can tear it
---down alongside the windowed files.
---@return vcs.File[]
function Diff1Inline:owned_files()
  local out = Layout.files(self)
  if self.a_file and not vim.tbl_contains(out, self.a_file) then out[#out + 1] = self.a_file end
  return out
end

---@override
---`convert_layout` looks up the file for each symbol via this method; expose
---`a_file` under the `"a"` slot so converting to a 2-way layout reuses the
---existing file instead of creating a fresh one (which would orphan the
---old-side buffer).
---@param sym string
---@return vcs.File?
function Diff1Inline:get_file_for(sym)
  if sym == "a" then return self.a_file end
  return Layout.get_file_for(self, sym)
end

---@override
function Diff1Inline:teardown_render()
  if self._repaint_bufnr and api.nvim_buf_is_valid(self._repaint_bufnr) then
    pcall(api.nvim_clear_autocmds, { group = repaint_augroup, buffer = self._repaint_bufnr })
  end
  if self._repaint_debounced then
    self._repaint_debounced:close()
    self._repaint_debounced = nil
  end
  self._repaint_bufnr = nil
  self._cached_old_lines = nil
  if self.b and self.b.file and self.b.file.bufnr then inline_diff.detach(self.b.file.bufnr) end
end

---@override
function Diff1Inline:destroy()
  self:teardown_render()
  Layout.destroy(self)
end

M.Diff1Inline = Diff1Inline

M._test = {
  effective_diffopt = effective_diffopt,
  render_opts = render_opts,
}

return M
