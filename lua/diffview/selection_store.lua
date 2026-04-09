local lazy = require("diffview.lazy")
local config = lazy.require("diffview.config") ---@module "diffview.config"

local logger = DiffviewGlobal.logger

local M = {}

---Get the storage path from config or fall back to stdpath("data").
---@return string
function M.get_path()
  local conf = config.get_config()
  if conf.persist_selections and conf.persist_selections.path then
    return conf.persist_selections.path
  end
  return vim.fn.stdpath("data") .. "/diffview_selections.json"
end

---Compute a scope key for a diff view.
---@param toplevel string
---@param rev_arg string?
---@return string
function M.scope_key(toplevel, rev_arg)
  return toplevel .. ":" .. (rev_arg or "")
end

---Read the entire store from disk.
---@param path string
---@return table
local function read_store(path)
  local ok, content = pcall(vim.fn.readfile, path)
  if not ok or #content == 0 then return {} end
  local decode_ok, data = pcall(vim.json.decode, table.concat(content, "\n"))
  if not decode_ok or type(data) ~= "table" then
    logger:warn("[SelectionStore] Corrupt store file; ignoring: " .. path)
    return {}
  end
  return data
end

---Write the entire store to disk atomically via a temp file + rename.
---@param path string
---@param data table
local function write_store(path, data)
  local ok, err = pcall(function()
    local dir = vim.fn.fnamemodify(path, ":h")
    vim.fn.mkdir(dir, "p")
    local json = vim.json.encode(data)
    local tmp = path .. ".tmp"
    vim.fn.writefile({ json }, tmp)
    local rename_ok, rename_err = vim.uv.fs_rename(tmp, path)
    if not rename_ok then
      error(rename_err or "fs_rename failed")
    end
  end)
  if not ok then
    logger:warn("[SelectionStore] Failed to write store: " .. tostring(err))
  end
end

---Load selection keys for a given scope.
---@param scope_key string
---@return string[]
function M.load(scope_key)
  local store = read_store(M.get_path())
  local scope = store[scope_key]
  if type(scope) == "table" and type(scope.selections) == "table" then
    return scope.selections
  end
  return {}
end

---Save selection keys for a given scope.
---@param scope_key string
---@param selection_keys string[]
function M.save(scope_key, selection_keys)
  local path = M.get_path()
  local store = read_store(path)
  if #selection_keys == 0 then
    store[scope_key] = nil
  else
    store[scope_key] = {
      selections = selection_keys,
      timestamp = os.time(),
    }
  end
  write_store(path, store)
end

return M
