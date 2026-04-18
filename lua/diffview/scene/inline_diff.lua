-- Inline diff renderer for the `diff1_inline` layout.
--
-- The inline strikethrough rendering for deleted characters in the
-- "overleaf" style is adapted from the sample code shared by
-- @tienlonghungson in issue #109:
-- <https://github.com/dlyongemallo/diffview.nvim/issues/109>
-- which was itself modified from inlinediff-nvim:
-- <https://github.com/YouSame2/inlinediff-nvim>
--
-- The hunk dispatch, style architecture, unified-diff rendering,
-- hybrid word/char intraline tokenization, navigation, and caching are
-- original to this implementation.

local api = vim.api

local M = {}

M.ns = api.nvim_create_namespace("diffview_inline_diff")

-- Iterate over UTF-8 characters in `s`. Each step yields the character
-- substring, its 0-indexed byte offset, and its byte length. Pure-Lua O(n)
-- traversal: avoids the quadratic cost of `vim.fn.strcharpart(s, i, 1)` in
-- a per-character loop, which matters on long modified lines.
-- TODO: if the plugin's minimum Neovim version is raised to 0.12, replace
-- this decoder with `vim.str_utf_pos(s)`, which returns the byte start
-- positions of each UTF-8 character in a single call.
---@param s string
---@return fun(): string?, integer?, integer?
local function utf8_iter(s)
  local len = #s
  local pos = 1
  return function()
    if pos > len then return nil end
    local b = s:byte(pos)
    local char_len
    if b < 0x80 then
      char_len = 1
    elseif b < 0xC2 then
      -- Stray continuation byte or overlong lead; fall back to a single byte
      -- so malformed input still makes forward progress.
      char_len = 1
    elseif b < 0xE0 then
      char_len = 2
    elseif b < 0xF0 then
      char_len = 3
    elseif b < 0xF8 then
      char_len = 4
    else
      char_len = 1
    end
    local remaining = len - pos + 1
    if char_len > remaining then char_len = remaining end
    local ch = s:sub(pos, pos + char_len - 1)
    local start = pos - 1
    pos = pos + char_len
    return ch, start, char_len
  end
end

-- Classify a byte as a word byte: ASCII alphanumeric, underscore, or any
-- non-ASCII byte (multi-byte UTF-8 sequences are bucketed as word bytes so
-- non-Latin scripts tokenize as word runs rather than per-character).
---@param b integer
---@return boolean
local function is_word_byte(b)
  return b >= 0x80
    or (b >= 0x30 and b <= 0x39)
    or (b >= 0x41 and b <= 0x5A)
    or (b >= 0x61 and b <= 0x7A)
    or b == 0x5F
end

-- Classify a UTF-8 character as word-like. Any multi-byte character is
-- word-like; single-byte characters consult `is_word_byte`.
---@param ch string
---@return boolean
local function is_word_char(ch)
  if ch == "" then return false end
  if #ch > 1 then return true end
  return is_word_byte(ch:byte(1))
end

-- True when `s` is a word token (a maximal word-char run produced by
-- `tokenize`). Tokens are either an all-word-char run or a single
-- non-word char, so the first byte determines the class.
---@param s string
---@return boolean
local function is_word_token(s) return s ~= "" and is_word_byte(s:byte(1)) end

-- Tokenize `s` for word-level intraline diffing. Each maximal run of word
-- characters forms one token; each non-word character becomes its own
-- token. Returns the token list and a parallel byte-range map.
--
-- Per-character tokenization was tried first, but `vim.diff --minimal`
-- matches coincidental letters between dissimilar lines (e.g.
-- "something." and "any tracked metric." share 't', 'e', 'm', 'i', '.')
-- and splits the diff into small hunks. Rendered in overleaf style those
-- fragments interleave deleted and inserted text into unreadable
-- character-level noise. Word tokens sidestep that failure mode: a
-- shared word is meaningful context, a shared letter is not.
---@param s string
---@return string[] tokens
---@return { byte: integer, byte_len: integer }[] byte_map
local function tokenize(s)
  local tokens, byte_map = {}, {}
  local word_start, word_bytes
  for ch, byte_pos, char_len in utf8_iter(s) do
    if is_word_char(ch) then
      if word_start then
        tokens[#tokens] = tokens[#tokens] .. ch
        word_bytes = word_bytes + char_len
      else
        tokens[#tokens + 1] = ch
        word_start, word_bytes = byte_pos, char_len
      end
    else
      if word_start then
        byte_map[#byte_map + 1] = { byte = word_start, byte_len = word_bytes }
        word_start = nil
      end
      tokens[#tokens + 1] = ch
      byte_map[#byte_map + 1] = { byte = byte_pos, byte_len = char_len }
    end
  end
  if word_start then byte_map[#byte_map + 1] = { byte = word_start, byte_len = word_bytes } end
  return tokens, byte_map
end

-- Decompose `s` into UTF-8 characters with byte offsets. Used to refine a
-- 1:1 word-token replacement into per-character sub-hunks, preserving
-- typo-level precision (e.g. `recieve` → `receive` highlights only the
-- moved `i`).
---@param s string
---@return string[] chars
---@return { byte: integer, byte_len: integer }[] byte_map
local function split_chars(s)
  local chars, byte_map = {}, {}
  for ch, byte_pos, char_len in utf8_iter(s) do
    chars[#chars + 1] = ch
    byte_map[#byte_map + 1] = { byte = byte_pos, byte_len = char_len }
  end
  return chars, byte_map
end

-- Diff two unit arrays (tokens or chars) using `vim.diff`. Units are
-- joined with newlines so each unit maps to one "line" in vim.diff's
-- output; indices in the returned hunks are 1-based positions into the
-- input arrays.
--
-- Appending a trailing newline to both joined strings is essential.
-- Without it, `vim.diff` treats the final unit as an incomplete line
-- and can spuriously classify a matching trailing unit as
-- deleted+reinserted when one side has many more units after the
-- common run — e.g. `"function...(status)"` vs the same line with
-- `" return ... end"` appended would report `)` as deleted and
-- `) return ... end` as inserted, instead of recognizing `)` as the
-- end of the common prefix and treating the rest as pure addition.
-- Same remedy as the outer line-level diff in `render()`.
--
-- `'diffopt'`'s `ignore_*` whitespace/blank-line flags are deliberately
-- not forwarded here. Those flags only decide which lines are paired as
-- modifications by the outer hunk diff; once a pair is formed, the
-- intraline highlight reflects the actual character differences so the
-- reader can see exactly what changed. This matches how |hl-DiffText|
-- works in the built-in side-by-side diff.
---@param a_units string[]
---@param b_units string[]
---@return integer[][]
local function diff_units(a_units, b_units)
  if #a_units == 0 or #b_units == 0 then return {} end
  local a = table.concat(a_units, "\n") .. "\n"
  local b = table.concat(b_units, "\n") .. "\n"
  return vim.diff(a, b, {
    result_type = "indices",
    algorithm = "minimal",
    ctxlen = 0,
    linematch = 0,
    indent_heuristic = false,
  }) or {}
end

-- Skip intraline highlighting when a diff produces more than this many
-- hunks. Applied to word-level hunks as the similarity gate (dissimilar
-- lines cascade into many small word-level hunks) and to char-level
-- sub-hunks inside a 1:1 word replacement (if refinement fragments,
-- render the word as a whole instead).
local INTRALINE_MAX_HUNKS = 3

-- A 1:1 word replacement is safe to refine to char level only when the
-- sub-diff won't interleave deleted and inserted chars into garbage. A
-- single sub-hunk always renders cleanly (one anchor, one span). Two or
-- three sub-hunks are fine when the words genuinely overlap, signalled
-- by a shared prefix or suffix of at least two chars (e.g. `recieve`
-- vs `receive` shares `rec` + `ve`). Without that overlap, a lone
-- coincidental match (e.g. the single `r` in `param`/`return`)
-- fragments the diff and renders as `[pa]r[am]eturn` — worse than
-- falling back to a whole-word `[param]return` replacement.
---@param old_chars string[]
---@param new_chars string[]
---@param n_hunks integer
---@return boolean
local function refinement_safe(old_chars, new_chars, n_hunks)
  if n_hunks == 0 or n_hunks > INTRALINE_MAX_HUNKS then return false end
  if n_hunks == 1 then return true end

  local pre = 0
  while pre < #old_chars and pre < #new_chars and old_chars[pre + 1] == new_chars[pre + 1] do
    pre = pre + 1
  end
  if pre >= 2 then return true end

  local suf = 0
  while
    suf < #old_chars - pre
    and suf < #new_chars - pre
    and old_chars[#old_chars - suf] == new_chars[#new_chars - suf]
  do
    suf = suf + 1
  end
  return suf >= 2
end

-- Render a single intraline diff hunk as extmarks. Units (tokens or
-- characters) are located via `byte_map` with positions relative to the
-- span's origin at `base_byte`; `span_byte_len` is the byte length of
-- the span (the full line for word-level hunks, a single token for
-- refined char-level sub-hunks) and serves as the deletion-anchor
-- fallback when an index falls off the map.
---@param bufnr integer
---@param new_row integer
---@param base_byte integer
---@param span_byte_len integer
---@param byte_map { byte: integer, byte_len: integer }[]
---@param new_start integer
---@param new_count integer
---@param del_text string Joined deleted units ("" if none).
---@param inline_del boolean
local function render_hunk(
  bufnr,
  new_row,
  base_byte,
  span_byte_len,
  byte_map,
  new_start,
  new_count,
  del_text,
  inline_del
)
  if new_count > 0 then
    -- A hunk is a contiguous range, so emit one extmark spanning all units
    -- rather than one per unit (avoids thousands of extmarks on long lines).
    local first = byte_map[new_start]
    local last = byte_map[new_start + new_count - 1]
    if first and last then
      api.nvim_buf_set_extmark(bufnr, M.ns, new_row, base_byte + first.byte, {
        end_col = base_byte + last.byte + last.byte_len,
        hl_group = "DiffviewDiffText",
        priority = 200,
      })
    else
      -- Defensive fallback when byte_map can't resolve both ends — should
      -- not happen with a well-formed UTF-8 string but handle it so partial
      -- highlighting still appears.
      for k = new_start, new_start + new_count - 1 do
        local info = byte_map[k]
        if info then
          api.nvim_buf_set_extmark(bufnr, M.ns, new_row, base_byte + info.byte, {
            end_col = base_byte + info.byte + info.byte_len,
            hl_group = "DiffviewDiffText",
            priority = 200,
          })
        end
      end
    end
  end

  if inline_del and del_text ~= "" then
    local anchor_col
    if new_count > 0 then
      -- Replacement: anchor before the first added unit.
      anchor_col = base_byte + ((byte_map[new_start] and byte_map[new_start].byte) or span_byte_len)
    elseif new_start < 1 then
      -- Pure deletion at the start of the span.
      anchor_col = base_byte
    else
      -- Pure deletion mid/end: anchor after the context unit at new_start.
      local info = byte_map[new_start]
      anchor_col = base_byte + (info and (info.byte + info.byte_len) or span_byte_len)
    end

    api.nvim_buf_set_extmark(bufnr, M.ns, new_row, anchor_col, {
      virt_text = { { del_text, "DiffviewDiffDeleteInline" } },
      virt_text_pos = "inline",
      priority = 200,
    })
  end
end

-- Highlight changed ranges on a paired line. Uses a hybrid
-- word/char-level diff: hunks are computed at word granularity to avoid
-- coincidental-letter fragmentation, and 1:1 word-token replacements are
-- refined with a per-character sub-diff so typo-level precision is
-- preserved (e.g. `recieve` → `receive` highlights only the moved `i`
-- rather than the whole word).
--
-- When `inline_del` is true, additionally emit inline virtual text for
-- deleted units (the "overleaf" style). Bails out when the word-level
-- diff is too fragmented (a signal that the paired lines aren't really
-- related).
---@param bufnr integer
---@param new_row integer 0-indexed row in `bufnr`.
---@param old_line string
---@param new_line string
---@param inline_del boolean Render deleted units as inline virt_text.
---@return "ok"|"noop"|"skipped" # `ok`: rendered; `noop`: identical (nothing to do); `skipped`: fragmented, caller may want to fall back.
local function render_char_highlights(bufnr, new_row, old_line, new_line, inline_del)
  if old_line == new_line then return "noop" end
  -- Blank-to-nonblank (or vice versa) has no meaningful char-level diff, but
  -- the lines differ: signal `skipped` so the caller's fallback path still
  -- renders a line highlight / echoes the old line in overleaf style.
  if old_line == "" or new_line == "" then return "skipped" end

  local old_tokens = tokenize(old_line)
  local new_tokens, new_map = tokenize(new_line)
  local hunks = diff_units(old_tokens, new_tokens)
  if #hunks == 0 then return "noop" end
  if #hunks > INTRALINE_MAX_HUNKS then return "skipped" end

  local new_line_len = #new_line

  for _, h in ipairs(hunks) do
    local old_start, old_count, new_start, new_count = h[1], h[2], h[3], h[4]

    -- Try char-level refinement by diffing the concatenation of the old
    -- tokens in this hunk against the concatenation of the new tokens.
    -- This covers:
    --   - typo-style 1:1 word replacements (`recieve` → `receive`),
    --   - mid-word edits split across token boundaries
    --     (`statusend` → `status end`: delete the word, insert
    --     word+space+word — concat diff sees one inserted space),
    --   - punctuation swaps (`,` → `;`: one sub-hunk, clean).
    -- The `refinement_safe` guard rejects concatenations whose char-level
    -- diff is fragmented without genuine overlap (e.g. `something` vs
    -- `any tracked metric` shares only coincidental letters and falls
    -- back to word-level whole-token rendering).
    local refined = false
    if old_count > 0 and new_count > 0 then
      local old_parts = {}
      for k = old_start, old_start + old_count - 1 do
        old_parts[#old_parts + 1] = old_tokens[k] or ""
      end
      local new_parts = {}
      for k = new_start, new_start + new_count - 1 do
        new_parts[#new_parts + 1] = new_tokens[k] or ""
      end
      local old_concat = table.concat(old_parts)
      local new_concat = table.concat(new_parts)

      if old_concat ~= "" and new_concat ~= "" and old_concat ~= new_concat then
        local old_chars = split_chars(old_concat)
        local new_chars, new_char_map = split_chars(new_concat)
        local sub_hunks = diff_units(old_chars, new_chars)

        if refinement_safe(old_chars, new_chars, #sub_hunks) then
          refined = true
          local region_start = new_map[new_start]
          local region_end = new_map[new_start + new_count - 1]
          local region_base = region_start.byte
          local region_len = (region_end.byte + region_end.byte_len) - region_base

          for _, sh in ipairs(sub_hunks) do
            local sos, soc, sns, snc = sh[1], sh[2], sh[3], sh[4]
            local del_text = ""
            if inline_del and soc > 0 then
              local parts = {}
              for k = sos, sos + soc - 1 do
                parts[#parts + 1] = old_chars[k] or ""
              end
              del_text = table.concat(parts)
            end
            render_hunk(
              bufnr,
              new_row,
              region_base,
              region_len,
              new_char_map,
              sns,
              snc,
              del_text,
              inline_del
            )
          end
        end
      end
    end

    if not refined then
      local del_text = ""
      if inline_del and old_count > 0 then
        local parts = {}
        for k = old_start, old_start + old_count - 1 do
          parts[#parts + 1] = old_tokens[k] or ""
        end
        del_text = table.concat(parts)
      end
      render_hunk(
        bufnr,
        new_row,
        0,
        new_line_len,
        new_map,
        new_start,
        new_count,
        del_text,
        inline_del
      )
    end
  end

  return "ok"
end

-- Attach a block of deleted lines as virtual lines near `new_start`.
---@param bufnr integer
---@param old_lines string[]
---@param old_from integer 1-based start index into `old_lines`.
---@param old_to integer 1-based end index (inclusive).
---@param new_start integer Line position in new content (0 = before first line).
---@param anchor_row? integer 0-indexed row to attach to; default `new_start - 1`.
---@param above? boolean Default: `new_start == 0`.
---@param del_hl? string Highlight group for the deleted text. Default: `DiffviewDiffDelete`.
local function render_deleted_block(
  bufnr,
  old_lines,
  old_from,
  old_to,
  new_start,
  anchor_row,
  above,
  del_hl
)
  del_hl = del_hl or "DiffviewDiffDelete"
  local virt_lines = {}
  for k = old_from, old_to do
    virt_lines[#virt_lines + 1] = {
      { old_lines[k] or "", del_hl },
    }
  end

  if #virt_lines == 0 then return end

  local row = anchor_row
  if row == nil then row = new_start == 0 and 0 or new_start - 1 end

  if above == nil then above = new_start == 0 end

  local line_count = api.nvim_buf_line_count(bufnr)
  if line_count == 0 then return end

  if row >= line_count then row = line_count - 1 end

  api.nvim_buf_set_extmark(bufnr, M.ns, row, 0, {
    virt_lines = virt_lines,
    virt_lines_above = above,
    priority = 100,
  })
end

-- Per-buffer cache of hunks so ]c/[c navigation can find them without
-- re-scanning extmarks. Keyed by bufnr; cleared by `M.clear` and by a
-- buffer-lifecycle autocmd so externally-wiped buffers don't leak entries.
---@type table<integer, integer[][]>
M._hunks_by_buf = {}

-- Track which buffers already have a cleanup autocmd so we don't register
-- duplicates across repeated render passes on the same buffer.
---@type table<integer, true>
local cache_cleanup_registered = {}

local cache_cleanup_augroup =
  api.nvim_create_augroup("diffview_inline_diff_hunk_cache", { clear = true })

-- Track buffers whose CursorMoved scroll-adjuster is already installed.
---@type table<integer, true>
local scroll_adjuster_registered = {}

local scroll_adjuster_augroup =
  api.nvim_create_augroup("diffview_inline_diff_scroll", { clear = true })

---@param bufnr integer
local function register_cache_cleanup(bufnr)
  if cache_cleanup_registered[bufnr] or not api.nvim_buf_is_valid(bufnr) then return end

  cache_cleanup_registered[bufnr] = true
  api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
    group = cache_cleanup_augroup,
    buffer = bufnr,
    once = true,
    callback = function(args)
      M._hunks_by_buf[args.buf] = nil
      cache_cleanup_registered[args.buf] = nil
      -- Buffer-scoped autocmds on the scroll-adjuster group are dropped by
      -- Neovim when the buffer is wiped, so only the registration flag needs
      -- resetting here.
      scroll_adjuster_registered[args.buf] = nil
    end,
  })
end

-- Count virt_lines on a single row that match the `above` orientation.
---@param bufnr integer
---@param row integer 0-indexed.
---@param above boolean
---@return integer
local function count_edge_virt_lines(bufnr, row, above)
  local marks = api.nvim_buf_get_extmarks(bufnr, M.ns, { row, 0 }, { row, -1 }, { details = true })
  local total = 0
  for _, m in ipairs(marks) do
    local d = m[4]
    if d and d.virt_lines and (d.virt_lines_above or false) == above then
      total = total + #d.virt_lines
    end
  end
  return total
end

-- Bump `topline` just enough that virt_lines attached below the last
-- buffer line are visible whenever the cursor sits on that line.
-- Neovim's scroll computation does not count virt_lines, so motions
-- that land at EOF (`G`, `:$`, `}`, `Shift-L`, `<C-End>`, …) leave the
-- rendered deletions clipped below the viewport — the user sees them
-- only after a manual `zz`/`zb`. Idempotent: when topline is already
-- high enough, winrestview is not called (so WinScrolled doesn't
-- re-fire and there's no feedback loop).
---@param bufnr integer
---@param winid integer
function M.ensure_eof_virt_lines_visible(bufnr, winid)
  if not (api.nvim_buf_is_valid(bufnr) and api.nvim_win_is_valid(winid)) then return end
  if api.nvim_win_get_buf(winid) ~= bufnr then return end

  local last_row = api.nvim_buf_line_count(bufnr)
  if last_row == 0 then return end
  if api.nvim_win_get_cursor(winid)[1] ~= last_row then return end

  local below = count_edge_virt_lines(bufnr, last_row - 1, false)
  if below == 0 then return end

  local height = api.nvim_win_get_height(winid)
  -- Clamp `below` so we never ask for a topline past `last_row`: we can't
  -- show more virt_lines below the cursor than a full window's worth.
  local effective_below = math.min(below, math.max(height - 1, 0))
  local min_topline = math.min(last_row, math.max(1, last_row - (height - 1 - effective_below)))

  api.nvim_win_call(winid, function()
    local view = vim.fn.winsaveview()
    if view.topline < min_topline then
      view.topline = min_topline
      vim.fn.winrestview(view)
    end
  end)
end

-- Keep `topfill` in sync with the `virt_lines_above` count attached to
-- line 1: when `topline == 1`, topfill should equal the BOF virt_lines
-- count so the deletions render inside the viewport above line 1;
-- otherwise topfill should be 0 so stale filler from a previous render
-- doesn't leave an empty band at the top after BOF deletions go away
-- (e.g. re-render with no leading hunks, or a layout switch).
--
-- Gated on `M._hunks_by_buf[bufnr]` so we only touch topfill while the
-- buffer still hosts an inline diff — the CursorMoved autocmd that
-- calls this function outlives the inline layout, and we don't want to
-- fight diff-mode's own topfill on a buffer that's since switched
-- layouts.
--
-- `topfill` is normally a diff-mode filler-rows count, but Neovim
-- honours it for virt_lines_above on topline even when `'diff'` is off.
---@param bufnr integer
---@param winid integer
function M.ensure_bof_virt_lines_visible(bufnr, winid)
  if not (api.nvim_buf_is_valid(bufnr) and api.nvim_win_is_valid(winid)) then return end
  if api.nvim_win_get_buf(winid) ~= bufnr then return end
  if M._hunks_by_buf[bufnr] == nil then return end

  api.nvim_win_call(winid, function()
    local view = vim.fn.winsaveview()
    local desired = 0
    if view.topline == 1 then desired = count_edge_virt_lines(bufnr, 0, true) end
    if (view.topfill or 0) == desired then return end
    view.topfill = desired
    vim.fn.winrestview(view)
  end)
end

---@param bufnr integer
local function register_scroll_adjuster(bufnr)
  if scroll_adjuster_registered[bufnr] or not api.nvim_buf_is_valid(bufnr) then return end

  scroll_adjuster_registered[bufnr] = true
  api.nvim_create_autocmd("CursorMoved", {
    group = scroll_adjuster_augroup,
    buffer = bufnr,
    callback = function(args)
      local winid = api.nvim_get_current_win()
      M.ensure_eof_virt_lines_visible(args.buf, winid)
      M.ensure_bof_virt_lines_visible(args.buf, winid)
    end,
  })
end

-- Clear all inline-diff extmarks from the buffer.
---@param bufnr integer
function M.clear(bufnr)
  if bufnr and api.nvim_buf_is_valid(bufnr) then
    api.nvim_buf_clear_namespace(bufnr, M.ns, 0, -1)
  end
  -- Note: keep `cache_cleanup_registered[bufnr]` set. The BufWipeout/BufDelete
  -- autocmd installed by `register_cache_cleanup` is still pending and will
  -- reset the flag when it fires. Clearing the flag here would cause the next
  -- render pass to register a duplicate autocmd.
  if bufnr then M._hunks_by_buf[bufnr] = nil end
end

-- Fully detach the inline diff from `bufnr`: clear extmarks and cached hunks
-- (as `clear()` does), remove the CursorMoved scroll-adjuster autocmd so the
-- buffer doesn't keep firing a now-useless handler after the inline view is
-- torn down (e.g. layout switch, or closing the view while keeping the
-- underlying file buffer alive), and reset any `topfill` that
-- `ensure_bof_virt_lines_visible()` set on windows showing `bufnr` so
-- teardown doesn't leave an empty filler band above line 1.
---@param bufnr integer
function M.detach(bufnr)
  M.clear(bufnr)
  if not bufnr then return end
  if scroll_adjuster_registered[bufnr] then
    scroll_adjuster_registered[bufnr] = nil
    if api.nvim_buf_is_valid(bufnr) then
      pcall(api.nvim_clear_autocmds, { group = scroll_adjuster_augroup, buffer = bufnr })
    end
  end
  if not api.nvim_buf_is_valid(bufnr) then return end
  for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
    if api.nvim_win_is_valid(winid) then
      api.nvim_win_call(winid, function()
        local view = vim.fn.winsaveview()
        if (view.topfill or 0) ~= 0 then
          view.topfill = 0
          vim.fn.winrestview(view)
        end
      end)
    end
  end
end

-- Return the sorted list of 0-indexed rows where each hunk's cursor target
-- should land. For add/change hunks this is the first modified new-side row;
-- for pure deletions it's the row adjacent to the virt_lines anchor.
---@param bufnr integer
---@return integer[]
function M.hunk_anchor_rows(bufnr)
  local hunks = M._hunks_by_buf[bufnr]
  if not hunks then return {} end

  local rows = {}
  local line_count = api.nvim_buf_is_valid(bufnr) and api.nvim_buf_line_count(bufnr) or 0
  local seen = {}

  for _, h in ipairs(hunks) do
    local new_start, new_count = h[3], h[4]
    local row
    if new_count > 0 then
      row = new_start - 1
    else
      -- Pure deletion: anchor at the line that holds the virt_lines.
      row = new_start == 0 and 0 or new_start - 1
    end
    if row < 0 then row = 0 end
    if line_count > 0 and row >= line_count then row = line_count - 1 end

    if not seen[row] then
      seen[row] = true
      rows[#rows + 1] = row
    end
  end

  table.sort(rows)
  return rows
end

-- Find the row of the first hunk strictly after `cursor_row` (0-indexed).
---@param bufnr integer
---@param cursor_row integer
---@return integer? row
function M.next_hunk_row(bufnr, cursor_row)
  for _, r in ipairs(M.hunk_anchor_rows(bufnr)) do
    if r > cursor_row then return r end
  end
end

-- Return the cached hunks for `bufnr`, or `nil` if no inline diff is
-- currently attached. Each hunk is `{ old_start, old_count, new_start,
-- new_count }` in 1-indexed form, as returned by `vim.diff`.
---@param bufnr integer
---@return integer[][]?
function M.get_hunks(bufnr) return M._hunks_by_buf[bufnr] end

-- Find the row of the last hunk strictly before `cursor_row` (0-indexed).
---@param bufnr integer
---@param cursor_row integer
---@return integer? row
function M.prev_hunk_row(bufnr, cursor_row)
  local rows = M.hunk_anchor_rows(bufnr)
  local prev
  for _, r in ipairs(rows) do
    if r < cursor_row then
      prev = r
    else
      break
    end
  end
  return prev
end

---@class InlineDiffOpts
---@field algorithm? string
---@field linematch? integer
---@field indent_heuristic? boolean
---@field ignore_whitespace? boolean
---@field ignore_whitespace_change? boolean
---@field ignore_whitespace_change_at_eol? boolean
---@field ignore_blank_lines? boolean
---@field style? "unified"|"overleaf" Default: `"unified"`.

---@class InlineDiffStyle
---@field del_hl string Highlight group for virt_line deletions.
---@field inline_del boolean Render paired char-level deletions as inline virt_text.
---@field echo_paired_old boolean Emit full old content as virt_lines above paired modifications.
---@field change_line_hl? string Line highlight on paired modified rows, or `nil` to skip.

---@type table<string, InlineDiffStyle>
local STYLES = {
  -- Proper unified diff: deletions visible as virt_lines above the new block.
  unified = {
    del_hl = "DiffviewDiffDelete",
    inline_del = false,
    echo_paired_old = true,
    change_line_hl = "DiffviewDiffChange",
  },
  -- Overleaf style: deletions rendered inline as strikethrough virt_text so
  -- the reader sees the change in flow. No block echo, no line hl — the
  -- char-level rendering stands alone.
  overleaf = {
    del_hl = "DiffviewDiffDeleteInline",
    inline_del = true,
    echo_paired_old = false,
    change_line_hl = nil,
  },
}

-- Render a unified inline diff into `bufnr` using extmarks. The buffer is
-- assumed to contain `new_lines`; deletions and char-level highlights are
-- layered on top without modifying buffer contents.
---@param bufnr integer
---@param old_lines string[] Content of the old side.
---@param new_lines string[] Content of the new side (matches `bufnr`).
---@param opts? InlineDiffOpts
function M.render(bufnr, old_lines, new_lines, opts)
  opts = opts or {}
  local style = STYLES[opts.style] or STYLES.unified
  M.clear(bufnr)

  if not api.nvim_buf_is_valid(bufnr) then return end
  if api.nvim_buf_line_count(bufnr) == 0 then return end

  -- Terminate with a trailing newline so `vim.diff` treats the last line as a
  -- complete line. Without it, EOF additions/deletions get classified as
  -- modifications of the adjacent line (e.g. `{old_last, e} -> {old_last}`
  -- reports as a 2:1 modify rather than a pure delete of `e`), which both
  -- hides the EOF hunk's real shape and echoes the unchanged adjacent line
  -- as a spurious virt_line under the "unified" style.
  local old = #old_lines > 0 and table.concat(old_lines, "\n") .. "\n" or ""
  local new = #new_lines > 0 and table.concat(new_lines, "\n") .. "\n" or ""

  local diff_opts = { result_type = "indices" }
  -- Only forward each `vim.diff` option (`algorithm`, `linematch`,
  -- `indent_heuristic`, and the `ignore_*` whitespace/blank-line flags) when
  -- explicitly set so vim.diff's own defaults apply otherwise. This mirrors
  -- how `'diffopt'` toggles flags/options by presence/absence rather than
  -- forcing fallback values here.
  if opts.algorithm ~= nil then diff_opts.algorithm = opts.algorithm end
  if opts.linematch ~= nil then diff_opts.linematch = opts.linematch end
  if opts.indent_heuristic ~= nil then diff_opts.indent_heuristic = opts.indent_heuristic end
  if opts.ignore_whitespace ~= nil then diff_opts.ignore_whitespace = opts.ignore_whitespace end
  if opts.ignore_whitespace_change ~= nil then
    diff_opts.ignore_whitespace_change = opts.ignore_whitespace_change
  end
  if opts.ignore_whitespace_change_at_eol ~= nil then
    diff_opts.ignore_whitespace_change_at_eol = opts.ignore_whitespace_change_at_eol
  end
  if opts.ignore_blank_lines ~= nil then diff_opts.ignore_blank_lines = opts.ignore_blank_lines end

  local hunks = vim.diff(old, new, diff_opts)

  if not hunks then return end

  M._hunks_by_buf[bufnr] = hunks
  register_cache_cleanup(bufnr)
  register_scroll_adjuster(bufnr)

  for _, h in ipairs(hunks) do
    local old_start, old_count, new_start, new_count = h[1], h[2], h[3], h[4]

    if old_count == 0 and new_count > 0 then
      -- Pure addition: highlight the new lines.
      for k = 0, new_count - 1 do
        local row = new_start - 1 + k
        api.nvim_buf_set_extmark(bufnr, M.ns, row, 0, {
          line_hl_group = "DiffviewDiffAdd",
          priority = 100,
        })
      end
    elseif new_count == 0 and old_count > 0 then
      -- Pure deletion: show the old lines as virtual lines.
      render_deleted_block(
        bufnr,
        old_lines,
        old_start,
        old_start + old_count - 1,
        new_start,
        nil,
        nil,
        style.del_hl
      )
    elseif old_count > 0 and new_count > 0 then
      -- Modification: unified and overleaf diverge on how deletions are
      -- conveyed. Unified echoes the full old content as virt_lines above
      -- (block-level unified diff); overleaf relies on char-level inline
      -- strikethrough on the paired new rows and only uses virt_lines for
      -- overflow old lines that don't pair with any new line.
      local paired = math.min(old_count, new_count)

      if style.echo_paired_old then
        render_deleted_block(
          bufnr,
          old_lines,
          old_start,
          old_start + old_count - 1,
          new_start,
          new_start - 1,
          true,
          style.del_hl
        )
      elseif old_count > paired then
        -- Overleaf: overflow old lines still get a virt_line above.
        local anchor = new_start - 1 + paired - 1
        render_deleted_block(
          bufnr,
          old_lines,
          old_start + paired,
          old_start + old_count - 1,
          new_start,
          anchor,
          false,
          style.del_hl
        )
      end

      for k = 0, paired - 1 do
        local row = new_start - 1 + k
        local ol = old_lines[old_start + k] or ""
        local nl = new_lines[new_start + k] or ""
        local char_result = render_char_highlights(bufnr, row, ol, nl, style.inline_del)

        -- Line highlight. Unified always applies it; overleaf applies it only
        -- as a fallback when char-level rendering was skipped (fragmented
        -- pairing) so the reader still sees that the line was modified.
        local line_hl = style.change_line_hl
        if not line_hl and char_result == "skipped" then line_hl = "DiffviewDiffChange" end
        if line_hl then
          api.nvim_buf_set_extmark(bufnr, M.ns, row, 0, {
            line_hl_group = line_hl,
            priority = 100,
          })
        end

        -- Overleaf fallback: when char-level was skipped and we're not
        -- already echoing old lines, show this paired old line above the
        -- new one so the reader can see what changed.
        if not style.echo_paired_old and char_result == "skipped" and ol ~= nl then
          render_deleted_block(
            bufnr,
            old_lines,
            old_start + k,
            old_start + k,
            new_start + k,
            row,
            true,
            "DiffviewDiffDelete"
          )
        end
      end

      if new_count > paired then
        for k = paired, new_count - 1 do
          local row = new_start - 1 + k
          api.nvim_buf_set_extmark(bufnr, M.ns, row, 0, {
            line_hl_group = "DiffviewDiffAdd",
            priority = 100,
          })
        end
      end
    end
  end

  -- Cover the case where the buffer was already showing its last/first
  -- line (e.g. a refresh after the user navigated to either edge) — the
  -- next CursorMoved might not fire until they move again.
  local winid = vim.fn.bufwinid(bufnr)
  if winid ~= -1 then
    M.ensure_eof_virt_lines_visible(bufnr, winid)
    M.ensure_bof_virt_lines_visible(bufnr, winid)
  end
end

M._test = {
  is_word_char = is_word_char,
  is_word_token = is_word_token,
  tokenize = tokenize,
  split_chars = split_chars,
  diff_units = diff_units,
  refinement_safe = refinement_safe,
  INTRALINE_MAX_HUNKS = INTRALINE_MAX_HUNKS,
}

return M
