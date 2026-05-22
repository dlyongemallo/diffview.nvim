local oop = require("diffview.oop")
local Commit = require("diffview.vcs.commit").Commit

local M = {}

---@class JjCommit : Commit
local JjCommit = oop.create_class("JjCommit", Commit)

---@param opt table
function JjCommit:init(opt)
  self:super(opt)

  -- jj's `author.timestamp().format("%s")` is already an absolute UTC epoch,
  -- so unlike `HgCommit` we never subtract `time_offset` from `time` -- the
  -- offset is purely a display hint for `Commit.time_to_iso`.
  if opt.time_offset then
    self.time_offset = JjCommit.parse_time_offset(opt.time_offset)
  else
    self.time_offset = 0
  end

  self.iso_date = Commit.time_to_iso(self.time, self.time_offset)
end

---Parse jj's `%z` format (e.g. `+0200`, `-0500`) into seconds. Returns 0 on
---empty or malformed input.
---@param raw string?
---@return integer
function JjCommit.parse_time_offset(raw)
  if not raw or raw == "" then
    return 0
  end

  local sign, h, m = vim.trim(raw):match("([+-])(%d%d):?(%d%d)$")
  if not sign then
    return 0
  end

  local seconds = tonumber(h) * 3600 + tonumber(m) * 60
  return sign == "-" and -seconds or seconds
end

M.JjCommit = JjCommit
return M
