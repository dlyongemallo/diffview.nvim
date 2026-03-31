local helpers = require("diffview.tests.helpers")
local config = require("diffview.config")
local vcs_utils = require("diffview.vcs.utils")

local eq = helpers.eq

describe("vcs.utils.is_merge_artifact", function()
  it("matches .orig files", function()
    eq(true, vcs_utils.is_merge_artifact("foo.orig"))
    eq(true, vcs_utils.is_merge_artifact("src/bar.lua.orig"))
    eq(true, vcs_utils.is_merge_artifact("deep/nested/path/file.txt.orig"))
  end)

  it("matches .BACKUP. files", function()
    eq(true, vcs_utils.is_merge_artifact("foo.BACKUP.12345.lua"))
    eq(true, vcs_utils.is_merge_artifact("src/foo.BACKUP.12345.lua"))
    eq(true, vcs_utils.is_merge_artifact("file.BACKUP.99999.txt"))
  end)

  it("matches .BASE. files", function()
    eq(true, vcs_utils.is_merge_artifact("foo.BASE.12345.lua"))
    eq(true, vcs_utils.is_merge_artifact("src/foo.BASE.12345.lua"))
    eq(true, vcs_utils.is_merge_artifact("file.BASE.99999.txt"))
  end)

  it("matches .LOCAL. files", function()
    eq(true, vcs_utils.is_merge_artifact("foo.LOCAL.12345.lua"))
    eq(true, vcs_utils.is_merge_artifact("src/foo.LOCAL.12345.lua"))
    eq(true, vcs_utils.is_merge_artifact("file.LOCAL.99999.txt"))
  end)

  it("matches .REMOTE. files", function()
    eq(true, vcs_utils.is_merge_artifact("foo.REMOTE.12345.lua"))
    eq(true, vcs_utils.is_merge_artifact("src/foo.REMOTE.12345.lua"))
    eq(true, vcs_utils.is_merge_artifact("file.REMOTE.99999.txt"))
  end)

  it("does not match normal files", function()
    eq(false, vcs_utils.is_merge_artifact("foo.lua"))
    eq(false, vcs_utils.is_merge_artifact("src/bar.txt"))
    eq(false, vcs_utils.is_merge_artifact("README.md"))
    eq(false, vcs_utils.is_merge_artifact("init.lua"))
  end)

  it("does not match files with artifact words only in the name", function()
    eq(false, vcs_utils.is_merge_artifact("BACKUP.md"))
    eq(false, vcs_utils.is_merge_artifact("BASE.txt"))
    eq(false, vcs_utils.is_merge_artifact("LOCAL.lua"))
    eq(false, vcs_utils.is_merge_artifact("REMOTE.lua"))
    eq(false, vcs_utils.is_merge_artifact("original.lua"))
    eq(false, vcs_utils.is_merge_artifact("src/original.txt"))
  end)

  it("does not match files ending in .origin or similar", function()
    eq(false, vcs_utils.is_merge_artifact("foo.original"))
    eq(false, vcs_utils.is_merge_artifact("src/bar.origins"))
  end)
end)

describe("vcs.utils.filter_merge_artifacts", function()
  local saved_config

  before_each(function()
    saved_config = vim.deepcopy(config.get_config())
  end)

  after_each(function()
    config.setup(saved_config)
  end)

  ---Helper to create a minimal file-like table with a path field.
  ---@param path string
  ---@return table
  local function make_file(path)
    return { path = path }
  end

  it("returns the list unmodified when hide_merge_artifacts is false", function()
    config.setup({ hide_merge_artifacts = false })

    local files = {
      make_file("foo.lua"),
      make_file("bar.orig"),
      make_file("baz.BACKUP.123.lua"),
    }
    local result = vcs_utils.filter_merge_artifacts(files)

    eq(3, #result)
    eq(files, result)
  end)

  it("filters out artifacts when hide_merge_artifacts is true", function()
    config.setup({ hide_merge_artifacts = true })

    local files = {
      make_file("foo.lua"),
      make_file("bar.orig"),
      make_file("baz.BACKUP.123.lua"),
    }
    local result = vcs_utils.filter_merge_artifacts(files)

    eq(1, #result)
    eq("foo.lua", result[1].path)
  end)

  it("returns an empty list when given an empty list", function()
    config.setup({ hide_merge_artifacts = true })

    local result = vcs_utils.filter_merge_artifacts({})

    eq(0, #result)
  end)

  it("returns an empty list when all files are artifacts", function()
    config.setup({ hide_merge_artifacts = true })

    local files = {
      make_file("foo.orig"),
      make_file("bar.BACKUP.123.lua"),
      make_file("baz.BASE.456.txt"),
      make_file("qux.LOCAL.789.lua"),
      make_file("quux.REMOTE.012.txt"),
    }
    local result = vcs_utils.filter_merge_artifacts(files)

    eq(0, #result)
  end)

  it("preserves all files when none are artifacts", function()
    config.setup({ hide_merge_artifacts = true })

    local files = {
      make_file("src/init.lua"),
      make_file("README.md"),
      make_file("tests/test_spec.lua"),
    }
    local result = vcs_utils.filter_merge_artifacts(files)

    eq(3, #result)
    eq("src/init.lua", result[1].path)
    eq("README.md", result[2].path)
    eq("tests/test_spec.lua", result[3].path)
  end)

  it("filters a mixed list keeping only non-artifacts", function()
    config.setup({ hide_merge_artifacts = true })

    local files = {
      make_file("src/init.lua"),
      make_file("src/init.lua.orig"),
      make_file("lib/utils.lua"),
      make_file("lib/utils.BACKUP.55555.lua"),
      make_file("lib/utils.BASE.55555.lua"),
      make_file("lib/utils.LOCAL.55555.lua"),
      make_file("lib/utils.REMOTE.55555.lua"),
      make_file("README.md"),
    }
    local result = vcs_utils.filter_merge_artifacts(files)

    eq(3, #result)
    eq("src/init.lua", result[1].path)
    eq("lib/utils.lua", result[2].path)
    eq("README.md", result[3].path)
  end)

  it("does not modify the original table", function()
    config.setup({ hide_merge_artifacts = true })

    local files = {
      make_file("keep.lua"),
      make_file("remove.orig"),
    }
    local result = vcs_utils.filter_merge_artifacts(files)

    eq(1, #result)
    eq(2, #files)
  end)
end)
