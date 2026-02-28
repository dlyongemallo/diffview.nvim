local helpers = require("diffview.tests.helpers")
local config = require("diffview.config")
local utils = require("diffview.utils")

local eq = helpers.eq

---Create a stub file entry with an identifiable name.
---@param name string
---@return table
local function make_file(name)
  return {
    name = name,
    active = false,
    set_active = function(self, v) self.active = v end,
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

---Build a minimal FileHistoryPanel-shaped table with the given entries
---and cur_item pointing at (entry_idx, file_idx).
---@param entries table[]
---@param entry_idx integer
---@param file_idx integer
---@return table
local function make_panel(entries, entry_idx, file_idx)
  local FileHistoryPanel = require(
    "diffview.scene.views.file_history.file_history_panel"
  ).FileHistoryPanel

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

describe("diffview.wrap_entries", function()
  -- Save and restore config around the entire suite.
  local original_config

  before_each(function()
    original_config = vim.deepcopy(config.get_config())
  end)

  after_each(function()
    config.setup(original_config)
  end)

  -- ──────────────────────────────────────────────────────────────────
  -- _get_entry_by_file_offset: the core cross-entry navigation logic
  -- ──────────────────────────────────────────────────────────────────

  describe("_get_entry_by_file_offset", function()
    -- Layout: entry1 [a, b, c], entry2 [d, e], entry3 [f, g, h, i]
    local entries, panel

    before_each(function()
      entries = {
        make_entry("a", "b", "c"),
        make_entry("d", "e"),
        make_entry("f", "g", "h", "i"),
      }
      panel = make_panel(entries, 1, 1)
    end)

    describe("within a single entry", function()
      it("moves forward inside the same entry", function()
        local e, f = panel:_get_entry_by_file_offset(1, 1, 1, true)
        eq(entries[1], e)
        eq(entries[1].files[2], f)
      end)

      it("moves backward inside the same entry", function()
        local e, f = panel:_get_entry_by_file_offset(1, 3, -1, true)
        eq(entries[1], e)
        eq(entries[1].files[2], f)
      end)

      -- Within-entry navigation is the same regardless of wrap.
      it("moves forward inside the same entry (no wrap)", function()
        local e, f = panel:_get_entry_by_file_offset(1, 1, 1, false)
        eq(entries[1], e)
        eq(entries[1].files[2], f)
      end)
    end)

    describe("across entry boundaries (wrap = true)", function()
      it("wraps forward from the last file of the last entry", function()
        local e, f = panel:_get_entry_by_file_offset(3, 4, 1, true)
        eq(entries[1], e)
        eq(entries[1].files[1], f)
      end)

      it("wraps backward from the first file of the first entry", function()
        local e, f = panel:_get_entry_by_file_offset(1, 1, -1, true)
        eq(entries[3], e)
        eq(entries[3].files[4], f)
      end)

      it("moves forward from the last file of a middle entry", function()
        local e, f = panel:_get_entry_by_file_offset(1, 3, 1, true)
        eq(entries[2], e)
        eq(entries[2].files[1], f)
      end)

      it("moves backward from the first file of a middle entry", function()
        local e, f = panel:_get_entry_by_file_offset(2, 1, -1, true)
        eq(entries[1], e)
        eq(entries[1].files[3], f)
      end)
    end)

    describe("across entry boundaries (wrap = false)", function()
      it("moves forward from the last file of a middle entry", function()
        local e, f = panel:_get_entry_by_file_offset(1, 3, 1, false)
        eq(entries[2], e)
        eq(entries[2].files[1], f)
      end)

      it("moves backward from the first file of a middle entry", function()
        local e, f = panel:_get_entry_by_file_offset(2, 1, -1, false)
        eq(entries[1], e)
        eq(entries[1].files[3], f)
      end)

      it("stops at the last file when navigating forward past the end", function()
        local e, f = panel:_get_entry_by_file_offset(3, 4, 1, false)
        eq(nil, e)
        eq(nil, f)
      end)

      it("stops at the first file when navigating backward past the start", function()
        local e, f = panel:_get_entry_by_file_offset(1, 1, -1, false)
        eq(nil, e)
        eq(nil, f)
      end)

      it("skips entries correctly with a large offset", function()
        -- From entry1 file1, offset +6 should land on entry3 file1.
        -- entry1 has 2 remaining (files 2,3), entry2 has 2, so 2+2=4
        -- consumed; delta after entry2 = 6-2-2 = 2, but let's be exact:
        -- delta = 6 - (3 - 1) = 4, entry2 has 2 files (4-2=2), entry3
        -- needs delta=2 so files[2] = "g".
        local e, f = panel:_get_entry_by_file_offset(1, 1, 6, false)
        eq(entries[3], e)
        eq(entries[3].files[2], f)
      end)

      it("clamps a large forward offset at the boundary", function()
        -- From entry3 file3, offset +5 exceeds total remaining files.
        local e, f = panel:_get_entry_by_file_offset(3, 3, 5, false)
        eq(nil, e)
        eq(nil, f)
      end)
    end)
  end)

  -- ──────────────────────────────────────────────────────────────────
  -- FilePanel: flat-list next_file / prev_file
  -- ──────────────────────────────────────────────────────────────────

  describe("FilePanel next_file / prev_file", function()
    local FilePanel = require("diffview.scene.views.diff.file_panel").FilePanel
    local files

    ---Build a minimal FilePanel-shaped table.
    local function make_file_panel(file_list, cur_idx)
      files = {}
      for _, name in ipairs(file_list) do
        files[#files + 1] = make_file(name)
      end

      return {
        listing_style = "list",
        cur_file = files[cur_idx],
        files = {
          len = function() return #files end,
          iter = function()
            local i = 0
            return function()
              i = i + 1
              if i <= #files then return i, files[i] end
            end
          end,
        },
        ordered_file_list = FilePanel.ordered_file_list,
        set_cur_file = FilePanel.set_cur_file,
        next_file = FilePanel.next_file,
        prev_file = FilePanel.prev_file,
      }
    end

    describe("wrap_entries = true", function()
      before_each(function()
        config.setup({ wrap_entries = true })
      end)

      it("wraps forward from the last file", function()
        local fp = make_file_panel({ "a", "b", "c" }, 3)
        local result = fp:next_file()
        eq(files[1], result)
      end)

      it("wraps backward from the first file", function()
        local fp = make_file_panel({ "a", "b", "c" }, 1)
        local result = fp:prev_file()
        eq(files[3], result)
      end)
    end)

    describe("wrap_entries = false", function()
      before_each(function()
        config.setup({ wrap_entries = false })
      end)

      it("moves forward normally in the middle", function()
        local fp = make_file_panel({ "a", "b", "c" }, 1)
        local result = fp:next_file()
        eq(files[2], result)
      end)

      it("moves backward normally in the middle", function()
        local fp = make_file_panel({ "a", "b", "c" }, 3)
        local result = fp:prev_file()
        eq(files[2], result)
      end)

      it("returns nil at the last file going forward", function()
        local fp = make_file_panel({ "a", "b", "c" }, 3)
        local result = fp:next_file()
        eq(nil, result)
      end)

      it("returns nil at the first file going backward", function()
        local fp = make_file_panel({ "a", "b", "c" }, 1)
        local result = fp:prev_file()
        eq(nil, result)
      end)
    end)
  end)
end)
