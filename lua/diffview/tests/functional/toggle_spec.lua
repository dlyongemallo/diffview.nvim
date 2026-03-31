local helpers = require("diffview.tests.helpers")

local eq = helpers.eq

describe("diffview.toggle", function()
  local diffview = require("diffview")
  local lib = require("diffview.lib")

  local stubs = {}
  local call_log

  --- Replace tbl[key] with val, automatically restored in after_each.
  local function stub(tbl, key, val)
    stubs[#stubs + 1] = { tbl, key, tbl[key] }
    tbl[key] = val
  end

  before_each(function()
    call_log = {}

    stub(diffview, "open", function(args)
      call_log[#call_log + 1] = { fn = "open", args = args }
    end)
    stub(diffview, "close", function()
      call_log[#call_log + 1] = { fn = "close" }
    end)
  end)

  after_each(function()
    for i = #stubs, 1, -1 do
      local s = stubs[i]
      s[1][s[2]] = s[3]
    end
    stubs = {}
  end)

  it("calls open when no view exists", function()
    stub(lib, "get_current_view", function() return nil end)

    diffview.toggle({})

    eq(1, #call_log)
    eq("open", call_log[1].fn)
  end)

  it("calls close when a view exists", function()
    stub(lib, "get_current_view", function() return { tabpage = 1 } end)

    diffview.toggle({})

    eq(1, #call_log)
    eq("close", call_log[1].fn)
  end)

  it("passes args through to open", function()
    stub(lib, "get_current_view", function() return nil end)

    local args = { "--staged", "HEAD~2" }
    diffview.toggle(args)

    eq(1, #call_log)
    eq("open", call_log[1].fn)
    eq(args, call_log[1].args)
  end)

  it("does not call open when a view exists", function()
    stub(lib, "get_current_view", function() return { tabpage = 1 } end)

    diffview.toggle({})

    for _, entry in ipairs(call_log) do
      assert.are_not.equal("open", entry.fn)
    end
  end)

  it("does not call close when no view exists", function()
    stub(lib, "get_current_view", function() return nil end)

    diffview.toggle({})

    for _, entry in ipairs(call_log) do
      assert.are_not.equal("close", entry.fn)
    end
  end)
end)
