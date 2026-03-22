local async = require("diffview.async")
local lazy = require("diffview.lazy")
local oop = require("diffview.oop")

local AsyncListStream = lazy.access("diffview.stream", "AsyncListStream") ---@type AsyncListStream|LazyModule
local Job = lazy.access("diffview.job", "Job") ---@type diffview.Job|LazyModule
local Rev = lazy.access("diffview.vcs.rev", "Rev") ---@type Rev|LazyModule
local RevType = lazy.access("diffview.vcs.rev", "RevType") ---@type RevType|LazyModule
local arg_parser = lazy.require("diffview.arg_parser") ---@module "diffview.arg_parser"
local utils = lazy.require("diffview.utils") ---@module "diffview.utils"
local vcs_utils = lazy.require("diffview.vcs.utils") ---@module "diffview.vcs.utils"

local await = async.await
local fmt = string.format
local logger = DiffviewGlobal.logger
local pl = lazy.access(utils, "path") ---@type PathLib

local M = {}

---@class vcs.adapter.LayoutOpt
---@field default_layout Diff2
---@field merge_layout Layout

---@class vcs.adapter.VCSAdapter.Bootstrap
---@field done boolean # Did the bootstrapping
---@field ok boolean # Bootstrapping was successful
---@field err string?
---@field version table
---@field version_string string
---@field target_version table
---@field target_version_string string

---@class vcs.adapter.VCSAdapter.Flags
---@field switches FlagOption[]
---@field options FlagOption[]

---@class vcs.adapter.VCSAdapter.Ctx
---@field toplevel string # VCS repository toplevel directory
---@field dir string # VCS directory
---@field path_args string[] # Resolved path arguments

---@class VCSAdapter: diffview.Object
---@field bootstrap vcs.adapter.VCSAdapter.Bootstrap
---@field ctx vcs.adapter.VCSAdapter.Ctx
---@field flags vcs.adapter.VCSAdapter.Flags
local VCSAdapter = oop.create_class("VCSAdapter")

VCSAdapter.Rev = Rev
VCSAdapter.config_key = nil
VCSAdapter.bootstrap = {
  done = false,
  ok = false,
  version = {},
}

function VCSAdapter.run_bootstrap()
  VCSAdapter.bootstrap.done = true
  VCSAdapter.bootstrap.ok = false
end

---Common bootstrap preamble: marks bootstrap as started and checks the
---configured command is executable. Returns the err reporting function on
---success, or nil if the executable check failed.
---@param bs vcs.adapter.VCSAdapter.Bootstrap
---@param cmd string[]
---@param adapter_name string
---@param cmd_config_key string Config field name (e.g. "git_cmd").
---@return (fun(msg: string?): nil)?
function VCSAdapter.bootstrap_preamble(bs, cmd, adapter_name, cmd_config_key)
  bs.done = true

  local function err(msg)
    if msg then
      bs.err = msg
      logger:error(fmt("[%s] %s", adapter_name, bs.err))
    end
  end

  if vim.fn.executable(cmd[1]) ~= 1 then
    err(fmt("Configured `%s` is not executable: '%s'", cmd_config_key, cmd[1]))
    return nil
  end

  return err
end

---@diagnostic disable: unused-local, missing-return

---@abstract
---@param path_args string[] # Raw path args
---@param cpath string? # Cwd path given by the `-C` flag option
---@return string[] path_args # Resolved path args
---@return string[] top_indicators # Top-level indicators
function VCSAdapter.get_repo_paths(path_args, cpath) oop.abstract_stub() end

---Try to find the top-level of a working tree by using the given indicative
---paths.
---@abstract
---@param top_indicators string[] A list of paths that might indicate what working tree we are in.
---@return string? err
---@return string toplevel # Absolute path
function VCSAdapter.find_toplevel(top_indicators) oop.abstract_stub() end

---@diagnostic enable: unused-local, missing-return

---Build top-level indicators from path args and context.
---This is the shared implementation used by most adapters.  Git overrides
---this to handle its pathspec syntax.
---@param path_args string[]
---@param cpath string?
---@return string[] paths # Resolved path args
---@return string[] top_indicators
function VCSAdapter.build_top_indicators(path_args, cpath)
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

---Iterate top-level indicators and resolve the repository root using a
---VCS-specific lookup function.  Returns the first successful match or a
---formatted error message.
---@param top_indicators string[]
---@param lookup_fn fun(path: string): string? # VCS-specific root lookup
---@param vcs_name string # For the error message (e.g. "git", "mercurial")
---@return string? err
---@return string toplevel
function VCSAdapter.find_toplevel_with(top_indicators, lookup_fn, vcs_name)
  for _, p in ipairs(top_indicators) do
    if not pl:is_dir(p) then
      ---@diagnostic disable-next-line: cast-local-type
      p = pl:parent(p)
    end

    if p and pl:readable(p) then
      local toplevel = lookup_fn(p)
      if toplevel then
        return nil, toplevel
      end
    end
  end

  local msg_paths = vim.tbl_map(function(v)
    local rel_path = pl:relative(v, ".")
    return utils.str_quote(rel_path == "" and "." or rel_path)
  end, top_indicators)

  return fmt("Path not a %s repo (or any parent): %s", vcs_name, table.concat(msg_paths, ", ")), ""
end

---@class vcs.adapter.VCSAdapter.Opt
---@field cpath string? # CWD path
---@field toplevel string # VCS toplevel path
---@field path_args string[] # Extra path arguments

function VCSAdapter:init()
  self.ctx = {}
  self.comp = {
    file_history = arg_parser.FlagValueMap(),
    open = arg_parser.FlagValueMap(),
  }
end

---@diagnostic disable: unused-local, missing-return

---@param path string
---@param rev Rev
---@return boolean -- True if the file was binary for the given rev, or it didn't exist.
function VCSAdapter:is_binary(path, rev)
  oop.abstract_stub()
end

---Initialize completion parameters
function VCSAdapter:init_completion()
  oop.abstract_stub()
end

---@class RevCompletionSpec
---@field accept_range boolean

---Completion for revisions.
---@param arg_lead string
---@param opt? RevCompletionSpec
---@return string[]
function VCSAdapter:rev_candidates(arg_lead, opt)
  oop.abstract_stub()
end

---@return Rev?
function VCSAdapter:head_rev()
  oop.abstract_stub()
end

---Get the hash for a file's blob in a given rev.
---@param path string
---@param rev_arg string?
---@return string?
function VCSAdapter:file_blob_hash(path, rev_arg)
  oop.abstract_stub()
end

---@return string[] # path to binary for VCS command
function VCSAdapter:get_command()
  oop.abstract_stub()
end

---@diagnostic enable: unused-local, missing-return

---@return string cmd The VCS binary.
function VCSAdapter:bin()
  return self:get_command()[1]
end

---@return string[] args The default VCS args.
function VCSAdapter:args()
  return utils.vec_slice(self:get_command(), 2)
end


---Execute a VCS command synchronously.
---@param args string[]
---@param cwd_or_opt? string|utils.job.Opt
---@return string[] stdout
---@return integer code
---@return string[] stderr
---@overload fun(self: VCSAdapter, args: string[], cwd?: string)
---@overload fun(self: VCSAdapter, args: string[], opt?: utils.job.Opt)
function VCSAdapter:exec_sync(args, cwd_or_opt)
  if not self.class.bootstrap.done then self.class.run_bootstrap() end

  local cmd = utils.flatten({ self:get_command(), args })

  if not self.class.bootstrap.ok then
    logger:error(
      ("[VCSAdapter] Can't exec adapter command because bootstrap failed! Cmd: %s")
      :format(table.concat(cmd, " "))
    )
    return
  end

  return utils.job(cmd, cwd_or_opt)
end


---@param thread thread
---@param ok boolean
---@param result any
---@return boolean ok
---@return any result
function VCSAdapter:handle_co(thread, ok, result)
  if not ok then
    local err_msg = utils.vec_join(
      "Coroutine failed!",
      debug.traceback(thread, result, 1)
    )
    utils.err(err_msg, true)
    logger:error(table.concat(err_msg, "\n"))
  end
  return ok, result
end

-- File History

---@diagnostic disable: unused-local, missing-return

---@param path string
---@param rev Rev?
---@return string[] args to show commit content
function VCSAdapter:get_show_args(path, rev)
  oop.abstract_stub()
end

---@param args string[]
---@return string[] args to show commit log message
function VCSAdapter:get_log_args(args)
  oop.abstract_stub()
end

---@class vcs.MergeContext
---@field ours { hash: string, ref_names: string? }
---@field theirs { hash: string, ref_names: string? }
---@field base { hash: string, ref_names: string? }

---@return vcs.MergeContext?
function VCSAdapter:get_merge_context()
  oop.abstract_stub()
end

---@param range? { [1]: integer, [2]: integer }
---@param paths string[]
---@param argo ArgObject
---@return string[] # Options to show file history
function VCSAdapter:file_history_options(range, paths, argo)
  oop.abstract_stub()
end

---@param self VCSAdapter
---@param out_stream AsyncListStream
---@param opt vcs.adapter.FileHistoryWorkerSpec
VCSAdapter.file_history_worker = async.void(function(self, out_stream, opt)
  oop.abstract_stub()
end)

---@diagnostic enable: unused-local, missing-return

---@class vcs.adapter.FileHistoryWorkerSpec
---@field log_opt ConfigLogOptions
---@field layout_opt vcs.adapter.LayoutOpt

---@param opt vcs.adapter.FileHistoryWorkerSpec
---@return AsyncListStream out_stream
function VCSAdapter:file_history(opt)
  local out_stream = AsyncListStream()
  self:file_history_worker(out_stream, opt)

  return out_stream
end

-- Diff View

---@diagnostic disable: unused-local, missing-return

---Convert revs to rev args.
---@param left Rev
---@param right Rev
---@return string[]
function VCSAdapter:rev_to_args(left, right)
  oop.abstract_stub()
end

---Refresh rev endpoints for an existing view.
---@param rev_arg string?
---@param left Rev
---@param right Rev
---@return Rev? new_left
---@return Rev? new_right
function VCSAdapter:refresh_revs(rev_arg, left, right)
  return nil, nil
end

---Whether NOOP diff entries should still be replaced during a refresh.
---@param left Rev
---@param right Rev
---@return boolean
function VCSAdapter:force_entry_refresh_on_noop(left, right)
  return false
end

---Called when `_create_local_buffer` reuses an existing buffer. Adapters
---whose VCS rewrites working-copy files (e.g. jj) should override this to
---ensure the buffer content reflects the current state on disk.
---@param bufnr integer
function VCSAdapter:on_local_buffer_reused(bufnr)
  -- Default: no-op. Git and Hg do not rewrite working-copy files.
end

---Restore a file to the requested state
---@param path string # file to restore
---@param kind '"staged"'|'"working"'
---@param commit string
---@return string? Command to undo the restore
function VCSAdapter:restore_file(path, kind, commit)
  oop.abstract_stub()
end

---Add file(s)
---@param paths string[]
---@return boolean # add was successful
function VCSAdapter:add_files(paths)
  oop.abstract_stub()
end

---Reset file(s)
---@param paths string[]?
---@return boolean # reset was successful
function VCSAdapter:reset_files(paths)
  oop.abstract_stub()
end

---@param argo ArgObject
---@return {left: string, right: string, options: string[]}
function VCSAdapter:diffview_options(argo)
  oop.abstract_stub()
end

---@class VCSAdapter.show_untracked.Opt
---@field dv_opt? DiffViewOptions
---@field revs? { left: Rev, right: Rev }

---Check whether untracked files should be listed.
---@param opt? VCSAdapter.show_untracked.Opt
---@return boolean
function VCSAdapter:show_untracked(opt)
  oop.abstract_stub()
end

---Restore file
---@param self VCSAdapter
---@param path string
---@param kind vcs.FileKind
---@param commit string?
---@return boolean success
---@return string? undo # If the adapter supports it: a command that will undo the restoration.
VCSAdapter.file_restore = async.void(function(self, path, kind, commit)
  oop.abstract_stub()
end)

---Update the index entry for a given file with the contents of an index buffer.
---@param file vcs.File
---@return boolean success
function VCSAdapter:stage_index_file(file)
  oop.abstract_stub()
end

---@param self VCSAdapter
---@param left Rev
---@param right Rev
---@param args string[]
---@param kind vcs.FileKind
---@param opt vcs.adapter.LayoutOpt
---@param callback function
VCSAdapter.tracked_files = async.wrap(function(self, left, right, args, kind, opt, callback)
  oop.abstract_stub()
end)

---@param self VCSAdapter
---@param left Rev
---@param right Rev
---@param opt vcs.adapter.LayoutOpt
---@param callback? function
VCSAdapter.untracked_files = async.wrap(function(self, left, right, opt, callback)
  oop.abstract_stub()
end)

---@diagnostic enable: unused-local, missing-return

---@param self VCSAdapter
---@param path string
---@param rev? Rev
---@param callback fun(stderr: string[]?, stdout: string[]?)
VCSAdapter.show = async.wrap(function(self, path, rev, callback)
  local job
  job = Job({
    command = self:bin(),
    args = self:get_show_args(path, rev),
    cwd = self.ctx.toplevel,
    retry = 2,
    fail_cond = Job.FAIL_COND.on_empty,
    log_opt = { label = "VCSAdapter:show()" },
    on_exit = async.void(function(_, ok, err)
      if not ok or job.code ~= 0 then
        callback(utils.vec_join(err, job.stderr), nil)
        return
      end

      callback(nil, job.stdout)
    end),
  })
  -- Problem: Running multiple 'show' jobs simultaneously may cause them to fail
  -- silently.
  -- Solution: queue them and run them one after another.
  await(vcs_utils.queue_sync_job(job))
end)

---Convert revs to string representation.
---@param left Rev
---@param right Rev
---@return string|nil
function VCSAdapter:rev_to_pretty_string(left, right)
  if left.track_head and right.type == RevType.LOCAL then
    return nil
  elseif left.commit and right.type == RevType.LOCAL then
    return left:abbrev()
  elseif left.commit and right.commit then
    return left:abbrev() .. ".." .. right:abbrev()
  end
  return nil
end

---Check if any of the given revs are LOCAL.
---@param left Rev
---@param right Rev
---@return boolean
function VCSAdapter:has_local(left, right)
  return left.type == RevType.LOCAL or right.type == RevType.LOCAL
end

VCSAdapter.flags = {
  ---@type FlagOption[]
  switches = {},
  ---@type FlagOption[]
  options = {},
}

---@param arg_lead string
---@return string[]
function VCSAdapter:path_candidates(arg_lead)
  return vim.fn.getcompletion(arg_lead, "file", 0)
end

M.VCSAdapter = VCSAdapter
return M
