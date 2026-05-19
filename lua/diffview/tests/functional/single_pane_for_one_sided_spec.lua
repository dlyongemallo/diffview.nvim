local FileEntry = require("diffview.scene.file_entry").FileEntry
local Diff1Raw = require("diffview.scene.layouts.diff_1_raw").Diff1Raw
local Diff2Hor = require("diffview.scene.layouts.diff_2_hor").Diff2Hor
local RevType = require("diffview.vcs.rev").RevType
local config = require("diffview.config")

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

describe("view.single_pane_for_one_sided", function()
  local original

  before_each(function()
    original = vim.deepcopy(config.get_config())
  end)

  after_each(function()
    config.setup(original)
  end)

  describe("config schema", function()
    it("defaults to false", function()
      config.setup({})
      assert.is_false(config.get_config().view.single_pane_for_one_sided)
    end)

    it("can be set to true via user config", function()
      config.setup({ view = { single_pane_for_one_sided = true } })
      assert.is_true(config.get_config().view.single_pane_for_one_sided)
    end)

    it("does not affect unrelated view options when toggled", function()
      config.setup({ view = { single_pane_for_one_sided = true } })
      local conf = config.get_config()
      assert.equals("diff2_horizontal", conf.view.default.layout)
      assert.equals(0, conf.view.foldlevel)
    end)
  end)

  describe("FileEntry.with_layout layout selection", function()
    it("falls through to the default layout when the option is off", function()
      config.setup({})
      local entry = make_entry("A")
      assert.equals(Diff2Hor, entry.layout.class)
    end)

    it("substitutes Diff1Raw for an added (A) file when enabled", function()
      config.setup({ view = { single_pane_for_one_sided = true } })
      local entry = make_entry("A")
      assert.equals(Diff1Raw, entry.layout.class)
    end)

    it("substitutes Diff1Raw for an untracked (?) file when enabled", function()
      config.setup({ view = { single_pane_for_one_sided = true } })
      local entry = make_entry("?")
      assert.equals(Diff1Raw, entry.layout.class)
    end)

    it("substitutes Diff1Raw for a deleted (D) file when enabled", function()
      config.setup({ view = { single_pane_for_one_sided = true } })
      local entry = make_entry("D")
      assert.equals(Diff1Raw, entry.layout.class)
    end)

    it("leaves modified (M) files on the default Diff2 layout", function()
      config.setup({ view = { single_pane_for_one_sided = true } })
      local entry = make_entry("M")
      assert.equals(Diff2Hor, entry.layout.class)
    end)

    it("leaves renamed (R) files on the default Diff2 layout", function()
      config.setup({ view = { single_pane_for_one_sided = true } })
      local entry = make_entry("R", { oldpath = "old.txt" })
      assert.equals(Diff2Hor, entry.layout.class)
    end)

    it("leaves pinned_b_file entries on the pin-aware Diff2 layout", function()
      config.setup({ view = { single_pane_for_one_sided = true } })
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
      config.setup({ view = { single_pane_for_one_sided = true } })
      local entry = make_entry("A")
      assert.equals(RevType.LOCAL, entry.layout.b.file.rev.type)
    end)

    it("swaps in revs.a for deleted files (pre-deletion content)", function()
      config.setup({ view = { single_pane_for_one_sided = true } })
      local rev_a = commit_rev()
      local entry = make_entry("D", { revs = { a = rev_a, b = local_rev() } })
      assert.equals(rev_a, entry.layout.b.file.rev)
    end)

    it("drops the unwindowed a-side File when the b-side is substituted", function()
      -- Avoids fetching the same scratch content twice.
      config.setup({ view = { single_pane_for_one_sided = true } })
      local entry = make_entry("D")
      assert.is_nil(entry.layout.a_file)
    end)

    it("keeps the unwindowed a-side File for non-substituted Diff1Raw entries", function()
      -- Needed by `convert_layout` to round-trip back to Diff2 without
      -- losing the COMMIT-side file metadata.
      config.setup({ view = { single_pane_for_one_sided = true } })
      local entry = make_entry("A")
      assert.is_not_nil(entry.layout.a_file)
    end)
  end)

  describe("Diff1Raw layout shape", function()
    it("owned_files includes the unwindowed a_file", function()
      config.setup({ view = { single_pane_for_one_sided = true } })
      local entry = make_entry("A")
      local owned = entry.layout:owned_files()
      assert.is_true(vim.tbl_contains(owned, entry.layout.a_file))
      assert.is_true(vim.tbl_contains(owned, entry.layout.b.file))
    end)

    it("get_file_for('a') returns the unwindowed a_file", function()
      config.setup({ view = { single_pane_for_one_sided = true } })
      local entry = make_entry("A")
      assert.equals(entry.layout.a_file, entry.layout:get_file_for("a"))
    end)

    it("get_file_for('b') returns nil when the b-side was substituted", function()
      -- convert_layout's fallback rebuilds a natural b-side with the right
      -- nulled flag instead of carrying the substituted COMMIT-rev File
      -- into a Diff2's b-slot.
      config.setup({ view = { single_pane_for_one_sided = true } })
      local entry = make_entry("D")
      assert.is_nil(entry.layout:get_file_for("b"))
    end)

    it("get_file_for('b') delegates to the base when not substituted", function()
      config.setup({ view = { single_pane_for_one_sided = true } })
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
end)
