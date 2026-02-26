local FileEntry = require("diffview.scene.file_entry").FileEntry
local Job = require("diffview.job").Job
local JjRev = require("diffview.vcs.adapters.jj.rev").JjRev
local RevType = require("diffview.vcs.rev").RevType
local VCSAdapter = require("diffview.vcs.adapter").VCSAdapter
local arg_parser = require("diffview.arg_parser")
local async = require("diffview.async")
local config = require("diffview.config")
local lazy = require("diffview.lazy")
local oop = require("diffview.oop")
local utils = require("diffview.utils")
local vcs_utils = require("diffview.vcs.utils")

local await = async.await
local fmt = string.format
local logger = DiffviewGlobal.logger
local pl = lazy.access(utils, "path") ---@type PathLib

local M = {}

---@class JjAdapter : VCSAdapter
---@operator call : JjAdapter
local JjAdapter = oop.create_class("JjAdapter", VCSAdapter)

JjAdapter.Rev = JjRev
JjAdapter.config_key = "jj"
JjAdapter.bootstrap = {
  done = false,
  ok = false,
  version = {},
}

function JjAdapter.run_bootstrap()
  local jj_cmd = config.get_config().jj_cmd
  local bs = JjAdapter.bootstrap
  bs.done = true

  local function err(msg)
    if msg then
      bs.err = msg
      logger:error("[JjAdapter] " .. bs.err)
    end
  end

  if vim.fn.executable(jj_cmd[1]) ~= 1 then
    return err(fmt("Configured `jj_cmd` is not executable: '%s'", jj_cmd[1]))
  end

  local out = utils.job(utils.flatten({ jj_cmd, "--version" }))
  bs.version_string = out[1] and out[1]:match("jj (%S+)") or nil

  if not bs.version_string then
    return err("Could not get Jujutsu version!")
  end

  bs.ok = true
end

---@param path_args string[] # Raw path args
---@param cpath string? # Cwd path given by the `-C` flag option
---@return string[] path_args # Resolved path args
---@return string[] top_indicators # Top-level indicators
function JjAdapter.get_repo_paths(path_args, cpath)
  local paths = {}
  local top_indicators = {}

  for _, path_arg in ipairs(path_args) do
    for _, path in ipairs(pl:vim_expand(path_arg, false, true) --[[@as string[] ]]) do
      path = pl:readlink(path) or path
      table.insert(paths, path)
    end
  end

  local cfile = pl:vim_expand("%")
  cfile = pl:readlink(cfile) or cfile

  for _, path in ipairs(paths) do
    table.insert(top_indicators, pl:absolute(path, cpath))
    break
  end

  table.insert(top_indicators, cpath and pl:realpath(cpath) or (
    vim.bo.buftype == ""
    and pl:absolute(cfile)
    or nil
  ))

  if not cpath then
    table.insert(top_indicators, pl:realpath("."))
  end

  return paths, top_indicators
end

---@param path string
---@return string?
local function get_toplevel(path)
  local out, code = utils.job(utils.flatten({ config.get_config().jj_cmd, { "root" } }), path)
  if code ~= 0 then
    return nil
  end
  return out[1] and vim.trim(out[1])
end

---@param top_indicators string[]
---@return string? err
---@return string toplevel
function JjAdapter.find_toplevel(top_indicators)
  local toplevel

  for _, p in ipairs(top_indicators) do
    if not pl:is_dir(p) then
      ---@diagnostic disable-next-line: cast-local-type
      p = pl:parent(p)
    end

    if p and pl:readable(p) then
      toplevel = get_toplevel(p)
      if toplevel then
        return nil, toplevel
      end
    end
  end

  local msg_paths = vim.tbl_map(function(v)
    local rel_path = pl:relative(v, ".")
    return utils.str_quote(rel_path == "" and "." or rel_path)
  end, top_indicators)

  local err = fmt(
    "Path not a Jujutsu repo (or any parent): %s",
    table.concat(msg_paths, ", ")
  )

  return err, ""
end

---@param toplevel string
---@param path_args string[]
---@param cpath string?
---@return string? err
---@return JjAdapter
function JjAdapter.create(toplevel, path_args, cpath)
  local err
  local adapter = JjAdapter({
    toplevel = toplevel,
    path_args = path_args,
    cpath = cpath,
  })

  if not adapter.ctx.toplevel then
    err = "Could not find the top-level of the repository!"
  elseif not pl:is_dir(adapter.ctx.toplevel) then
    err = "The top-level is not a readable directory: " .. adapter.ctx.toplevel
  end

  if not adapter.ctx.dir then
    err = "Could not find the Jujutsu directory!"
  elseif not pl:is_dir(adapter.ctx.dir) then
    err = "The Jujutsu directory is not readable: " .. adapter.ctx.dir
  end

  return err, adapter
end

---@param opt vcs.adapter.VCSAdapter.Opt
function JjAdapter:init(opt)
  opt = opt or {}
  self:super(opt)

  self.ctx = {
    toplevel = opt.toplevel,
    dir = self:get_dir(opt.toplevel),
    path_args = opt.path_args or {},
  }

  self:init_completion()
end

---@return string[]
function JjAdapter:get_command()
  return config.get_config().jj_cmd
end

---@param path string
---@param rev Rev?
---@return string[]
function JjAdapter:get_show_args(path, rev)
  return utils.vec_join(self:args(), "file", "show", "-r", rev and rev:object_name() or "@", "--", path)
end

---@param args string[]
---@return string[]
function JjAdapter:get_log_args(args)
  return utils.vec_join("log", args)
end

---@param path string
---@return string?
function JjAdapter:get_dir(path)
  local root = get_toplevel(path)
  if not root then
    return nil
  end

  local jj_dir = pl:join(root, ".jj")
  if pl:is_dir(jj_dir) then
    return jj_dir
  end

  return root
end

---@return table<string, boolean>
function JjAdapter:get_bookmark_map()
  if self._bookmark_map then
    return self._bookmark_map
  end

  local out, code = self:exec_sync(
    { "bookmark", "list", "-a", "-T", [[name ++ "\n"]] },
    { cwd = self.ctx.toplevel, silent = true }
  )

  local map = {}
  if code == 0 then
    for _, line in ipairs(out) do
      local name = vim.trim(line)
      if name ~= "" then
        map[name] = true
      end
    end
  end

  self._bookmark_map = map
  return map
end

---@param name string
---@return boolean
function JjAdapter:has_bookmark(name)
  return self:get_bookmark_map()[name] == true
end

---@param rev_arg string
---@return string
function JjAdapter:normalize_rev_arg(rev_arg)
  -- Special-case fallback for repositories that use 'master' instead of 'main'.
  if rev_arg == "main" and not self:has_bookmark("main") and self:has_bookmark("master") then
    return "master"
  end

  return rev_arg
end

---@param rev_arg string
---@return string?
function JjAdapter:resolve_rev_arg(rev_arg)
  rev_arg = self:normalize_rev_arg(rev_arg)

  local out, code, stderr = self:exec_sync(
    { "show", "-T", "commit_id", rev_arg, "--no-patch" },
    {
      cwd = self.ctx.toplevel,
      retry = 2,
      fail_on_empty = true,
      log_opt = { label = "JjAdapter:resolve_rev_arg()" },
    }
  )

  if code ~= 0 or not out[1] then
    utils.err(utils.vec_join(
      fmt("Failed to parse rev %s!", utils.str_quote(rev_arg)),
      "Jujutsu output: ",
      stderr
    ))
    return
  end

  return vim.trim(out[1])
end

---@return JjRev?
function JjAdapter:head_rev()
  local head_hash = self:resolve_rev_arg("@")
  if not head_hash then
    return
  end

  return JjRev(RevType.COMMIT, head_hash, true)
end

---@param rev_arg string
---@return JjRev? left
---@return JjRev? right
function JjAdapter:symmetric_diff_revs(rev_arg)
  local r1 = self:normalize_rev_arg(rev_arg:match("(.+)%.%.%.") or "@")
  local r2 = self:normalize_rev_arg(rev_arg:match("%.%.%.(.+)") or "@")

  local h1 = self:resolve_rev_arg(r1)
  local h2 = self:resolve_rev_arg(r2)

  if not (h1 and h2) then
    return
  end

  -- Resolve a single fork-point commit with JJ revsets. This mirrors
  -- merge-base style behavior, but works in pure JJ repositories as well.
  local revset = fmt('latest(fork_point(commit_id("%s") | commit_id("%s")), 1)', h1, h2)
  local out, code, stderr = self:exec_sync(
    { "log", "-r", revset, "-T", [[commit_id ++ "\n"]], "--no-graph" },
    {
    cwd = self.ctx.toplevel,
    retry = 2,
    fail_on_empty = true,
    log_opt = { label = "JjAdapter:symmetric_diff_revs()" },
  })

  if code ~= 0 or not out[1] then
    utils.err(utils.vec_join(
      fmt("Failed to compute merge-base for rev range %s!", utils.str_quote(rev_arg)),
      "Jujutsu output: ",
      stderr
    ))
    return
  end

  local left_hash = vim.trim(out[1])

  return JjRev(RevType.COMMIT, left_hash), JjRev(RevType.COMMIT, h2)
end

---@param rev_arg string
---@return boolean
function JjAdapter:is_rev_arg_range(rev_arg)
  if rev_arg:match("%.%.%.") then
    return true
  end

  if rev_arg:match("::") then
    return false
  end

  return rev_arg:match(".*%.%..*") ~= nil
end

---@param rev_arg string?
---@param opt table
---@return Rev? left
---@return Rev? right
function JjAdapter:parse_revs(rev_arg, opt)
  local left
  local right

  if not rev_arg then
    local parent_hash = self:resolve_rev_arg("@-") or self:resolve_rev_arg("root()")
    left = parent_hash and JjRev(RevType.COMMIT, parent_hash) or JjRev.new_null_tree()
    right = JjRev(RevType.LOCAL)
  elseif rev_arg:match("%.%.%.") then
    local r2 = self:normalize_rev_arg(rev_arg:match("%.%.%.(.+)") or "@")
    left, right = self:symmetric_diff_revs(rev_arg)
    if left and right and r2 == "@" then
      -- In JJ, '@' is the mutable working-copy commit. Keep the right side as
      -- LOCAL so refresh reflects latest filesystem content even when commit
      -- identifiers are stable across edits.
      right = JjRev(RevType.LOCAL)
    end
  elseif self:is_rev_arg_range(rev_arg) then
    local r1 = self:normalize_rev_arg(rev_arg:match("^(.-)%.%.") or "@")
    local r2 = self:normalize_rev_arg(rev_arg:match("%.%.(.-)$") or "@")

    if r1 == "" then r1 = "@" end
    if r2 == "" then r2 = "@" end

    local h1 = self:resolve_rev_arg(r1)
    local h2 = self:resolve_rev_arg(r2)

    if not (h1 and h2) then
      return
    end

    left = JjRev(RevType.COMMIT, h1)
    right = JjRev(RevType.COMMIT, h2)
  else
    local hash = self:resolve_rev_arg(self:normalize_rev_arg(rev_arg))
    if not hash then
      return
    end

    left = JjRev(RevType.COMMIT, hash)
    right = JjRev(RevType.LOCAL)
  end

  if opt.cached then
    utils.warn("The '--cached/--staged' option is not supported for Jujutsu. Ignoring.")
  end

  if opt.imply_local then
    utils.warn("The '--imply-local' option is not supported for Jujutsu. Ignoring.")
  end

  return left, right
end

---@param rev_arg string?
---@param left Rev
---@param right Rev
---@return Rev? new_left
---@return Rev? new_right
function JjAdapter:refresh_revs(rev_arg, left, right)
  -- Keep bookmark state current between refreshes.
  self._bookmark_map = nil

  local new_left, new_right = self:parse_revs(rev_arg, {})
  if not (new_left and new_right) then
    return nil, nil
  end

  if new_left.type == left.type
    and new_right.type == right.type
    and new_left:object_name() == left:object_name()
    and new_right:object_name() == right:object_name()
  then
    return nil, nil
  end

  return new_left, new_right
end

---@param left Rev
---@param right Rev
---@return boolean
function JjAdapter:force_entry_refresh_on_noop(left, right)
  return self:has_local(left, right)
end

---Jj may rewrite working-copy files when revisions change, so reload the
---buffer from disk when it is reused.
---@param bufnr integer
function JjAdapter:on_local_buffer_reused(bufnr)
  local api = vim.api

  if not api.nvim_buf_is_loaded(bufnr) then
    vim.fn.bufload(bufnr)
  end

  if not vim.bo[bufnr].modified then
    pcall(vim.cmd, ("checktime %d"):format(bufnr))
  end
end

---@param left Rev
---@param right Rev
---@return string[]
function JjAdapter:rev_to_args(left, right)
  assert(
    not (left.type == RevType.LOCAL and right.type == RevType.LOCAL),
    "InvalidArgument :: Can't diff LOCAL against LOCAL!"
  )

  if left.type == RevType.COMMIT and right.type == RevType.COMMIT then
    return { "--from", left.commit, "--to", right.commit }

  elseif right.type == RevType.LOCAL and left.type == RevType.COMMIT then
    return { "--from", left.commit }

  elseif left.type == RevType.LOCAL and right.type == RevType.COMMIT then
    return { "--to", right.commit }
  end

  error(fmt("InvalidArgument :: Unsupported rev range: '%s..%s'!", left, right))
end

---@param argo ArgObject
---@return {left: Rev, right: Rev, options: DiffViewOptions}?
function JjAdapter:diffview_options(argo)
  local rev_arg = argo.args[1]

  local left, right = self:parse_revs(rev_arg, {
    cached = argo:get_flag({ "cached", "staged" }),
    imply_local = argo:get_flag("imply-local"),
  })

  if not (left and right) then
    return
  end

  logger:fmt_debug("Parsed revs: left = %s, right = %s", left, right)

  local options = {
    show_untracked = arg_parser.ambiguous_bool(
      argo:get_flag({ "u", "untracked-files" }, { plain = true }),
      nil,
      { "all", "normal", "true" },
      { "no", "false" }
    ),
    selected_file = argo:get_flag("selected-file", { no_empty = true, expand = true })
      or (vim.bo.buftype == "" and pl:vim_expand("%:p"))
      or nil,
  }

  return { left = left, right = right, options = options }
end

---@param range? { [1]: integer, [2]: integer }
---@param paths string[]
---@param argo ArgObject
---@return string[]?
function JjAdapter:file_history_options(range, paths, argo)
  utils.err("The Jujutsu adapter currently supports only ':DiffviewOpen'.")
  return nil
end

---@param opt? VCSAdapter.show_untracked.Opt
---@return boolean
function JjAdapter:show_untracked(opt)
  return false
end

---@param self JjAdapter
---@param left Rev
---@param right Rev
---@param args string[]
---@param kind vcs.FileKind
---@param opt vcs.adapter.LayoutOpt
---@param callback function
JjAdapter.tracked_files = async.wrap(function(self, left, right, args, kind, opt, callback)
  local job = Job({
    command = self:bin(),
    args = utils.vec_join(
      self:args(),
      "diff",
      "--summary",
      args
    ),
    cwd = self.ctx.toplevel,
    retry = 2,
    log_opt = { label = "JjAdapter:tracked_files()" },
  })

  local ok = await(job)

  if not ok or job.code ~= 0 then
    callback(job.stderr or {}, nil)
    return
  end

  local files = {}

  for _, line in ipairs(job.stdout) do
    local status, path = line:match("^(%u)%s+(.*)$")

    if status and path then
      local oldpath

      if status == "R" or status == "C" then
        local from_path, to_path = path:match("^(.-)%s+=>%s+(.-)$")
        oldpath = from_path
        path = to_path or path
      end

      files[#files + 1] = FileEntry.with_layout(opt.default_layout, {
        adapter = self,
        path = path,
        oldpath = oldpath,
        status = status,
        stats = {},
        kind = kind,
        revs = {
          a = left,
          b = right,
        },
      })
    end
  end

  callback(nil, files, {})
end)

---@param self JjAdapter
---@param left Rev
---@param right Rev
---@param opt vcs.adapter.LayoutOpt
---@param callback function
JjAdapter.untracked_files = async.wrap(function(self, left, right, opt, callback)
  callback(nil, {})
end)

---@param self JjAdapter
---@param path string
---@param rev? Rev
---@param callback fun(stderr: string[]?, stdout: string[]?)
JjAdapter.show = async.wrap(function(self, path, rev, callback)
  if not rev or rev:object_name() == self.Rev.NULL_TREE_SHA then
    callback(nil, {})
    return
  end

  local job
  job = Job({
    command = self:bin(),
    args = self:get_show_args(path, rev),
    cwd = self.ctx.toplevel,
    retry = 2,
    fail_cond = Job.FAIL_COND.on_empty,
    log_opt = { label = "JjAdapter:show()" },
    on_exit = async.void(function(_, ok, err)
      if not ok or job.code ~= 0 then
        local out = job.stderr and job.stderr[1] or ""
        if out:match("No such path") then
          callback(nil, {})
        else
          callback(utils.vec_join(err, job.stderr), nil)
        end
        return
      end

      callback(nil, job.stdout)
    end),
  })
  vcs_utils.queue_sync_job(job)
end)

---@param path string
---@param rev Rev
---@return boolean
function JjAdapter:is_binary(path, rev)
  return false
end

---@param path string
---@param kind vcs.FileKind
---@param commit string?
---@param callback fun(ok: boolean, undo?: string)
JjAdapter.file_restore = async.wrap(function(self, path, kind, commit, callback)
  callback(false)
end)

---@param file vcs.File
---@return boolean
function JjAdapter:stage_index_file(file)
  return false
end

---@param paths string[]?
---@return boolean
function JjAdapter:reset_files(paths)
  return false
end

---@param paths string[]
---@return boolean
function JjAdapter:add_files(paths)
  return false
end

---@param arg_lead string
---@param opt? RevCompletionSpec
---@return string[]
function JjAdapter:rev_candidates(arg_lead, opt)
  opt = vim.tbl_extend("keep", opt or {}, { accept_range = false }) --[[@as RevCompletionSpec ]]
  logger:lvl(1):debug("[completion] Revision candidates requested.")

  local ret = { "@", "@-", "root()" }
  local bookmarks = self:exec_sync(
    { "bookmark", "list", "-a", "-T", [[name ++ "\n"]] },
    { cwd = self.ctx.toplevel, silent = true }
  )

  local tags = self:exec_sync(
    { "tag", "list", "-T", [[name ++ "\n"]] },
    { cwd = self.ctx.toplevel, silent = true }
  )

  ret = utils.vec_join(ret, bookmarks, tags)

  local seen = {}
  ret = vim.tbl_filter(function(v)
    if not v or v == "" or seen[v] then
      return false
    end
    seen[v] = true
    return true
  end, ret)

  if opt.accept_range then
    local _, range_end = utils.str_match(arg_lead, {
      "^(%.%.%.?)()$",
      "^(%.%.%.?)()[^.]",
      "[^.](%.%.%.?)()$",
      "[^.](%.%.%.?)()[^.]",
    })

    if range_end then
      local range_lead = arg_lead:sub(1, range_end - 1)
      ret = vim.tbl_map(function(v)
        return range_lead .. v
      end, ret)
    end
  end

  return ret
end

function JjAdapter:init_completion()
  self.comp.open:put({ "u", "untracked-files" }, { "true", "normal", "all", "false", "no" })
  self.comp.open:put({ "C" }, function(_, arg_lead)
    return vim.fn.getcompletion(arg_lead, "dir")
  end)
  self.comp.open:put({ "selected-file" }, function(_, arg_lead)
    return vim.fn.getcompletion(arg_lead, "file")
  end)
end

M.JjAdapter = JjAdapter
return M
