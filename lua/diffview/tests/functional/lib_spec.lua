describe("diffview.lib", function()
  local lib = require("diffview.lib")
  local oop = require("diffview.oop")
  local RevType = require("diffview.vcs.rev").RevType

  -- Minimal stub classes to satisfy the ancestorof / instanceof checks without
  -- pulling in the full StandardView/FilePanel dependency chain.
  local StubView = oop.create_class("StubView")
  local DiffView = require("diffview.scene.views.diff.diff_view").DiffView

  local StubDiffView = oop.create_class("StubDiffView", DiffView)

  function StubDiffView:init(opt)
    self.adapter = opt.adapter
    self.rev_arg = opt.rev_arg
    self.path_args = opt.path_args
    self.left = opt.left
    self.right = opt.right
  end

  local function make_rev(rev_type, commit, stage)
    return { type = rev_type, commit = commit, stage = stage }
  end

  local function make_adapter(toplevel)
    return { ctx = { toplevel = toplevel } }
  end

  describe("find_existing_view", function()
    local saved_views

    before_each(function()
      saved_views = lib.views
      lib.views = {}
    end)

    after_each(function()
      lib.views = saved_views
    end)

    -- Regression: find_existing_view must distinguish views whose left/right
    -- revisions differ (e.g., --cached vs default).
    it("does not match when right rev type differs", function()
      local adapter = make_adapter("/repo")
      local local_rev = make_rev(RevType.LOCAL, nil, nil)
      local stage_rev = make_rev(RevType.STAGE, nil, 0)
      local commit_rev = make_rev(RevType.COMMIT, "abc123", nil)

      local view = StubDiffView({
        adapter = adapter,
        rev_arg = nil,
        path_args = {},
        left = commit_rev,
        right = local_rev,
      })
      table.insert(lib.views, view)

      -- Same toplevel/rev_arg/path_args but different right rev (--cached).
      local result = lib.find_existing_view(adapter, nil, {}, commit_rev, stage_rev)
      assert.is_nil(result)
    end)

    it("matches when all parameters including revs are equal", function()
      local adapter = make_adapter("/repo")
      local left = make_rev(RevType.COMMIT, "abc123", nil)
      local right = make_rev(RevType.LOCAL, nil, nil)

      local view = StubDiffView({
        adapter = adapter,
        rev_arg = "HEAD",
        path_args = { "src/" },
        left = left,
        right = right,
      })
      table.insert(lib.views, view)

      local result = lib.find_existing_view(adapter, "HEAD", { "src/" }, left, right)
      assert.are.equal(view, result)
    end)

    it("returns nil for empty views list", function()
      local adapter = make_adapter("/repo")
      local rev = make_rev(RevType.LOCAL, nil, nil)
      assert.is_nil(lib.find_existing_view(adapter, nil, {}, rev, rev))
    end)
  end)
end)
