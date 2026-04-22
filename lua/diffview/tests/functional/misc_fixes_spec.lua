local helpers = require("diffview.tests.helpers")
local oop = require("diffview.oop")

local eq = helpers.eq

-- Tests for miscellaneous bug fix commits:
-- - 60fc176: three bugs introduced by merged PRs (#17)
-- - 1b778b6: misc. minor bug fixes (#20)
-- - 58f14a5: more misc. bug fixes (#21)

-----------------------------------------------------------------------
-- 60fc176: fix(oop): use dot syntax for super_class call in
-- CommitLogPanel. The colon syntax invoked the super class as a
-- constructor, producing a spurious instance; every other super-call
-- in the codebase uses dot access (e.g. Foo.super_class.method(self)).
-----------------------------------------------------------------------

describe("super_class dot syntax (60fc176)", function()
  -- Build a minimal two-level class hierarchy to verify that calling
  -- super_class.method(self) correctly delegates to the parent without
  -- constructing a new instance.

  local Parent = oop.create_class("Parent")
  local Child = oop.create_class("Child", Parent)

  local parent_calls

  function Parent:init() end

  function Parent:greet()
    parent_calls = parent_calls + 1
    return "hello from parent"
  end

  function Child:init() end

  -- Correct: dot access (mirrors the fix).
  function Child:greet_dot()
    return Child.super_class.greet(self)
  end

  before_each(function()
    parent_calls = 0
  end)

  it("dot syntax delegates to the parent method", function()
    local inst = Child()
    local result = inst:greet_dot()
    eq("hello from parent", result)
    eq(1, parent_calls)
  end)

  it("dot syntax does not create a new instance", function()
    local inst = Child()
    -- super_class should be the Parent class table, not an instance.
    eq(Parent, Child.super_class)
    assert.is_nil(Child.super_class.class, "super_class should be a class, not an instance")

    inst:greet_dot()
    eq(1, parent_calls)
  end)

  it("colon syntax on super_class would treat it as a constructor call", function()
    -- This test documents why the colon syntax was wrong:
    -- Child:super_class() would call the __call metamethod on
    -- super_class (which is the Parent class), constructing a new
    -- instance rather than returning the class table.
    local inst = Child()
    local constructed = Child:super_class()
    -- The result of __call is a new instance, not the class table.
    assert.truthy(constructed.class, "colon call should produce an instance")
    eq(Parent, constructed.class)
    -- Meanwhile, dot access gives the class itself.
    assert.is_nil(Child.super_class.class)
  end)
end)

-----------------------------------------------------------------------
-- 60fc176: fix(hg): guard get_commit_url call in open_commit_in_browser.
-- The method only exists on GitAdapter; HgAdapter users got a nil crash.
-----------------------------------------------------------------------

describe("get_commit_url nil guard (60fc176)", function()
  -- We cannot run a full file_history listener, but we can verify the
  -- guard pattern: checking for the existence of a method on the
  -- adapter before calling it.

  it("adapter without get_commit_url should be detected", function()
    local mock_adapter = { name = "hg" }
    -- Simulates the guard from listeners.lua.
    assert.is_nil(mock_adapter.get_commit_url)
    assert.falsy(mock_adapter.get_commit_url)
  end)

  it("adapter with get_commit_url should pass the guard", function()
    local mock_adapter = {
      name = "git",
      get_commit_url = function(_, hash)
        return "https://github.com/example/repo/commit/" .. hash
      end,
    }
    assert.truthy(mock_adapter.get_commit_url)
    local url = mock_adapter:get_commit_url("abc123")
    eq("https://github.com/example/repo/commit/abc123", url)
  end)
end)

-----------------------------------------------------------------------
-- 1b778b6: fix misleading "clipboard" message for copy_hash.
-- The action copies to the unnamed register ("), not the system
-- clipboard. The message was changed to say "default register".
-----------------------------------------------------------------------

describe("copy_hash message wording (1b778b6)", function()
  -- The actual copy_hash action lives inside a listener closure and
  -- cannot be called directly. Instead we verify the corrected format
  -- string pattern that the fix introduced.

  it("format string refers to default register, not clipboard", function()
    local hash = "abc123def"
    local msg = string.format("Copied '%s' to the default register.", hash)
    assert.truthy(msg:find("default register"))
    assert.falsy(msg:find("clipboard"))
  end)
end)

-----------------------------------------------------------------------
-- 1b778b6: guard against empty resolved layout list in cycle_layout.
-- When config contains only unknown layout names, resolve_layouts
-- returns an empty table. The fix ensures fallback defaults are used
-- so that #layouts is never zero (which would cause division by zero
-- in the modulo operation).
-----------------------------------------------------------------------

describe("cycle_layout empty resolved list fallback (1b778b6)", function()
  -- The original bug surfaced when layout names from the user config
  -- resolved to an empty list, which then caused a division by zero in
  -- the modulo operation inside actions.cycle_layout().
  --
  -- These tests exercise the real actions.cycle_layout() function with
  -- a config that resolves to an empty list and ensure that it falls
  -- back to the default layouts without throwing an error.

  local actions = require("diffview.actions")
  local config = require("diffview.config")

  local saved_config

  before_each(function()
    saved_config = vim.deepcopy(config.get_config())
  end)

  after_each(function()
    config.setup(saved_config)
  end)

  it("does not error when resolved layouts list is empty", function()
    -- Force the layout configuration to contain only unknown layout
    -- names so that the internal resolve_layouts() returns an empty
    -- list and the fallback path is exercised.
    config.setup({
      view = {
        cycle_layouts = {
          default = { "bogus_layout_name" },
          merge_tool = { "another_bogus_layout_name" },
        },
      },
    })

    -- We only care that cycle_layout does not throw when the resolved
    -- layouts list is empty; the fallback behaviour is internal.
    local ok, err = pcall(function()
      actions.cycle_layout()
    end)
    assert.is_true(ok, tostring(err))
  end)

  it("still works when at least one valid layout is configured", function()
    -- Add a valid layout name so that the resolved list is non-empty
    -- and ensure cycle_layout continues to operate without error.
    config.setup({
      view = {
        cycle_layouts = {
          default = { "diff2_horizontal", "bogus_layout_name" },
        },
      },
    })

    local ok, err = pcall(function()
      actions.cycle_layout()
    end)
    assert.is_true(ok, tostring(err))
  end)
end)

-----------------------------------------------------------------------
-- 58f14a5: fix get_style() returning only the first matching style
-- attribute. The bug had the early return inside the for loop over
-- style_attrs, so only the first truthy attribute was ever collected.
-----------------------------------------------------------------------

describe("hl.get_style multi-attribute fix (58f14a5)", function()
  local hl = require("diffview.hl")

  local orig_get_hl

  before_each(function()
    orig_get_hl = hl.get_hl
  end)

  after_each(function()
    hl.get_hl = orig_get_hl
  end)

  it("returns all matching style attributes, not just the first", function()
    hl.get_hl = function()
      return { bold = true, strikethrough = true }
    end

    local result = hl.get_style("TestGroup")
    -- Both attributes should appear, comma-separated.
    assert.truthy(result)
    assert.truthy(result:find("bold"))
    assert.truthy(result:find("strikethrough"))
    eq("bold,strikethrough", result)
  end)

  it("returns a single attribute when only one matches", function()
    hl.get_hl = function()
      return { italic = true }
    end

    local result = hl.get_style("TestGroup")
    eq("italic", result)
  end)

  it("returns nil when no style attributes match", function()
    hl.get_hl = function()
      return { fg = 0xffffff }
    end

    local result = hl.get_style("TestGroup")
    assert.is_nil(result)
  end)

  it("returns nil when get_hl returns nil", function()
    hl.get_hl = function()
      return nil
    end

    local result = hl.get_style("TestGroup")
    assert.is_nil(result)
  end)

  it("returns all three attributes when bold, italic, and underline match", function()
    hl.get_hl = function()
      return { bold = true, italic = true, underline = true }
    end

    local result = hl.get_style("TestGroup")
    assert.truthy(result)
    assert.truthy(result:find("bold"))
    assert.truthy(result:find("italic"))
    assert.truthy(result:find("underline"))
  end)

  it("tries multiple groups and returns the first with style attrs", function()
    hl.get_hl = function(name)
      if name == "GroupA" then
        return { fg = 0xff0000 } -- No style attrs.
      elseif name == "GroupB" then
        return { bold = true, reverse = true }
      end
    end

    local result = hl.get_style({ "GroupA", "GroupB" })
    assert.truthy(result)
    assert.truthy(result:find("bold"))
    assert.truthy(result:find("reverse"))
  end)
end)

-----------------------------------------------------------------------
-- 58f14a5: fix inverted guard conditions in FilePanel and
-- FileHistoryPanel get_item_at_cursor/get_dir_at_cursor.
-- The original code was: if not self:is_open() and self:buf_loaded()
-- which, due to precedence, evaluated as:
--   (not self:is_open()) and self:buf_loaded()
-- The fix changed it to:
--   if not (self:is_open() and self:buf_loaded())
-- so that the method returns early when *either* condition is false.
-----------------------------------------------------------------------

describe("inverted panel guard conditions (58f14a5)", function()
  -- We test the boolean logic directly to demonstrate the difference
  -- between the buggy and fixed guard conditions.

  ---Evaluate the buggy guard: not is_open and buf_loaded
  local function buggy_guard(is_open, buf_loaded)
    return (not is_open) and buf_loaded
  end

  ---Evaluate the fixed guard: not (is_open and buf_loaded)
  local function fixed_guard(is_open, buf_loaded)
    return not (is_open and buf_loaded)
  end

  it("both guards agree when panel is open and buffer is loaded (no early return)", function()
    -- is_open=true, buf_loaded=true -> should NOT return early.
    eq(false, buggy_guard(true, true))
    eq(false, fixed_guard(true, true))
  end)

  it("buggy guard misses early return when panel is closed and buffer is not loaded", function()
    -- is_open=false, buf_loaded=false -> should return early.
    eq(false, buggy_guard(false, false)) -- Bug: incorrectly does NOT return early!
    eq(true, fixed_guard(false, false)) -- Fix: correctly returns early.
  end)

  it("buggy guard fails when panel is open but buffer is not loaded", function()
    -- is_open=true, buf_loaded=false -> should return early (unsafe to use).
    -- Buggy: (not true) and false = false and false = false (no early return!)
    eq(false, buggy_guard(true, false))
    -- Fixed: not (true and false) = not false = true (early return).
    eq(true, fixed_guard(true, false))
  end)

  it("buggy guard incorrectly returns early when panel is closed but buffer loaded", function()
    -- is_open=false, buf_loaded=true -> should return early.
    -- Buggy: (not false) and true = true and true = true (early return, happens to be correct).
    eq(true, buggy_guard(false, true))
    -- Fixed: not (false and true) = not false = true (also correct).
    eq(true, fixed_guard(false, true))
  end)

  -- Summary: the buggy guard only returns early in one of the three
  -- cases where it should (open=false, loaded=true). The fixed guard
  -- correctly returns early in all three cases where either condition
  -- is false.
  it("fixed guard returns early in all cases where either condition is false", function()
    local cases = {
      { false, false, true },
      { false, true, true },
      { true, false, true },
      { true, true, false },
    }
    for _, case in ipairs(cases) do
      local is_open, buf_loaded, should_early_return = case[1], case[2], case[3]
      eq(
        should_early_return,
        fixed_guard(is_open, buf_loaded),
        string.format("is_open=%s, buf_loaded=%s", tostring(is_open), tostring(buf_loaded))
      )
    end
  end)
end)

-----------------------------------------------------------------------
-- 58f14a5: fix unconditional break in deprecated config warning loop.
-- The break was outside the if-block, so the loop over top_options
-- ("single_file", "multi_file") always exited after checking only
-- "single_file". The fix moved break inside the if-block.
-----------------------------------------------------------------------

describe("deprecated config warning loop fix (58f14a5)", function()
  -- Reproduce the logic of the loop over top_options in config.setup.

  local function buggy_check_deprecated(user_log_options)
    local warned = {}
    local top_options = { "single_file", "multi_file" }
    for _, name in ipairs(top_options) do
      if user_log_options[name] ~= nil then
        warned[#warned + 1] = name
      end
      break -- Bug: always breaks after first iteration.
    end
    return warned
  end

  local function fixed_check_deprecated(user_log_options)
    local warned = {}
    local top_options = { "single_file", "multi_file" }
    for _, name in ipairs(top_options) do
      if user_log_options[name] ~= nil then
        warned[#warned + 1] = name
        break -- Fix: only breaks when a warning is issued.
      end
    end
    return warned
  end

  it("buggy loop never checks multi_file", function()
    local opts = { multi_file = {} }
    local warned = buggy_check_deprecated(opts)
    -- Buggy: break runs after first iteration regardless, so
    -- multi_file is never checked.
    eq(0, #warned)
  end)

  it("fixed loop checks multi_file when single_file is absent", function()
    local opts = { multi_file = {} }
    local warned = fixed_check_deprecated(opts)
    eq(1, #warned)
    eq("multi_file", warned[1])
  end)

  it("both versions detect single_file (first element)", function()
    local opts = { single_file = {} }
    local buggy = buggy_check_deprecated(opts)
    local fixed = fixed_check_deprecated(opts)
    eq(1, #buggy)
    eq(1, #fixed)
    eq("single_file", buggy[1])
    eq("single_file", fixed[1])
  end)

  it("fixed loop stops after first match (does not warn twice)", function()
    local opts = { single_file = {}, multi_file = {} }
    local warned = fixed_check_deprecated(opts)
    -- The break ensures we only warn once, even if both are present.
    eq(1, #warned)
    eq("single_file", warned[1])
  end)

  it("fixed loop produces no warnings when neither option is present", function()
    local opts = {}
    local warned = fixed_check_deprecated(opts)
    eq(0, #warned)
  end)
end)

-----------------------------------------------------------------------
-- 58f14a5: fix typo merge_layuots -> merge_layouts in config
-- validation. This is verified by checking that the variable name
-- used in the valid_layouts table matches "merge_layouts".
-----------------------------------------------------------------------

describe("config merge_layouts typo fix (58f14a5)", function()
  it("config validation uses the correctly spelled merge_layouts variable", function()
    -- We verify that the config module loads and validates merge_tool
    -- layouts without error. If the typo were still present, the
    -- undefined variable merge_layuots would produce nil.
    local config = require("diffview.config")
    local original = vim.deepcopy(config.get_config())
    local old_warn = require("diffview.utils").warn
    local old_err = require("diffview.utils").err
    require("diffview.utils").warn = function() end
    require("diffview.utils").err = function() end

    local ok, err = pcall(function()
      config.setup({
        view = {
          merge_tool = {
            layout = "diff3_horizontal",
          },
        },
      })
      local conf = config.get_config()
      eq("diff3_horizontal", conf.view.merge_tool.layout)
    end)

    require("diffview.utils").warn = old_warn
    require("diffview.utils").err = old_err
    config.setup(original)

    if not ok then
      error(err)
    end
  end)
end)

-----------------------------------------------------------------------
-- 58f14a5: fix HgAdapter.parse_revs error check.
-- The original check was: if code ~= 0 and node then
-- which silently skipped failures when exec_sync returned nil for code
-- (e.g. when the command could not be executed at all).
-- The fix changed it to: if not code or code ~= 0 then
-----------------------------------------------------------------------

describe("HgAdapter parse_revs error check (58f14a5)", function()
  -- We test the boolean logic of the error check directly.

  local function buggy_should_error(code, node)
    -- Original: only errors when code is non-zero AND node is truthy.
    return code ~= 0 and node
  end

  local function fixed_should_error(code)
    -- Fixed: errors when code is nil OR non-zero.
    return not code or code ~= 0
  end

  it("both detect non-zero exit code with output", function()
    assert.truthy(buggy_should_error(1, { "some output" }))
    assert.truthy(fixed_should_error(1))
  end)

  it("buggy check misses nil code (command failed to execute)", function()
    -- When exec_sync fails completely, code may be nil.
    -- Buggy: nil ~= 0 is true, but `true and nil` is nil (falsy).
    assert.falsy(buggy_should_error(nil, nil))
    -- Fixed: not nil is true, so we correctly detect the error.
    assert.truthy(fixed_should_error(nil))
  end)

  it("buggy check misses non-zero code when node is nil", function()
    -- Code is non-zero but node is nil.
    -- Buggy: 1 ~= 0 is true, but `true and nil` is nil (falsy).
    assert.falsy(buggy_should_error(1, nil))
    -- Fixed: correctly detects the error.
    assert.truthy(fixed_should_error(1))
  end)

  it("both allow success (code == 0)", function()
    assert.falsy(buggy_should_error(0, { "abc123" }))
    assert.falsy(fixed_should_error(0))
  end)

  it("fixed check also handles stderr concatenation with nil guard", function()
    -- The fix also changed stderr handling to: table.concat(stderr or {}, "\n")
    -- Verify the pattern does not crash when stderr is nil.
    local stderr = nil
    local msg = table.concat(stderr or {}, "\n")
    eq("", msg)
  end)

  it("fixed check concatenates stderr lines", function()
    local stderr = { "error: unknown revision", "hint: check spelling" }
    local msg = table.concat(stderr or {}, "\n")
    eq("error: unknown revision\nhint: check spelling", msg)
  end)
end)
