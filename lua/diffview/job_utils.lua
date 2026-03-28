local fmt = string.format

local M = {}

---Resolve a fail_cond option to a check function.
---@param fail_cond_opt (string|function)?
---@param fail_cond_table table<string, function>
---@return function
function M.resolve_fail_cond(fail_cond_opt, fail_cond_table)
  if fail_cond_opt then
    if type(fail_cond_opt) == "string" then
      local cond = fail_cond_table[fail_cond_opt]
      assert(cond, fmt("Unknown fail condition: '%s'", fail_cond_opt))
      return cond
    elseif type(fail_cond_opt) == "function" then
      return fail_cond_opt
    else
      error("Invalid fail condition: " .. vim.inspect(fail_cond_opt))
    end
  end
  return fail_cond_table.non_zero
end

---Build a default log_opt table.
---@param opt table?
---@param caller_depth integer? Stack depth of the original caller (default: 4).
---@return table
function M.default_log_opt(opt, caller_depth)
  return vim.tbl_extend("keep", opt or {}, {
    func = "debug",
    no_stdout = true,
    debuginfo = debug.getinfo(caller_depth or 4, "Sl"),
  })
end

return M
