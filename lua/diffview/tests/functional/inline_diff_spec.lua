local api = vim.api

describe("diffview.scene.inline_diff", function()
  local inline_diff = require("diffview.scene.inline_diff")
  local created_bufs

  local function fresh_buf(lines)
    local bufnr = api.nvim_create_buf(false, true)
    table.insert(created_bufs, bufnr)
    api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    return bufnr
  end

  local function extmarks(bufnr)
    return api.nvim_buf_get_extmarks(bufnr, inline_diff.ns, 0, -1, { details = true })
  end

  local function line_hls(marks)
    local out = {}
    for _, m in ipairs(marks) do
      if m[4] and m[4].line_hl_group then
        out[#out + 1] = { row = m[2], hl = m[4].line_hl_group }
      end
    end
    table.sort(out, function(a, b)
      return a.row < b.row
    end)
    return out
  end

  local function virt_line_counts(marks)
    local out = {}
    for _, m in ipairs(marks) do
      if m[4] and m[4].virt_lines then
        out[#out + 1] = {
          row = m[2],
          count = #m[4].virt_lines,
          above = m[4].virt_lines_above or false,
        }
      end
    end
    table.sort(out, function(a, b)
      return a.row < b.row
    end)
    return out
  end

  local function char_ranges(marks)
    local out = {}
    for _, m in ipairs(marks) do
      if m[4] and m[4].hl_group == "DiffviewDiffText" then
        out[#out + 1] = { row = m[2], start = m[3], finish = m[4].end_col }
      end
    end
    table.sort(out, function(a, b)
      if a.row == b.row then
        return a.start < b.start
      end
      return a.row < b.row
    end)
    return out
  end

  local function inline_virt_texts(marks, hl)
    local out = {}
    for _, m in ipairs(marks) do
      local d = m[4]
      if d and d.virt_text and d.virt_text_pos == "inline" then
        local chunk = d.virt_text[1]
        if not hl or (chunk and chunk[2] == hl) then
          out[#out + 1] = { row = m[2], col = m[3], text = chunk and chunk[1] or "" }
        end
      end
    end
    table.sort(out, function(a, b)
      if a.row == b.row then
        return a.col < b.col
      end
      return a.row < b.row
    end)
    return out
  end

  local function virt_line_hls(marks)
    local out = {}
    for _, m in ipairs(marks) do
      if m[4] and m[4].virt_lines then
        for _, line in ipairs(m[4].virt_lines) do
          out[#out + 1] = line[1] and line[1][2] or nil
        end
      end
    end
    return out
  end

  before_each(function()
    created_bufs = {}
  end)

  after_each(function()
    for _, b in ipairs(created_bufs) do
      pcall(api.nvim_buf_delete, b, { force = true })
    end
  end)

  describe("render", function()
    it("marks pure-addition hunks with DiffviewDiffAdd", function()
      local bufnr = fresh_buf({ "line one", "line two", "line three", "line four" })
      inline_diff.render(bufnr, { "line one", "line four" }, {
        "line one",
        "line two",
        "line three",
        "line four",
      })

      local hls = line_hls(extmarks(bufnr))
      assert.are.same({
        { row = 1, hl = "DiffviewDiffAdd" },
        { row = 2, hl = "DiffviewDiffAdd" },
      }, hls)
      assert.are.same({}, virt_line_counts(extmarks(bufnr)))
    end)

    it("renders pure deletions as virt_lines attached to the right row", function()
      local bufnr = fresh_buf({ "a", "d" })
      inline_diff.render(bufnr, { "a", "b", "c", "d" }, { "a", "d" })

      local vls = virt_line_counts(extmarks(bufnr))
      -- Deletion between new line 1 ("a") and new line 2 ("d") -> row 0, below.
      assert.are.same({ { row = 0, count = 2, above = false } }, vls)
      -- No line highlights expected for pure deletion.
      assert.are.same({}, line_hls(extmarks(bufnr)))
    end)

    it("anchors top-of-file deletions above line 0", function()
      local bufnr = fresh_buf({ "x", "y" })
      inline_diff.render(bufnr, { "gone1", "gone2", "x", "y" }, { "x", "y" })

      local vls = virt_line_counts(extmarks(bufnr))
      assert.are.same({ { row = 0, count = 2, above = true } }, vls)
    end)

    it("anchors end-of-file deletions below the last line", function()
      -- Regression: without a trailing newline `vim.diff` treats the last
      -- new line as unterminated and reports this as a modification hunk
      -- (conflating the unchanged last line with the EOF deletion), which
      -- both hid the deletion and echoed the unchanged line as a spurious
      -- virt_line above. The EOF-deleted block should sit *below* the last
      -- new-side row.
      local bufnr = fresh_buf({ "a", "b" })
      inline_diff.render(bufnr, { "a", "b", "gone1", "gone2" }, { "a", "b" })

      local vls = virt_line_counts(extmarks(bufnr))
      assert.are.same({ { row = 1, count = 2, above = false } }, vls)
      -- No paired-modification line_hl — the last line is unchanged.
      assert.are.same({}, line_hls(extmarks(bufnr)))
    end)

    it("marks end-of-file additions with DiffviewDiffAdd", function()
      local bufnr = fresh_buf({ "a", "b", "added1", "added2" })
      inline_diff.render(bufnr, { "a", "b" }, { "a", "b", "added1", "added2" })

      local hls = line_hls(extmarks(bufnr))
      assert.are.same({
        { row = 2, hl = "DiffviewDiffAdd" },
        { row = 3, hl = "DiffviewDiffAdd" },
      }, hls)
      -- No virt_lines for a pure addition.
      assert.are.same({}, virt_line_counts(extmarks(bufnr)))
    end)

    it("marks modified lines with DiffChange and char-level DiffText", function()
      local bufnr = fresh_buf({ "hello wonderful world" })
      inline_diff.render(bufnr, { "hello world" }, { "hello wonderful world" })

      local hls = line_hls(extmarks(bufnr))
      assert.are.same({ { row = 0, hl = "DiffviewDiffChange" } }, hls)

      -- Expect at least one char-level DiffText range covering "wonderful ".
      local ranges = char_ranges(extmarks(bufnr))
      assert.is_true(#ranges > 0, "expected DiffviewDiffText extmarks")

      -- Unified style echoes the old line above the modification.
      local vls = virt_line_counts(extmarks(bufnr))
      assert.are.same({ { row = 0, count = 1, above = true } }, vls)
    end)

    it("shows old lines as virt_lines above modification hunks", function()
      -- Pick a 1:1 modification so vim.diff doesn't split into separate
      -- modify + pure-delete hunks.
      local bufnr = fresh_buf({ "first changed", "second" })
      inline_diff.render(bufnr, { "first", "second" }, { "first changed", "second" })

      local hls = line_hls(extmarks(bufnr))
      local vls = virt_line_counts(extmarks(bufnr))

      assert.are.same({ { row = 0, hl = "DiffviewDiffChange" } }, hls)
      -- Old line "first" appears above the first paired row.
      assert.are.same({ { row = 0, count = 1, above = true } }, vls)
    end)

    it("handles overflow-addition within a modification hunk", function()
      local bufnr = fresh_buf({ "one changed", "extra" })
      inline_diff.render(bufnr, { "one" }, { "one changed", "extra" })

      local hls = line_hls(extmarks(bufnr))
      assert.are.same({
        { row = 0, hl = "DiffviewDiffChange" },
        { row = 1, hl = "DiffviewDiffAdd" },
      }, hls)
    end)

    it("treats an empty old side as pure addition across the whole buffer", function()
      local bufnr = fresh_buf({ "first", "second", "third" })
      inline_diff.render(bufnr, {}, { "first", "second", "third" })

      local hls = line_hls(extmarks(bufnr))
      assert.are.same({
        { row = 0, hl = "DiffviewDiffAdd" },
        { row = 1, hl = "DiffviewDiffAdd" },
        { row = 2, hl = "DiffviewDiffAdd" },
      }, hls)
      assert.are.same({}, virt_line_counts(extmarks(bufnr)))
    end)

    it("bails out cleanly on an empty buffer", function()
      -- fresh_buf({}) yields a buffer with no lines; Neovim's default empty
      -- buffer always has one empty line, but render should be safe either way.
      local bufnr = fresh_buf({})
      inline_diff.render(bufnr, { "old" }, api.nvim_buf_get_lines(bufnr, 0, -1, false))
      assert.is_table(extmarks(bufnr))
    end)

    it("clear() removes previously-rendered marks", function()
      local bufnr = fresh_buf({ "a", "b", "c" })
      inline_diff.render(bufnr, {}, { "a", "b", "c" })
      assert.is_true(#extmarks(bufnr) > 0)

      inline_diff.clear(bufnr)
      assert.are.equal(0, #extmarks(bufnr))
    end)

    it("is idempotent across repeated calls", function()
      local bufnr = fresh_buf({ "one", "two changed", "three" })
      inline_diff.render(bufnr, { "one", "two", "three" }, {
        "one",
        "two changed",
        "three",
      })
      local first = #extmarks(bufnr)

      inline_diff.render(bufnr, { "one", "two", "three" }, {
        "one",
        "two changed",
        "three",
      })
      local second = #extmarks(bufnr)

      assert.are.equal(first, second)
    end)
  end)

  describe("overleaf style", function()
    it("emits inline virt_text for char-level deletions on paired lines", function()
      local bufnr = fresh_buf({ "hello world" })
      inline_diff.render(bufnr, { "hello brave world" }, { "hello world" }, { style = "overleaf" })

      local inlines = inline_virt_texts(extmarks(bufnr), "DiffviewDiffDeleteInline")
      assert.is_true(#inlines > 0, "expected at least one inline deletion virt_text")
      -- The deleted run should be on the modified line and contain "brave".
      local any = false
      for _, v in ipairs(inlines) do
        if v.text:find("brave") then
          any = true
        end
      end
      assert.is_true(any, "expected deleted text to contain 'brave'")
    end)

    it("still emits DiffText hl on added chars in overleaf style", function()
      local bufnr = fresh_buf({ "hello brave new world" })
      inline_diff.render(
        bufnr,
        { "hello world" },
        { "hello brave new world" },
        { style = "overleaf" }
      )

      local ranges = char_ranges(extmarks(bufnr))
      assert.is_true(#ranges > 0, "expected DiffviewDiffText extmarks on added chars")
    end)

    it("uses DiffviewDiffDeleteInline hl for whole-line deletions", function()
      local bufnr = fresh_buf({ "a", "c" })
      inline_diff.render(bufnr, { "a", "b", "c" }, { "a", "c" }, { style = "overleaf" })

      local hls = virt_line_hls(extmarks(bufnr))
      assert.are.same({ "DiffviewDiffDeleteInline" }, hls)
    end)

    it("uses DiffviewDiffDelete hl in default unified style", function()
      local bufnr = fresh_buf({ "a", "c" })
      inline_diff.render(bufnr, { "a", "b", "c" }, { "a", "c" })

      local hls = virt_line_hls(extmarks(bufnr))
      assert.are.same({ "DiffviewDiffDelete" }, hls)
    end)

    it("does NOT emit inline deletion virt_text in unified style", function()
      local bufnr = fresh_buf({ "hello world" })
      inline_diff.render(bufnr, { "hello brave world" }, { "hello world" })

      local inlines = inline_virt_texts(extmarks(bufnr), "DiffviewDiffDeleteInline")
      assert.are.equal(0, #inlines)
    end)

    it("falls back to unified for unknown style values", function()
      local bufnr = fresh_buf({ "a", "c" })
      inline_diff.render(bufnr, { "a", "b", "c" }, { "a", "c" }, { style = "bogus" })

      local hls = virt_line_hls(extmarks(bufnr))
      assert.are.same({ "DiffviewDiffDelete" }, hls)
    end)

    it("does not echo old paired lines as virt_lines (no double-rendering)", function()
      local bufnr = fresh_buf({ "first changed", "second" })
      inline_diff.render(
        bufnr,
        { "first", "second" },
        { "first changed", "second" },
        { style = "overleaf" }
      )

      -- No block virt_lines for the paired modification in overleaf.
      assert.are.same({}, virt_line_counts(extmarks(bufnr)))
    end)

    it("does not apply DiffChange line_hl on paired modified rows", function()
      local bufnr = fresh_buf({ "first changed", "second" })
      inline_diff.render(
        bufnr,
        { "first", "second" },
        { "first changed", "second" },
        { style = "overleaf" }
      )

      local hls = line_hls(extmarks(bufnr))
      for _, h in ipairs(hls) do
        assert.are_not.equal("DiffviewDiffChange", h.hl)
      end
    end)

    it("still emits virt_lines for overflow old lines within a modification", function()
      -- Modification: 2 old paired with 1 new, so 1 unpaired old overflow.
      -- Use unrelated content to force a single 2:1 modification hunk rather
      -- than a 1:1 modify + pure-delete split.
      local bufnr = fresh_buf({ "alpha" })
      inline_diff.render(bufnr, { "xyz", "pqr" }, { "alpha" }, { style = "overleaf" })

      local hls = virt_line_hls(extmarks(bufnr))
      -- Whatever vim.diff produces, any virt_lines emitted must be in the
      -- overleaf deletion hl group.
      for _, h in ipairs(hls) do
        assert.are.equal("DiffviewDiffDeleteInline", h)
      end
    end)
  end)

  describe("hunk navigation", function()
    -- Set up a buffer with three discontiguous hunks: pure add at top,
    -- change in the middle, and pure deletion at the end.
    local function buf_with_hunks()
      local new = {
        "added one",
        "added two",
        "context",
        "middle changed",
        "context",
        "context",
      }
      local old = {
        "context",
        "middle",
        "context",
        "context",
        "trailing-old",
      }
      local bufnr = fresh_buf(new)
      inline_diff.render(bufnr, old, new)
      return bufnr
    end

    it("returns anchor rows sorted, one per hunk", function()
      local bufnr = buf_with_hunks()
      local rows = inline_diff.hunk_anchor_rows(bufnr)
      assert.is_true(#rows >= 2, "expected multiple hunks")
      for i = 2, #rows do
        assert.is_true(rows[i] > rows[i - 1], "rows must be strictly increasing")
      end
    end)

    it("next_hunk_row returns the first row strictly after the cursor", function()
      local bufnr = buf_with_hunks()
      local rows = inline_diff.hunk_anchor_rows(bufnr)
      -- From the top, next_hunk from -1 should be the first anchor.
      assert.are.equal(rows[1], inline_diff.next_hunk_row(bufnr, -1))
      -- From row[1], next should be rows[2].
      if #rows >= 2 then
        assert.are.equal(rows[2], inline_diff.next_hunk_row(bufnr, rows[1]))
      end
    end)

    it("next_hunk_row returns nil past the last hunk", function()
      local bufnr = buf_with_hunks()
      local rows = inline_diff.hunk_anchor_rows(bufnr)
      assert.is_nil(inline_diff.next_hunk_row(bufnr, rows[#rows]))
    end)

    it("prev_hunk_row returns nil before the first hunk", function()
      local bufnr = buf_with_hunks()
      local rows = inline_diff.hunk_anchor_rows(bufnr)
      assert.is_nil(inline_diff.prev_hunk_row(bufnr, rows[1]))
    end)

    it("prev_hunk_row returns the last row strictly before the cursor", function()
      local bufnr = buf_with_hunks()
      local rows = inline_diff.hunk_anchor_rows(bufnr)
      if #rows >= 2 then
        assert.are.equal(rows[1], inline_diff.prev_hunk_row(bufnr, rows[2]))
        -- From well past the last hunk, prev is the last one.
        assert.are.equal(rows[#rows], inline_diff.prev_hunk_row(bufnr, rows[#rows] + 100))
      end
    end)

    it("clear() also drops the cached hunks", function()
      local bufnr = buf_with_hunks()
      assert.is_true(#inline_diff.hunk_anchor_rows(bufnr) > 0)
      inline_diff.clear(bufnr)
      assert.are.same({}, inline_diff.hunk_anchor_rows(bufnr))
    end)

    it("drops cached hunks when the buffer is wiped externally", function()
      local bufnr = buf_with_hunks()
      assert.is_not_nil(inline_diff._hunks_by_buf[bufnr])

      -- Simulate a foreign owner deleting the buffer without calling clear().
      api.nvim_buf_delete(bufnr, { force = true })

      -- The buffer id may be reused; just confirm the stale entry is gone.
      assert.is_nil(inline_diff._hunks_by_buf[bufnr])
    end)

    it("detach() removes the CursorMoved scroll-adjuster autocmd", function()
      local bufnr = buf_with_hunks()
      local before = api.nvim_get_autocmds({
        group = "diffview_inline_diff_scroll",
        buffer = bufnr,
      })
      assert.is_true(#before > 0, "render should have installed the scroll adjuster")

      inline_diff.detach(bufnr)

      local after = api.nvim_get_autocmds({
        group = "diffview_inline_diff_scroll",
        buffer = bufnr,
      })
      assert.are.equal(0, #after)
      assert.are.same({}, inline_diff.hunk_anchor_rows(bufnr))
      assert.are.equal(0, #extmarks(bufnr))
    end)

    it("detach() followed by render reinstalls the scroll-adjuster autocmd", function()
      local bufnr = buf_with_hunks()
      inline_diff.detach(bufnr)

      inline_diff.render(bufnr, { "a", "b" }, { "a", "b", "c" })

      local autocmds = api.nvim_get_autocmds({
        group = "diffview_inline_diff_scroll",
        buffer = bufnr,
      })
      assert.are.equal(1, #autocmds)
    end)

    it("detach() resets topfill on windows displaying the buffer", function()
      -- Regression: without resetting topfill, tearing down the inline layout
      -- (e.g. layout switch) while `ensure_bof_virt_lines_visible` had raised
      -- `topfill` leaves an empty filler band above line 1 in the viewport.
      local new_lines = { "line 1", "line 2", "line 3" }
      local old_lines = { "gone 1", "gone 2", "line 1", "line 2", "line 3" }
      local bufnr = fresh_buf(new_lines)
      inline_diff.render(bufnr, old_lines, new_lines)

      local win = api.nvim_get_current_win()
      api.nvim_win_set_buf(win, bufnr)
      api.nvim_win_set_cursor(win, { 1, 0 })
      vim.fn.winrestview({ topline = 1, topfill = 0 })
      inline_diff.ensure_bof_virt_lines_visible(bufnr, win)
      assert.are.equal(2, vim.fn.winsaveview().topfill or 0)

      inline_diff.detach(bufnr)

      assert.are.equal(0, vim.fn.winsaveview().topfill or 0)
    end)
  end)

  describe("helpers", function()
    local h = inline_diff._test

    it("split_chars decomposes multi-byte characters with byte ranges", function()
      local chars, m = h.split_chars("a\xc3\xa9b")
      assert.are.same({ "a", "\xc3\xa9", "b" }, chars)
      assert.are.equal(3, #m)
      assert.are.equal(0, m[1].byte)
      assert.are.equal(1, m[1].byte_len)
      assert.are.equal(1, m[2].byte)
      assert.are.equal(2, m[2].byte_len)
      assert.are.equal(3, m[3].byte)
      assert.are.equal(1, m[3].byte_len)
    end)

    it("tokenize groups word-char runs and splits non-word chars individually", function()
      local tokens, m = h.tokenize("hello, world!")
      assert.are.same({ "hello", ",", " ", "world", "!" }, tokens)
      assert.are.equal(5, #m)
      assert.are.equal(0, m[1].byte)
      assert.are.equal(5, m[1].byte_len)
      assert.are.equal(5, m[2].byte)
      assert.are.equal(1, m[2].byte_len)
      assert.are.equal(7, m[4].byte)
      assert.are.equal(5, m[4].byte_len)
    end)

    it("tokenize keeps multi-byte letters inside their word run", function()
      -- "café" = 'c','a','f','é' → one word token spanning 5 bytes.
      local tokens, m = h.tokenize("caf\xc3\xa9")
      assert.are.same({ "caf\xc3\xa9" }, tokens)
      assert.are.equal(0, m[1].byte)
      assert.are.equal(5, m[1].byte_len)
    end)

    it("is_word_token distinguishes word runs from punctuation tokens", function()
      assert.is_true(h.is_word_token("foo"))
      assert.is_true(h.is_word_token("_x"))
      assert.is_true(h.is_word_token("\xc3\xa9"))
      assert.is_false(h.is_word_token(","))
      assert.is_false(h.is_word_token(" "))
      assert.is_false(h.is_word_token(""))
    end)

    it("diff_units returns [] when either side is empty", function()
      assert.are.same({}, h.diff_units({}, { "a" }))
      assert.are.same({}, h.diff_units({ "a" }, {}))
    end)

    it("INTRALINE_MAX_HUNKS is a positive integer", function()
      assert.is_true(h.INTRALINE_MAX_HUNKS >= 1)
    end)

    it("refinement_safe admits single-hunk sub-diffs regardless of overlap", function()
      -- One hunk cannot interleave, so even unrelated words (foo/bar) are safe.
      assert.is_true(h.refinement_safe({ "f", "o", "o" }, { "b", "a", "r" }, 1))
    end)

    it("refinement_safe admits multi-hunk sub-diffs with a shared prefix", function()
      -- "recieve" / "receive" share prefix "rec" and suffix "ve".
      assert.is_true(
        h.refinement_safe(
          { "r", "e", "c", "i", "e", "v", "e" },
          { "r", "e", "c", "e", "i", "v", "e" },
          2
        )
      )
    end)

    it("refinement_safe rejects multi-hunk sub-diffs with no substantial overlap", function()
      -- "param" / "return" share only a coincidental 'r'; refining would
      -- interleave the deleted and inserted chars.
      assert.is_false(
        h.refinement_safe({ "p", "a", "r", "a", "m" }, { "r", "e", "t", "u", "r", "n" }, 2)
      )
    end)

    it("refinement_safe rejects when hunk count exceeds the limit", function()
      assert.is_false(h.refinement_safe({ "a" }, { "b" }, h.INTRALINE_MAX_HUNKS + 1))
    end)
  end)

  describe("similarity gate", function()
    local function text_extmarks(bufnr)
      local marks = api.nvim_buf_get_extmarks(bufnr, inline_diff.ns, 0, -1, { details = true })
      local out = { hl = 0, inline = 0 }
      for _, m in ipairs(marks) do
        local d = m[4]
        if d.hl_group == "DiffviewDiffText" then
          out.hl = out.hl + 1
        end
        if d.virt_text and d.virt_text_pos == "inline" then
          out.inline = out.inline + 1
        end
      end
      return out
    end

    it("renders char-level highlights for similar paired lines", function()
      local bufnr = fresh_buf({ "hello brave world" })
      inline_diff.render(bufnr, { "hello world" }, { "hello brave world" })
      local t = text_extmarks(bufnr)
      assert.is_true(t.hl > 0, "expected DiffText on added chars for similar lines")
    end)

    it("skips char-level highlights when lines are too dissimilar (unified)", function()
      -- Two sentences sharing only the first clause; the divergent tails are
      -- completely different content that would otherwise produce fragmented
      -- char-level hunks.
      local old = "This is a plain, singular window. This is available in case"
      local new = "This is a plain, singular window with no diff rendering —"
      local bufnr = fresh_buf({ new })
      inline_diff.render(bufnr, { old }, { new })
      local t = text_extmarks(bufnr)
      assert.are.equal(0, t.hl, "expected no DiffText fragments on dissimilar pairing")
    end)

    it("skips inline deletions in overleaf for dissimilar pairings", function()
      local old = "This is a plain, singular window. This is available in case"
      local new = "This is a plain, singular window with no diff rendering —"
      local bufnr = fresh_buf({ new })
      inline_diff.render(bufnr, { old }, { new }, { style = "overleaf" })
      local t = text_extmarks(bufnr)
      assert.are.equal(0, t.inline, "expected no inline deletion virt_text on dissimilar pairing")
    end)

    it("falls back to block echo + line_hl in overleaf when char-level skips", function()
      -- When overleaf's char-level rendering is gated off, the paired
      -- modification would otherwise be invisible. Verify the fallback
      -- emits a DiffChange line_hl and a virt_line with the old content.
      local old = "This is a plain, singular window. This is available in case"
      local new = "This is a plain, singular window with no diff rendering —"
      local bufnr = fresh_buf({ new })
      inline_diff.render(bufnr, { old }, { new }, { style = "overleaf" })

      local hls = line_hls(extmarks(bufnr))
      assert.are.same({ { row = 0, hl = "DiffviewDiffChange" } }, hls)

      local vls = virt_line_hls(extmarks(bufnr))
      assert.are.same({ "DiffviewDiffDelete" }, vls)
    end)
  end)

  describe("intraline tokenization", function()
    -- Regression: per-character diffing matched coincidental letters
    -- ('t', 'e', 'm', 'i', '.') between "something." and "any tracked
    -- metric." and fragmented the change into interleaved per-char
    -- virt_text in overleaf. Word-level tokens keep the deleted word as
    -- a single strikethrough unit before the added phrase.
    it("renders multi-word replacements without char interleaving (overleaf)", function()
      local old = "# Print the log, showing only passes that changed something."
      local new = "# Print the log, showing only passes that changed any tracked metric."
      local bufnr = fresh_buf({ new })
      inline_diff.render(bufnr, { old }, { new }, { style = "overleaf" })

      local inlines = inline_virt_texts(extmarks(bufnr), "DiffviewDiffDeleteInline")
      assert.are.equal(1, #inlines, "expected a single inline deletion virt_text")
      assert.are.equal("something", inlines[1].text)
      -- Anchor sits before "any" in the new line.
      local anchor_at = ("# Print the log, showing only passes that changed "):len()
      assert.are.equal(anchor_at, inlines[1].col)
    end)

    it("refines 1:1 word replacements with char-level precision", function()
      -- "recieve" → "receive" is one word-level 1:1 pair, so the sub-diff
      -- kicks in. DiffText highlights should cover only the moved letter
      -- rather than the whole word.
      local bufnr = fresh_buf({ "receive" })
      inline_diff.render(bufnr, { "recieve" }, { "receive" })

      local ranges = char_ranges(extmarks(bufnr))
      assert.is_true(#ranges > 0, "expected char-level DiffText inside the word")
      for _, r in ipairs(ranges) do
        assert.is_true(
          r.finish - r.start < #"receive",
          "each highlight should be narrower than the full word"
        )
      end
    end)

    it("emits char-level inline deletions inside a 1:1 word replacement (overleaf)", function()
      local bufnr = fresh_buf({ "receive" })
      inline_diff.render(bufnr, { "recieve" }, { "receive" }, { style = "overleaf" })

      local inlines = inline_virt_texts(extmarks(bufnr), "DiffviewDiffDeleteInline")
      assert.is_true(#inlines >= 1, "expected inline deletion from char-level refinement")
      for _, v in ipairs(inlines) do
        assert.is_true(
          #v.text < #"recieve",
          "refined inline deletions must be sub-word, not the whole old word"
        )
      end
    end)

    it("treats multi-word replacements atomically (no intra-word refinement)", function()
      -- Replacing one word with multiple words is not a 1:1 pair, so the
      -- whole deleted word sits before the added tokens as a single
      -- strikethrough run rather than being split char-by-char.
      local bufnr = fresh_buf({ "any tracked metric" })
      inline_diff.render(bufnr, { "something" }, { "any tracked metric" }, { style = "overleaf" })

      local inlines = inline_virt_texts(extmarks(bufnr), "DiffviewDiffDeleteInline")
      assert.are.equal(1, #inlines)
      assert.are.equal("something", inlines[1].text)
    end)

    it("keeps punctuation swaps as atomic token hunks", function()
      -- A single-char punctuation change (is_word_token=false) must not
      -- trigger char-level refinement — the hunk stays at token level.
      local bufnr = fresh_buf({ "a; b" })
      inline_diff.render(bufnr, { "a, b" }, { "a; b" }, { style = "overleaf" })

      local inlines = inline_virt_texts(extmarks(bufnr), "DiffviewDiffDeleteInline")
      assert.are.equal(1, #inlines)
      assert.are.equal(",", inlines[1].text)
    end)

    it("ensure_eof_virt_lines_visible bumps topline so trailing deletions fit", function()
      -- Build a buffer large enough that `G` lands line N at the bottom of
      -- the window with virt_lines_below clipped. After adjustment, topline
      -- must rise enough that the 3 trailing virt_lines fit below the cursor.
      local new_lines = {}
      for i = 1, 20 do
        new_lines[i] = "line " .. i
      end
      local old_lines = {}
      for i = 1, 23 do
        old_lines[i] = "line " .. i
      end

      local bufnr = fresh_buf(new_lines)
      inline_diff.render(bufnr, old_lines, new_lines)

      local win = api.nvim_get_current_win()
      api.nvim_win_set_buf(win, bufnr)
      pcall(api.nvim_win_set_height, win, 13)
      api.nvim_win_set_cursor(win, { 20, 0 })

      local height = api.nvim_win_get_height(win)
      -- Force an initial topline that clips the EOF virt_lines (cursor sits
      -- at the very bottom row).
      vim.fn.winrestview({ topline = 20 - height + 1 })
      local before = vim.fn.winsaveview().topline

      inline_diff.ensure_eof_virt_lines_visible(bufnr, win)
      local after = vim.fn.winsaveview().topline

      assert.is_true(after > before, "topline should have risen to reveal EOF virt_lines")
      -- 3 virt_lines below line 20 in a 13-row window: cursor must sit at
      -- row height - below = 10, so topline = 20 - 10 + 1 = 11.
      assert.are.equal(11, after)
    end)

    it(
      "ensure_eof_virt_lines_visible is a no-op when the cursor is not on the last line",
      function()
        local bufnr = fresh_buf({ "a", "b", "c" })
        inline_diff.render(bufnr, { "a", "b", "c", "d", "e" }, { "a", "b", "c" })

        local win = api.nvim_get_current_win()
        api.nvim_win_set_buf(win, bufnr)
        api.nvim_win_set_cursor(win, { 1, 0 })

        local before = vim.fn.winsaveview().topline
        inline_diff.ensure_eof_virt_lines_visible(bufnr, win)
        assert.are.equal(before, vim.fn.winsaveview().topline)
      end
    )

    it("ensure_eof_virt_lines_visible is a no-op when there are no EOF virt_lines", function()
      local bufnr = fresh_buf({ "a", "b", "c" })
      local win = api.nvim_get_current_win()
      api.nvim_win_set_buf(win, bufnr)
      api.nvim_win_set_cursor(win, { 3, 0 })

      local before = vim.fn.winsaveview().topline
      inline_diff.ensure_eof_virt_lines_visible(bufnr, win)
      assert.are.equal(before, vim.fn.winsaveview().topline)
    end)

    it("ensure_bof_virt_lines_visible sets topfill so leading deletions render", function()
      -- 3 deleted lines before the first surviving line. `virt_lines_above`
      -- on row 0 are clipped at `topline=1` unless `topfill` is set.
      local new_lines = { "line 1", "line 2", "line 3" }
      local old_lines = { "gone 1", "gone 2", "gone 3", "line 1", "line 2", "line 3" }
      local bufnr = fresh_buf(new_lines)
      inline_diff.render(bufnr, old_lines, new_lines)

      local win = api.nvim_get_current_win()
      api.nvim_win_set_buf(win, bufnr)
      api.nvim_win_set_cursor(win, { 1, 0 })
      vim.fn.winrestview({ topline = 1, topfill = 0 })
      assert.are.equal(0, vim.fn.winsaveview().topfill or 0)

      inline_diff.ensure_bof_virt_lines_visible(bufnr, win)
      assert.are.equal(3, vim.fn.winsaveview().topfill or 0)
    end)

    it("ensure_bof_virt_lines_visible is a no-op when topline is not 1", function()
      local new_lines = {}
      for i = 1, 10 do
        new_lines[i] = "line " .. i
      end
      local old_lines = { "gone 1", "gone 2" }
      for i = 1, 10 do
        old_lines[#old_lines + 1] = "line " .. i
      end
      local bufnr = fresh_buf(new_lines)
      inline_diff.render(bufnr, old_lines, new_lines)

      local win = api.nvim_get_current_win()
      api.nvim_win_set_buf(win, bufnr)
      api.nvim_win_set_cursor(win, { 5, 0 })
      vim.fn.winrestview({ topline = 3, topfill = 0 })

      inline_diff.ensure_bof_virt_lines_visible(bufnr, win)
      assert.are.equal(0, vim.fn.winsaveview().topfill or 0)
    end)

    it("ensure_bof_virt_lines_visible is a no-op when there are no BOF virt_lines", function()
      local bufnr = fresh_buf({ "a", "b", "c" })
      local win = api.nvim_get_current_win()
      api.nvim_win_set_buf(win, bufnr)
      api.nvim_win_set_cursor(win, { 1, 0 })

      local before = vim.fn.winsaveview().topfill or 0
      inline_diff.ensure_bof_virt_lines_visible(bufnr, win)
      assert.are.equal(before, vim.fn.winsaveview().topfill or 0)
    end)

    it("ensure_bof_virt_lines_visible clears stale topfill when BOF deletions go away", function()
      -- Regression: topfill is window state, so a render that previously set
      -- it (for BOF virt_lines above line 1) needs to clear it on a later
      -- render where those deletions are gone; otherwise the viewport shows
      -- an empty filler band above line 1.
      local new_lines = { "line 1", "line 2", "line 3" }
      local old_lines = { "gone 1", "gone 2", "line 1", "line 2", "line 3" }
      local bufnr = fresh_buf(new_lines)
      inline_diff.render(bufnr, old_lines, new_lines)

      local win = api.nvim_get_current_win()
      api.nvim_win_set_buf(win, bufnr)
      api.nvim_win_set_cursor(win, { 1, 0 })
      vim.fn.winrestview({ topline = 1, topfill = 0 })
      inline_diff.ensure_bof_virt_lines_visible(bufnr, win)
      assert.are.equal(2, vim.fn.winsaveview().topfill or 0)

      -- Re-render with no BOF deletions; topfill must fall back to 0.
      inline_diff.render(bufnr, new_lines, new_lines)
      vim.fn.winrestview({ topline = 1, topfill = 2 })
      inline_diff.ensure_bof_virt_lines_visible(bufnr, win)
      assert.are.equal(0, vim.fn.winsaveview().topfill or 0)
    end)

    it("does not spuriously mark the trailing token as deleted when paired line grows", function()
      -- Regression: a 3-line function collapsed to 1 line pairs the first
      -- old line with the new single-line version. The old line ends at
      -- `)`; the new line has `)` at the same position and a long tail
      -- appended. Without a trailing newline in `diff_units` input,
      -- vim.diff flagged `)` as deleted+reinserted, emitting a spurious
      -- `)` strikethrough virt_text on the paired row.
      local old = "function M.get_status_icon(status)"
      local new = "function M.get_status_icon(status) return "
        .. "config.get_config().status_icons[status] or status end"
      local bufnr = fresh_buf({ new })
      inline_diff.render(bufnr, { old }, { new }, { style = "overleaf" })

      local inlines = inline_virt_texts(extmarks(bufnr), "DiffviewDiffDeleteInline")
      assert.are.equal(
        0,
        #inlines,
        "pure addition after a shared prefix should emit no inline deletions"
      )
      -- The appended tail is highlighted as added.
      local ranges = char_ranges(extmarks(bufnr))
      assert.is_true(#ranges > 0, "expected DiffText on the appended tail")
    end)

    it("refines a 1:N hunk where a word is split by inserted whitespace", function()
      -- Regression: `statusend` → `status end` was rendering as
      -- `[statusend]status end` (whole old word shown deleted, whole new
      -- phrase shown inserted), when the ideal display is a highlight on
      -- the inserted space — `status` and `end` are common substrings.
      -- The concat-based refinement path handles this as a single-hunk
      -- char-level insert.
      local bufnr = fresh_buf({ "status end" })
      inline_diff.render(bufnr, { "statusend" }, { "status end" }, { style = "overleaf" })

      -- No inline deletion virt_text — nothing was "deleted" at char level.
      local inlines = inline_virt_texts(extmarks(bufnr), "DiffviewDiffDeleteInline")
      assert.are.equal(0, #inlines)

      -- The single added character (the space) is highlighted.
      local ranges = char_ranges(extmarks(bufnr))
      assert.are.equal(1, #ranges)
      assert.are.equal(6, ranges[1].start)
      assert.are.equal(7, ranges[1].finish)
    end)

    it(
      "falls back to atomic word delete for 1:1 pairs with only a coincidental letter match",
      function()
        -- Regression: `param` and `return` share only a single `r`, so the
        -- char-level refinement produced two hunks whose fragments rendered
        -- as `---@[pa]r[am]eturn new stringboolean`. Multi-hunk refinement
        -- without a substantial shared prefix/suffix must fall back to
        -- word-level rendering so the old word stays intact.
        local old = "---@param new string"
        local new = "---@return boolean"
        local bufnr = fresh_buf({ new })
        inline_diff.render(bufnr, { old }, { new }, { style = "overleaf" })

        local inlines = inline_virt_texts(extmarks(bufnr), "DiffviewDiffDeleteInline")
        local texts = {}
        for _, v in ipairs(inlines) do
          texts[#texts + 1] = v.text
        end
        table.sort(texts)
        assert.are.same({ "new string", "param" }, texts)
      end
    )
  end)
end)
