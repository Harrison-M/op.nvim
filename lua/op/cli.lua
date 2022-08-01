local JOB_TIMEOUT = 5000

local global_args = {
  '--cache',
  '--no-color',
}

local OP_COMMANDS = {
  account = {
    'add',
    'get',
    'list',
    'forget',
  },
  item = {
    'create',
    'get',
    'edit',
    'delete',
    'list',
    'share',
  },
  vault = {
    'create',
    'edit',
    'get',
    'delete',
    'list',
  },
}

local function non_empty_values(output)
  if not output then
    return {}
  end

  if #output == 0 then
    return {}
  end

  return vim.tbl_filter(function(value)
    return value and #value > 0
  end, output)
end

local function build_cmd(full_cmd)
  return function(args)
    args = args or {}
    local full_cmd_args = vim.list_extend(vim.deepcopy(full_cmd), vim.list_extend(vim.deepcopy(global_args), args))
    table.insert(full_cmd_args, 1, 'op')

    -- TODO remove this workaround
    -- TODO for some reason `op item create` hangs when run through job control but not `vim.fn.system()`
    if full_cmd_args[2] == 'item' and full_cmd_args[3] == 'create' then
      local escaped_args = vim.tbl_map(function(arg)
        return vim.fn.shellescape(arg)
      end, full_cmd_args)
      local output = vim.fn.systemlist(table.concat(escaped_args, ' '))
      local exit_code = vim.deepcopy(vim.v.shell_error or 0)
      if exit_code ~= 0 then
        -- non-zero exit code, return output in stderr position
        return {}, output, exit_code
      else
        -- zero exit code, return output in stdout position
        return output, {}, exit_code
      end
    end

    local stdout = {}
    local stderr = {}
    local exit_code = nil
    local job_id = vim.fn.jobstart(full_cmd_args, {
      stdout_buffered = true,
      stderr_buffered = true,
      detach = false,
      on_stdout = function(_, data)
        stdout = vim.list_extend(stdout, non_empty_values(data))
      end,
      on_stderr = function(_, data)
        stderr = vim.list_extend(stderr, non_empty_values(data))
      end,
      on_exit = function(job_exit_code)
        exit_code = job_exit_code
      end,
    })
    local status = vim.fn.jobwait({ job_id }, JOB_TIMEOUT)[1]
    -- see :h jobwait
    if status == -1 then
      vim.notify_once(
        'Command with args ' .. vim.inspect(full_cmd_args) .. ' timed out after ' .. (JOB_TIMEOUT / 1000) .. ' seconds'
      )
    end
    return stdout, stderr, exit_code
  end
end

local function build_api(command_map, parent_key)
  local api = {}
  for key, cmd_obj in pairs(command_map) do
    if type(cmd_obj) == 'string' then
      local args = { key, cmd_obj }
      if parent_key then
        table.insert(args, 1, parent_key)
      end

      -- don't include list indices as args
      args = vim.tbl_filter(function(val)
        return type(val) == 'string'
      end, args)

      api[cmd_obj] = build_cmd(args)
    else
      if type(cmd_obj) == 'table' then
        api[key] = build_api(cmd_obj, key)
      end
    end
  end

  return api
end

return build_api(OP_COMMANDS)
