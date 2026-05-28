local FileEntry = require("diffview.scene.file_entry").FileEntry
local async = require("diffview.async")
local Diff1 = require("diffview.scene.layouts.diff_1").Diff1
local Diff1Inline = require("diffview.scene.layouts.diff_1_inline").Diff1Inline
local Diff1Raw = require("diffview.scene.layouts.diff_1_raw").Diff1Raw
local Diff2Hor = require("diffview.scene.layouts.diff_2_hor").Diff2Hor
local RevType = require("diffview.vcs.rev").RevType
local config = require("diffview.config")
local helpers = require("diffview.tests.helpers")

local function commit_rev()
  return {
    type = RevType.COMMIT,
    commit = "abc1234567",
    object_name = function(_, n)
      return ("abc1234567"):sub(1, n or 10)
    end,
  }
end

local function local_rev()
  -- `vcs.File:init` always evaluates the winbar `object_path` substitution
  -- via `rev:object_name`, regardless of rev type. Stub it for LOCAL too.
  return {
    type = RevType.LOCAL,
    object_name = function(_, n)
      return ("0"):rep(n or 10)
    end,
  }
end

local function make_entry(status, opts)
  opts = opts or {}
  local adapter = { ctx = { toplevel = vim.uv.cwd() } }
  return FileEntry.with_layout(opts.layout_class or Diff2Hor, {
    adapter = adapter,
    path = opts.path or "foo.txt",
    oldpath = opts.oldpath,
    status = status,
    kind = "working",
    revs = opts.revs or { a = commit_rev(), b = local_rev() },
    pinned_b_file = opts.pinned_b_file,
  })
end

describe("view.one_sided_layout", function()
  local original

  before_each(function()
    original = vim.deepcopy(config.get_config())
  end)

  after_each(function()
    config.setup(original)
  end)

  describe("config schema", function()
    it('defaults to "default"', function()
      config.setup({})
      assert.equals("default", config.get_config().view.one_sided_layout)
    end)

    it('can be set to "raw" via user config', function()
      config.setup({ view = { one_sided_layout = "raw" } })
      assert.equals("raw", config.get_config().view.one_sided_layout)
    end)

    it("does not affect unrelated view options when toggled", function()
      config.setup({ view = { one_sided_layout = "raw" } })
      local conf = config.get_config()
      assert.equals("diff2_horizontal", conf.view.default.layout)
      assert.equals(0, conf.view.foldlevel)
    end)
  end)

  describe("FileEntry.with_layout layout selection", function()
    it('falls through to the default layout when option is "default"', function()
      config.setup({})
      local entry = make_entry("A")
      assert.equals(Diff2Hor, entry.layout.class)
    end)

    it('substitutes Diff1Raw for an added (A) Diff2 entry when "raw"', function()
      config.setup({ view = { one_sided_layout = "raw" } })
      local entry = make_entry("A")
      assert.equals(Diff1Raw, entry.layout.class)
    end)

    it('substitutes Diff1Raw for an untracked (?) Diff2 entry when "raw"', function()
      config.setup({ view = { one_sided_layout = "raw" } })
      local entry = make_entry("?")
      assert.equals(Diff1Raw, entry.layout.class)
    end)

    it('substitutes Diff1Raw for a deleted (D) Diff2 entry when "raw"', function()
      config.setup({ view = { one_sided_layout = "raw" } })
      local entry = make_entry("D")
      assert.equals(Diff1Raw, entry.layout.class)
    end)

    it('substitutes Diff1Raw for an added (A) Diff1 entry when "raw"', function()
      config.setup({ view = { one_sided_layout = "raw" } })
      local entry = make_entry("A", { layout_class = Diff1 })
      assert.equals(Diff1Raw, entry.layout.class)
    end)

    it('substitutes Diff1Raw for a deleted (D) Diff1 entry when "raw"', function()
      -- The substitution is more than cosmetic for status D: Diff1.should_null
      -- nulls the b-side, but Diff1Raw shows pre-deletion content from revs.a.
      config.setup({ view = { one_sided_layout = "raw" } })
      local entry = make_entry("D", { layout_class = Diff1 })
      assert.equals(Diff1Raw, entry.layout.class)
    end)

    it("leaves Diff1Inline entries alone (coherent one-sided rendering)", function()
      -- `diff1_inline` renders one-sided content itself, so `"raw"` doesn't
      -- substitute `Diff1Raw` for it (#199).
      config.setup({ view = { one_sided_layout = "raw" } })
      assert.equals(Diff1Inline, make_entry("A", { layout_class = Diff1Inline }).layout.class)
      assert.equals(Diff1Inline, make_entry("D", { layout_class = Diff1Inline }).layout.class)
    end)

    it("leaves modified (M) files on the default Diff2 layout", function()
      config.setup({ view = { one_sided_layout = "raw" } })
      local entry = make_entry("M")
      assert.equals(Diff2Hor, entry.layout.class)
    end)

    it("leaves renamed (R) files on the default Diff2 layout", function()
      config.setup({ view = { one_sided_layout = "raw" } })
      local entry = make_entry("R", { oldpath = "old.txt" })
      assert.equals(Diff2Hor, entry.layout.class)
    end)

    it("leaves pinned_b_file entries on the pin-aware Diff2 layout", function()
      config.setup({ view = { one_sided_layout = "raw" } })
      local Diff2HorPinned = require("diffview.scene.layouts.diff_2_hor_pinned").Diff2HorPinned
      local rev_b = local_rev()
      local shared = {
        path = "foo.txt",
        absolute_path = vim.fn.tempname() .. "-missing",
      } --[[@as vcs.File ]]
      local entry = make_entry("D", {
        layout_class = Diff2HorPinned,
        revs = { a = commit_rev(), b = rev_b },
        pinned_b_file = shared,
      })
      assert.equals(Diff2HorPinned, entry.layout.class)
    end)
  end)

  describe("b-side rev substitution", function()
    it("uses the LOCAL b-rev for added files (editable on-disk buffer)", function()
      config.setup({ view = { one_sided_layout = "raw" } })
      local entry = make_entry("A")
      assert.equals(RevType.LOCAL, entry.layout.b.file.rev.type)
    end)

    it("swaps in revs.a for deleted files (pre-deletion content)", function()
      config.setup({ view = { one_sided_layout = "raw" } })
      local rev_a = commit_rev()
      local entry = make_entry("D", { revs = { a = rev_a, b = local_rev() } })
      assert.equals(rev_a, entry.layout.b.file.rev)
    end)

    it("drops the unwindowed a-side File when the b-side is substituted", function()
      -- Avoids fetching the same scratch content twice.
      config.setup({ view = { one_sided_layout = "raw" } })
      local entry = make_entry("D")
      assert.is_nil(entry.layout.a_file)
    end)

    it("keeps the unwindowed a-side File for non-substituted Diff1Raw entries", function()
      -- Needed by `convert_layout` to round-trip back to Diff2 without
      -- losing the COMMIT-side file metadata.
      config.setup({ view = { one_sided_layout = "raw" } })
      local entry = make_entry("A")
      assert.is_not_nil(entry.layout.a_file)
    end)
  end)

  describe("Diff1Raw layout shape", function()
    it("owned_files includes the unwindowed a_file", function()
      config.setup({ view = { one_sided_layout = "raw" } })
      local entry = make_entry("A")
      local owned = entry.layout:owned_files()
      assert.is_true(vim.tbl_contains(owned, entry.layout.a_file))
      assert.is_true(vim.tbl_contains(owned, entry.layout.b.file))
    end)

    it("get_file_for('a') returns the unwindowed a_file", function()
      config.setup({ view = { one_sided_layout = "raw" } })
      local entry = make_entry("A")
      assert.equals(entry.layout.a_file, entry.layout:get_file_for("a"))
    end)

    it("get_file_for('b') returns nil when the b-side was substituted", function()
      -- convert_layout's fallback rebuilds a natural b-side with the right
      -- nulled flag instead of carrying the substituted COMMIT-rev File
      -- into a Diff2's b-slot.
      config.setup({ view = { one_sided_layout = "raw" } })
      local entry = make_entry("D")
      assert.is_nil(entry.layout:get_file_for("b"))
    end)

    it("get_file_for('b') delegates to the base when not substituted", function()
      config.setup({ view = { one_sided_layout = "raw" } })
      local entry = make_entry("A")
      assert.equals(entry.layout.b.file, entry.layout:get_file_for("b"))
    end)

    it("should_null returns false for the b slot", function()
      assert.is_false(Diff1Raw.should_null(local_rev(), "A", "b"))
      assert.is_false(Diff1Raw.should_null(commit_rev(), "D", "b"))
    end)

    it("registers as a known layout name", function()
      local cls = config.name_to_layout("diff1_raw")
      assert.equals(Diff1Raw, cls)
    end)
  end)

  describe("Diff1Inline old-side binary gating", function()
    -- Minimal `self` for `_load_old_lines`: an a-side file plus a b-side
    -- window. The mock adapter records each `is_binary` probe.
    local function make_self(opts)
      local calls = {}
      local a_file = {
        path = "foo.txt",
        rev = commit_rev(),
        nulled = false,
        adapter = {
          is_binary = function()
            calls[#calls + 1] = true
            return opts.is_binary_result
          end,
        },
        is_valid = function()
          return false
        end,
        produce_data = async.wrap(function(_, callback)
          callback(nil, opts.old_lines or { "x" })
        end),
      }
      return { a_file = a_file, b = { file = { nulled = opts.b_nulled } } }, calls
    end

    it(
      "treats a deleted file's binary old side as binary",
      helpers.async_test(function()
        config.setup({})
        local self, calls = make_self({ b_nulled = true, is_binary_result = true })
        helpers.eq({}, async.await(Diff1Inline._load_old_lines(self)))
        assert.equals(1, #calls)
      end)
    )

    it(
      "skips the old-side probe for a non-nulled (modified) b-side",
      helpers.async_test(function()
        config.setup({})
        local self, calls = make_self({ b_nulled = false, is_binary_result = true })
        helpers.eq({ "x" }, async.await(Diff1Inline._load_old_lines(self)))
        assert.equals(0, #calls)
      end)
    )
  end)
end)
