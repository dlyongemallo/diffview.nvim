local helpers = require("diffview.tests.helpers")
local config = require("diffview.config")
local render = require("diffview.scene.views.file_history.render")

local eq = helpers.eq

local render_stat_bar = render._test.render_stat_bar
local render_file_stats = render._test.render_file_stats
local formatters = render._test.formatters

-- ---------------------------------------------------------------------------
-- Mock RenderComponent
-- ---------------------------------------------------------------------------

---@class MockRenderComponent
---@field lines string[][] Each element is { text, hl_group? }.

---Create a mock RenderComponent that records add_text / ln calls.
---@return MockRenderComponent
local function make_comp()
  local comp = { lines = { {} } }

  function comp:add_text(text, hl)
    local cur = self.lines[#self.lines]
    cur[#cur + 1] = { text = text, hl = hl }
  end

  function comp:ln()
    self.lines[#self.lines + 1] = {}
  end

  --- Flatten all recorded text into a single string.
  function comp:flat_text()
    local parts = {}
    for _, line in ipairs(self.lines) do
      for _, seg in ipairs(line) do
        parts[#parts + 1] = seg.text
      end
    end
    return table.concat(parts)
  end

  --- Return every segment whose hl group matches `hl`.
  function comp:segments_by_hl(hl)
    local result = {}
    for _, line in ipairs(self.lines) do
      for _, seg in ipairs(line) do
        if seg.hl == hl then
          result[#result + 1] = seg.text
        end
      end
    end
    return result
  end

  return comp
end

-- ---------------------------------------------------------------------------
-- Helpers shared with the _get_entry_by_file_offset tests
-- (Mirrors wrap_entries_spec.lua conventions.)
-- ---------------------------------------------------------------------------

---Create a stub file entry with an identifiable name.
---@param name string
---@return table
local function make_file(name)
  return {
    name = name,
    active = false,
    set_active = function(self, v)
      self.active = v
    end,
  }
end

---Create a stub log entry with the given file names.
---@param ... string
---@return table
local function make_entry(...)
  local files = {}
  for _, name in ipairs({ ... }) do
    files[#files + 1] = make_file(name)
  end
  return { files = files, folded = false }
end

---Build a minimal FileHistoryPanel-shaped table.
---@param entries table[]
---@param entry_idx integer
---@param file_idx integer
---@return table
local function make_panel(entries, entry_idx, file_idx)
  local FileHistoryPanel =
    require("diffview.scene.views.file_history.file_history_panel").FileHistoryPanel

  local panel = {
    entries = entries,
    single_file = false,
    cur_item = { entries[entry_idx], entries[entry_idx].files[file_idx] },
  }

  panel._get_entry_by_file_offset = FileHistoryPanel._get_entry_by_file_offset
  panel.num_items = FileHistoryPanel.num_items
  panel.set_cur_item = function(self, new_item)
    self.cur_item = new_item
    if self.cur_item and self.cur_item[2] then
      self.cur_item[2]:set_active(true)
    end
  end

  return panel
end

-- =========================================================================
-- Tests
-- =========================================================================

describe("file_history_render", function()
  local original_config

  before_each(function()
    original_config = vim.deepcopy(config.get_config())
  end)

  after_each(function()
    config.setup(original_config)
  end)

  -- -----------------------------------------------------------------------
  -- stat_style: render_stat_bar
  -- -----------------------------------------------------------------------

  describe("render_stat_bar", function()
    it("renders proportional plus/minus segments", function()
      local comp = make_comp()
      render_stat_bar(comp, 5, 3)

      local flat = comp:flat_text()
      -- Total is 8, which is below MAX_BAR_WIDTH so bar_width = 8.
      -- add_width = floor(5/8*8 + 0.5) = 5, del_width = 3.
      assert.truthy(flat:find("+++++"), "expected 5 plus signs")
      assert.truthy(flat:find("%-%-%-"), "expected 3 minus signs")
      -- Counter should show total.
      local counters = comp:segments_by_hl("DiffviewFilePanelCounter")
      eq("8 ", counters[1])
    end)

    it("caps bar width at MAX_BAR_WIDTH for large totals", function()
      local comp = make_comp()
      render_stat_bar(comp, 100, 100)

      -- bar_width = min(200, 20) = 20.
      -- add_width = floor(100/200*20 + 0.5) = 10, del_width = 10.
      local adds = comp:segments_by_hl("DiffviewFilePanelInsertions")
      local dels = comp:segments_by_hl("DiffviewFilePanelDeletions")
      eq(10, #adds[1])
      eq(10, #dels[1])
    end)

    it("handles 0 additions (all deletions)", function()
      local comp = make_comp()
      render_stat_bar(comp, 0, 5)

      local adds = comp:segments_by_hl("DiffviewFilePanelInsertions")
      local dels = comp:segments_by_hl("DiffviewFilePanelDeletions")
      eq(0, #adds)
      eq(5, #dels[1])
    end)

    it("handles 0 deletions (all additions)", function()
      local comp = make_comp()
      render_stat_bar(comp, 7, 0)

      local adds = comp:segments_by_hl("DiffviewFilePanelInsertions")
      local dels = comp:segments_by_hl("DiffviewFilePanelDeletions")
      eq(7, #adds[1])
      eq(0, #dels)
    end)

    it("produces no output when both additions and deletions are 0", function()
      local comp = make_comp()
      render_stat_bar(comp, 0, 0)

      eq("", comp:flat_text())
    end)
  end)

  -- -----------------------------------------------------------------------
  -- stat_style: render_file_stats routing
  -- -----------------------------------------------------------------------

  describe("render_file_stats", function()
    local stats = { additions = 4, deletions = 2 }

    it("shows only numbers for stat_style 'number'", function()
      local comp = make_comp()
      render_file_stats(comp, stats, "number")

      local flat = comp:flat_text()
      -- Number portion: " 4", ", ", "2".
      assert.truthy(flat:find("4"), "expected additions count")
      assert.truthy(flat:find("2"), "expected deletions count")
      -- No bar separator.
      assert.falsy(flat:find(" | "), "should not contain bar separator")
    end)

    it("shows only bar for stat_style 'bar'", function()
      local comp = make_comp()
      render_file_stats(comp, stats, "bar")

      local flat = comp:flat_text()
      -- Bar portion present.
      assert.truthy(flat:find(" | "), "expected bar separator")
      assert.truthy(flat:find("+"), "expected plus signs")
      -- No leading numeric portion (no comma separator).
      -- The flat text should start with the bar, not " 4, 2".
      assert.falsy(flat:find(", "), "should not contain number comma separator")
    end)

    it("shows both number and bar for stat_style 'both'", function()
      local comp = make_comp()
      render_file_stats(comp, stats, "both")

      local flat = comp:flat_text()
      assert.truthy(flat:find("4"), "expected additions count")
      assert.truthy(flat:find(", "), "expected number comma separator")
      assert.truthy(flat:find(" | "), "expected bar separator")
    end)

    it("skips bar when stats lack additions/deletions fields", function()
      local comp = make_comp()
      render_file_stats(comp, { additions = nil, deletions = nil }, "bar")

      eq("", comp:flat_text())
    end)
  end)

  -- -----------------------------------------------------------------------
  -- date_format
  -- -----------------------------------------------------------------------

  describe("date formatter", function()
    ---Call the real formatters.date and return the rendered date string.
    ---@param time integer
    ---@param rel string
    ---@param iso string
    ---@param date_format string
    ---@return string
    local function render_date(time, rel, iso, date_format)
      local conf = config.get_config()
      conf.file_history_panel.date_format = date_format
      config.setup(conf)

      local entry = { commit = { time = time, rel_date = rel, iso_date = iso } }
      local comp = make_comp()
      local ctx = { conf = config.get_config() }
      formatters.date(comp, entry, ctx)
      -- The formatter renders ", <date>"; strip the leading ", ".
      return comp:flat_text():sub(3)
    end

    it("returns rel_date for 'relative' mode", function()
      eq("2 hours ago", render_date(os.time(), "2 hours ago", "2026-03-31", "relative"))
    end)

    it("returns iso_date for 'iso' mode", function()
      eq("2026-03-31", render_date(os.time(), "2 hours ago", "2026-03-31", "iso"))
    end)

    it("returns rel_date for a recent commit in 'auto' mode", function()
      -- Commit from 1 day ago (well within the 3-month threshold).
      local recent_time = os.time() - (60 * 60 * 24)
      eq("1 day ago", render_date(recent_time, "1 day ago", "2026-03-30", "auto"))
    end)

    it("returns iso_date for an old commit in 'auto' mode", function()
      -- Commit from 6 months ago (exceeds the 3-month threshold).
      local old_time = os.time() - (60 * 60 * 24 * 30 * 6)
      eq("2025-09-30", render_date(old_time, "6 months ago", "2025-09-30", "auto"))
    end)

    it("treats unknown format as 'auto'", function()
      local recent_time = os.time() - 60
      eq("1 minute ago", render_date(recent_time, "1 minute ago", "2026-03-31", "something_else"))
    end)
  end)

  -- -----------------------------------------------------------------------
  -- subject_highlight
  -- -----------------------------------------------------------------------

  describe("subject_highlight", function()
    ---Call the real formatters.subject and return the highlight group it used.
    ---@param entry table
    ---@param is_selected boolean
    ---@return string
    local function render_subject_hl(entry, is_selected)
      entry.commit = entry.commit or { subject = "test" }
      local comp = make_comp()
      local ctx = {
        conf = config.get_config(),
        panel = { cur_item = { is_selected and entry or {} } },
      }
      formatters.subject(comp, entry, ctx)
      -- The subject is rendered as a single segment; return its hl group.
      return comp.lines[1][1].hl
    end

    it("uses DiffviewFilePanelFileName for 'plain' mode", function()
      local conf = config.get_config()
      conf.file_history_panel.subject_highlight = "plain"
      config.setup(conf)

      local entry = { has_remote_ref = true }
      eq("DiffviewFilePanelFileName", render_subject_hl(entry, false))
    end)

    it("uses DiffviewCommitRemoteRef for 'ref_aware' with remote ref", function()
      local conf = config.get_config()
      conf.file_history_panel.subject_highlight = "ref_aware"
      config.setup(conf)

      local entry = { has_remote_ref = true }
      eq("DiffviewCommitRemoteRef", render_subject_hl(entry, false))
    end)

    it("uses DiffviewCommitLocalOnly for 'ref_aware' without remote ref", function()
      local conf = config.get_config()
      conf.file_history_panel.subject_highlight = "ref_aware"
      config.setup(conf)

      local entry = { has_remote_ref = false }
      eq("DiffviewCommitLocalOnly", render_subject_hl(entry, false))
    end)

    it("uses DiffviewFilePanelSelected when entry is selected", function()
      local conf = config.get_config()
      conf.file_history_panel.subject_highlight = "ref_aware"
      config.setup(conf)

      local entry = { has_remote_ref = true }
      eq("DiffviewFilePanelSelected", render_subject_hl(entry, true))
    end)

    it("defaults to 'ref_aware'", function()
      eq("ref_aware", config.get_config().file_history_panel.subject_highlight)
    end)
  end)

  -- -----------------------------------------------------------------------
  -- date_format config default
  -- -----------------------------------------------------------------------

  describe("config defaults", function()
    it("defaults stat_style to 'number'", function()
      local c = config.get_config()
      eq("number", c.file_history_panel.stat_style)
    end)

    it("defaults date_format to 'auto'", function()
      local c = config.get_config()
      eq("auto", c.file_history_panel.date_format)
    end)
  end)

  -- -----------------------------------------------------------------------
  -- _get_entry_by_file_offset: cycling within a commit
  -- (Exercises the commit 318ce58 behaviour.)
  -- -----------------------------------------------------------------------

  describe("_get_entry_by_file_offset (intra-commit cycling)", function()
    -- Single entry with 4 files: a, b, c, d.
    local entries, panel

    before_each(function()
      entries = { make_entry("a", "b", "c", "d") }
      panel = make_panel(entries, 1, 1)
    end)

    describe("cycling forward within a commit", function()
      it("moves from file 1 to file 2", function()
        local e, f = panel:_get_entry_by_file_offset(1, 1, 1, true)
        eq(entries[1], e)
        eq(entries[1].files[2], f)
      end)

      it("moves from file 2 to file 4 with offset 2", function()
        local e, f = panel:_get_entry_by_file_offset(1, 2, 2, true)
        eq(entries[1], e)
        eq(entries[1].files[4], f)
      end)
    end)

    describe("cycling backward within a commit", function()
      it("moves from file 3 to file 2", function()
        local e, f = panel:_get_entry_by_file_offset(1, 3, -1, true)
        eq(entries[1], e)
        eq(entries[1].files[2], f)
      end)

      it("moves from file 4 to file 2 with offset -2", function()
        local e, f = panel:_get_entry_by_file_offset(1, 4, -2, true)
        eq(entries[1], e)
        eq(entries[1].files[2], f)
      end)
    end)

    describe("wrapping at boundaries (wrap = true)", function()
      it("wraps forward from the last file back to the first", function()
        -- Single entry: wrapping forward from file 4 should come back around.
        -- The delta after exhausting the current entry is 1, and since there
        -- is only one entry the loop condition (i ~= entry_idx) is immediately
        -- false, so we get nil.  This matches the production code: a single
        -- entry with wrap=true does not re-enter itself.
        local e, f = panel:_get_entry_by_file_offset(1, 4, 1, true)
        eq(nil, e)
        eq(nil, f)
      end)

      it("wraps backward from the first file back to the last", function()
        local e, f = panel:_get_entry_by_file_offset(1, 1, -1, true)
        eq(nil, e)
        eq(nil, f)
      end)
    end)

    describe("stopping at boundaries (wrap = false)", function()
      it("returns nil when moving forward past the last file", function()
        local e, f = panel:_get_entry_by_file_offset(1, 4, 1, false)
        eq(nil, e)
        eq(nil, f)
      end)

      it("returns nil when moving backward past the first file", function()
        local e, f = panel:_get_entry_by_file_offset(1, 1, -1, false)
        eq(nil, e)
        eq(nil, f)
      end)
    end)
  end)

  -- -----------------------------------------------------------------------
  -- _get_entry_by_file_offset: multi-entry cycling
  -- -----------------------------------------------------------------------

  describe("_get_entry_by_file_offset (multi-entry)", function()
    -- Layout: entry1 [a, b], entry2 [c], entry3 [d, e, f].
    local entries, panel

    before_each(function()
      entries = {
        make_entry("a", "b"),
        make_entry("c"),
        make_entry("d", "e", "f"),
      }
      panel = make_panel(entries, 1, 1)
    end)

    describe("cycling forward across entries", function()
      it("crosses from entry1 last file to entry2 first file", function()
        local e, f = panel:_get_entry_by_file_offset(1, 2, 1, false)
        eq(entries[2], e)
        eq(entries[2].files[1], f)
      end)

      it("skips entry2 when offset exceeds its size", function()
        -- From entry1 file 2, offset +2: crosses entry2 (1 file) -> entry3 file 1.
        local e, f = panel:_get_entry_by_file_offset(1, 2, 2, false)
        eq(entries[3], e)
        eq(entries[3].files[1], f)
      end)
    end)

    describe("cycling backward across entries", function()
      it("crosses from entry2 first file to entry1 last file", function()
        local e, f = panel:_get_entry_by_file_offset(2, 1, -1, false)
        eq(entries[1], e)
        eq(entries[1].files[2], f)
      end)

      it("skips entry2 when offset exceeds its size going backward", function()
        -- From entry3 file 1, offset -2: crosses entry2 (1 file) -> entry1 file 2.
        local e, f = panel:_get_entry_by_file_offset(3, 1, -2, false)
        eq(entries[1], e)
        eq(entries[1].files[2], f)
      end)
    end)

    describe("wrapping across entries (wrap = true)", function()
      it("wraps forward from the last file of the last entry", function()
        local e, f = panel:_get_entry_by_file_offset(3, 3, 1, true)
        eq(entries[1], e)
        eq(entries[1].files[1], f)
      end)

      it("wraps backward from the first file of the first entry", function()
        local e, f = panel:_get_entry_by_file_offset(1, 1, -1, true)
        eq(entries[3], e)
        eq(entries[3].files[3], f)
      end)
    end)

    describe("stopping at boundaries (wrap = false)", function()
      it("returns nil at the absolute end going forward", function()
        local e, f = panel:_get_entry_by_file_offset(3, 3, 1, false)
        eq(nil, e)
        eq(nil, f)
      end)

      it("returns nil at the absolute start going backward", function()
        local e, f = panel:_get_entry_by_file_offset(1, 1, -1, false)
        eq(nil, e)
        eq(nil, f)
      end)
    end)
  end)
end)
