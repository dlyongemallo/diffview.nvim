-- Verify `M.defaults`, `@class DiffviewConfig`, and `@class DiffviewConfig.user`
-- declare the same set of top-level keys.
--
-- The check is purely source-based so that keys explicitly assigned `nil` in
-- `M.defaults` (e.g. `preferred_adapter`, `rename_threshold`) are still
-- counted; runtime `pairs()` would skip them.
--
-- Checks (top level only):
--   1. every key in `M.defaults` has a `@field` entry on both classes;
--   2. every `@field` entry on either class has a key in `M.defaults`;
--   3. `DiffviewConfig` and `DiffviewConfig.user` declare the same set of keys.
--
-- Run with:
--   nvim --headless -i NONE -n -u NONE -c "luafile scripts/check_config_schema.lua"

local function repo_root()
  local f = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(f, ":p:h:h")
end

local function read_file(path)
  local file = assert(io.open(path))
  local content = file:read("*a")
  file:close()
  return content
end

local root = repo_root()
local src = read_file(root .. "/lua/diffview/config.lua")

---Match a Lua long-bracket opening (`[[`, `[=[`, `[==[`, ...) at `p`.
---Returns `(level, body_start)` where `level` is the number of `=` signs and
---`body_start` is just past the final `[`, or nil if no long bracket opens
---at `p`.
---@param p integer
---@return integer? level
---@return integer? body_start
local function long_open(p)
  if src:sub(p, p) ~= "[" then
    return nil
  end
  local q = p + 1
  while src:sub(q, q) == "=" do
    q = q + 1
  end
  if src:sub(q, q) == "[" then
    return q - p - 1, q + 1
  end
  return nil
end

---Find the matching long-bracket close (`]]`, `]=]`, ...) for the given level,
---starting at `p`. Returns the position just past the close, or nil.
---@param p integer
---@param level integer
---@return integer?
local function long_close(p, level)
  local needle = "]" .. string.rep("=", level) .. "]"
  local _, e = src:find(needle, p, true)
  return e and (e + 1) or nil
end

---Extract top-level keys from the `M.defaults = { ... }` source block,
---including keys explicitly assigned `nil` (which `pairs()` would skip).
---@return table<string, true>?
---@return string? err
local function extract_defaults_keys()
  local _, eq_end = src:find("M%.defaults%s*=%s*")
  if not eq_end then
    return nil, "could not locate M.defaults assignment"
  end
  local open = src:find("{", eq_end + 1)
  if not open then
    return nil, "M.defaults: opening brace not found"
  end

  local keys = {}
  local depth = 1
  local pos = open + 1
  local len = #src
  local in_string = nil

  while pos <= len do
    local c = src:sub(pos, pos)
    if in_string then
      if c == "\\" then
        pos = pos + 2
      elseif c == in_string then
        in_string = nil
        pos = pos + 1
      else
        pos = pos + 1
      end
    elseif c == "-" and src:sub(pos + 1, pos + 1) == "-" then
      -- Comment. Either a `--[[ ... ]]` block or a line comment to EOL.
      local level, body_start = long_open(pos + 2)
      if level then
        local after = long_close(body_start, level)
        if not after then
          return nil, "M.defaults: unterminated block comment"
        end
        pos = after
      else
        local nl = src:find("\n", pos)
        pos = nl and (nl + 1) or (len + 1)
      end
    elseif c == '"' or c == "'" then
      in_string = c
      pos = pos + 1
    elseif c == "[" then
      -- Possible long-bracket string (`[[...]]`, `[=[...]=]`, ...); short
      -- brackets like `["A"]` fall through to the single-char advance.
      local level, body_start = long_open(pos)
      if level then
        local after = long_close(body_start, level)
        if not after then
          return nil, "M.defaults: unterminated long string"
        end
        pos = after
      else
        pos = pos + 1
      end
    elseif c == "{" then
      depth = depth + 1
      pos = pos + 1
    elseif c == "}" then
      depth = depth - 1
      if depth == 0 then
        break
      end
      pos = pos + 1
    elseif depth == 1 and c:match("[%a_]") then
      local _, e, name = src:find("^([%w_]+)%s*=", pos)
      if name then
        keys[name] = true
        pos = e + 1
      else
        pos = pos + 1
      end
    else
      pos = pos + 1
    end
  end

  if depth ~= 0 then
    return nil, "M.defaults: unbalanced braces"
  end

  return keys
end

---Extract top-level `@field` names from a `---@class <name>` block. The block
---runs from the `@class` header until the next `---@class` declaration or the
---first non-comment line. Blank lines within the block are tolerated so that
---fields grouped with blank lines for readability are still picked up.
---@param class_name string
---@return table<string, true>?
---@return string? err
local function extract_fields(class_name)
  local escaped = class_name:gsub("%.", "%%.")
  -- `%f[%s]` ensures the class name is a whole word, so `DiffviewConfig`
  -- doesn't accidentally also match `DiffviewConfig.user`.
  local pattern = "%-%-%-@class%s+" .. escaped .. "%f[%s][^\n]*\n"
  local _, header_end = src:find(pattern)
  if not header_end then
    return nil, "could not locate @class block: " .. class_name
  end

  local fields = {}
  local pos = header_end + 1
  local len = #src
  while pos <= len do
    local nl = src:find("\n", pos) or (len + 1)
    local line = src:sub(pos, nl - 1)
    if line:match("^%-%-%-@class") then
      break
    elseif line:match("^%s*$") then
      -- Blank line; keep scanning in case fields continue below.
      pos = nl + 1
    elseif not line:match("^%s*%-%-") then
      break
    else
      local name = line:match("^%-%-%-@field%s+([%w_]+)%??")
        or line:match('^%-%-%-@field%s+%["([^"]+)"%]%??')
      if name then
        fields[name] = true
      end
      pos = nl + 1
    end
  end

  return fields
end

local function die(msg)
  io.stderr:write(msg .. "\n")
  vim.cmd("cquit 1")
end

local defaults, err = extract_defaults_keys()
if not defaults then
  die(err)
end

local internal, err2 = extract_fields("DiffviewConfig")
if not internal then
  die(err2)
end

local user, err3 = extract_fields("DiffviewConfig.user")
if not user then
  die(err3)
end

local function sorted_diff(a, b)
  local out = {}
  for k in pairs(a) do
    if not b[k] then
      out[#out + 1] = k
    end
  end
  table.sort(out)
  return out
end

local function report(errors, label, diff)
  if #diff > 0 then
    table.insert(errors, label .. ": " .. table.concat(diff, ", "))
  end
end

local errors = {}
report(
  errors,
  "In M.defaults but missing from @class DiffviewConfig",
  sorted_diff(defaults, internal)
)
report(
  errors,
  "In M.defaults but missing from @class DiffviewConfig.user",
  sorted_diff(defaults, user)
)
report(
  errors,
  "Declared on @class DiffviewConfig but missing from M.defaults",
  sorted_diff(internal, defaults)
)
report(
  errors,
  "Declared on @class DiffviewConfig.user but missing from M.defaults",
  sorted_diff(user, defaults)
)
report(
  errors,
  "Declared on DiffviewConfig but not on DiffviewConfig.user",
  sorted_diff(internal, user)
)
report(
  errors,
  "Declared on DiffviewConfig.user but not on DiffviewConfig",
  sorted_diff(user, internal)
)

if #errors > 0 then
  io.stderr:write("Config schema drift detected:\n")
  for _, e in ipairs(errors) do
    io.stderr:write("  " .. e .. "\n")
  end
  io.stderr:write("\nAdd or remove the corresponding entries (see CONTRIBUTING.md).\n")
  vim.cmd("cquit 1")
end

local function count(t)
  local n = 0
  for _ in pairs(t) do
    n = n + 1
  end
  return n
end

print(
  string.format(
    "OK: M.defaults, @class DiffviewConfig, and @class DiffviewConfig.user agree on %d top-level keys.",
    count(defaults)
  )
)

vim.cmd("qa!")
