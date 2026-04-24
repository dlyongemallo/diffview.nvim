local utils = require("diffview.utils")
local vcs_utils = require("diffview.vcs.utils")

local M = {}

---@class GitAdapter.LogData
---@field left_hash? string
---@field right_hash string
---@field merge_hash? string
---@field author string
---@field time integer
---@field time_offset string
---@field rel_date string
---@field ref_names string
---@field reflog_selector string
---@field subject string
---@field namestat? string[]
---@field numstat? string[]
---@field diff? diff.FileEntry[]
---@field valid? boolean

-- Git's `--raw` output produces colon-prefixed lines (namestat) and
-- `--numstat` produces tab-separated numeric lines.  This function
-- separates the two from a combined data stream starting at `seek`.
--
-- namestat: `:100644 100644 abc123 def456 M\tfile.lua`
-- numstat:  `1\t1\tfile.lua`

---@param data string[]
---@param seek? integer
---@return string[] namestat
---@return string[] numstat
---@return integer data_end # First unprocessed data index.
function M.structure_stat_data(data, seek)
  local namestat, numstat = {}, {}
  local i = seek or 1

  while data[i] do
    if data[i]:match("^:+[0-7]") then
      namestat[#namestat + 1] = data[i]
    elseif data[i]:match("^[%d-]+\t[%d-]+\t") then
      numstat[#numstat + 1] = data[i]
    else
      -- We have hit unrelated data.
      break
    end
    i = i + 1
  end

  return namestat, numstat, i
end

---Structure raw file history log output into a LogData table.
---@param stat_data string[]
---@param keep_diff? boolean
---@return GitAdapter.LogData data
function M.structure_fh_data(stat_data, keep_diff)
  local right_hash, left_hash, merge_hash = unpack(utils.str_split(stat_data[1]))
  local time_offset = utils.str_split(stat_data[4])[3]

  ---@type GitAdapter.LogData
  local ret = {
    left_hash = left_hash ~= "" and left_hash or nil,
    right_hash = right_hash,
    merge_hash = merge_hash,
    author = stat_data[2],
    time = tonumber(stat_data[3]) or 0,
    time_offset = time_offset,
    rel_date = stat_data[5],
    ref_names = stat_data[6] and stat_data[6]:sub(3) or "",
    reflog_selector = stat_data[7] and stat_data[7]:sub(3) or "",
    subject = stat_data[8] and stat_data[8]:sub(3) or "",
  }

  local namestat, numstat = M.structure_stat_data(stat_data, 9)
  ret.namestat = namestat
  ret.numstat = numstat

  if keep_diff then
    ret.diff = vcs_utils.parse_diff(stat_data)
  end

  -- Soft validate the data.
  ret.valid = #namestat == #numstat
    and pcall(vim.validate, {
      left_hash = { ret.left_hash, "string", true },
      right_hash = { ret.right_hash, "string" },
      merge_hash = { ret.merge_hash, "string", true },
      author = { ret.author, "string" },
      time = { ret.time, "number" },
      time_offset = { ret.time_offset, "string" },
      rel_date = { ret.rel_date, "string" },
      ref_names = { ret.ref_names, "string" },
      reflog_selector = { ret.reflog_selector, "string" },
      subject = { ret.subject, "string" },
    })

  return ret
end

---@class GitAdapter.ParsedNamestat
---@field status string
---@field name string
---@field oldname? string
---@field stats? { additions: integer, deletions: integer }

---Parse a single namestat + numstat line pair into structured data.
---@param namestat_line string
---@param numstat_line string
---@return GitAdapter.ParsedNamestat
function M.parse_namestat_entry(namestat_line, numstat_line)
  local num_parents = #(namestat_line:match("^(:+)"))
  local offset = (num_parents + 1) * 2 + 1
  local namestat_fields

  local j = 1
  for idx in namestat_line:gmatch("%s+()") do
    ---@cast idx -string, +integer
    j = j + 1
    if j == offset then
      namestat_fields = utils.str_split(namestat_line:sub(idx), "\t")
      break
    end
  end

  if not namestat_fields then
    error(
      ("Malformed namestat line: insufficient fields (expected %d whitespace-separated groups): %s"):format(
        offset - 1,
        namestat_line
      )
    )
  end

  local status = namestat_fields[1]:match("^%a%a?")
  local name, oldname

  if num_parents == 1 and namestat_fields[3] then
    -- Rename.
    oldname = namestat_fields[2]
    name = namestat_fields[3]
  else
    name = namestat_fields[2]
  end

  local stats = {
    additions = tonumber(numstat_line:match("^%d+")),
    deletions = tonumber(numstat_line:match("^%d+%s+(%d+)")),
  }

  if not stats.additions or not stats.deletions then
    stats = nil
  end

  return {
    status = status,
    name = name,
    oldname = oldname,
    stats = stats,
  }
end

return M
