local async = require("diffview.async")
local lazy = require("diffview.lazy")
local Window = require("diffview.scene.window").Window
local Layout = require("diffview.scene.layout").Layout
local oop = require("diffview.oop")

local Diff1 = lazy.access("diffview.scene.layouts.diff_1", "Diff1") ---@type Diff1|LazyModule
local Diff3 = lazy.access("diffview.scene.layouts.diff_3", "Diff3") ---@type Diff3|LazyModule
local RevType = lazy.access("diffview.vcs.rev", "RevType") ---@type RevType|LazyModule

local await = async.await

local M = {}

---@class Diff4 : Layout
---@field a Window
---@field b Window
---@field c Window
---@field d Window
local Diff4 = oop.create_class("Diff4", Layout)

---@alias Diff4.WindowSymbol "a"|"b"|"c"|"d"

---@class Diff4.init.Opt
---@field a vcs.File
---@field b vcs.File
---@field c vcs.File
---@field d vcs.File
---@field winid_a integer
---@field winid_b integer
---@field winid_c integer
---@field winid_d integer

---@param opt Diff4.init.Opt
function Diff4:init(opt)
  self:super()
  self.a = Window({ file = opt.a, id = opt.winid_a })
  self.b = Window({ file = opt.b, id = opt.winid_b })
  self.c = Window({ file = opt.c, id = opt.winid_c })
  self.d = Window({ file = opt.d, id = opt.winid_d })
  self:use_windows(self.a, self.b, self.c, self.d)
end

---@param file vcs.File
function Diff4:set_file_a(file)
  self.a:set_file(file)
  file.symbol = "a"
end

---@param file vcs.File
function Diff4:set_file_b(file)
  self.b:set_file(file)
  file.symbol = "b"
end

---@param file vcs.File
function Diff4:set_file_c(file)
  self.c:set_file(file)
  file.symbol = "c"
end

---@param file vcs.File
function Diff4:set_file_d(file)
  self.d:set_file(file)
  file.symbol = "d"
end

---@param self Diff4
---@param entry FileEntry
Diff4.use_entry = async.void(function(self, entry)
  local layout = entry.layout --[[@as Diff4 ]]
  assert(layout:instanceof(Diff4))

  self:set_file_a(layout.a.file)
  self:set_file_b(layout.b.file)
  self:set_file_c(layout.c.file)
  self:set_file_d(layout.d.file)

  if self:is_valid() then
    await(self:open_files())
  end
end)

function Diff4:get_main_win()
  return self.b
end

---@param layout Diff1
---@return Diff1
function Diff4:to_diff1(layout)
  assert(layout:instanceof(Diff1.__get()))

  return layout({ a = self:get_main_win().file })
end

---@param layout Diff3
---@return Diff3
function Diff4:to_diff3(layout)
  assert(layout:instanceof(Diff3.__get()))
  return layout({
    a = self.a.file,
    b = self.b.file,
    c = self.c.file,
  })
end

---@override
---@param rev Rev
---@param status string Git status symbol.
---@param sym Diff4.WindowSymbol
function Diff4.should_null(rev, status, sym)
  assert(sym == "a" or sym == "b" or sym == "c" or sym == "d")

  if rev.type == RevType.LOCAL then
    return status == "D"

  elseif rev.type == RevType.COMMIT then
    if sym == "a" then
      return vim.tbl_contains({ "?", "A" }, status)
    end

    return status == "D"

  elseif rev.type == RevType.STAGE then
    if rev.stage == 0 then
      if sym == "a" then
        return vim.tbl_contains({ "?", "A" }, status)
      end

      return status == "D"
    end

    -- Merge stages (1..3) can be absent depending on conflict type.
    -- This is resolved at file load time by checking stage blob existence.
    return false
  end

  error(("Unexpected state! %s, %s, %s"):format(rev, status, sym))
end

M.Diff4 = Diff4
return M
