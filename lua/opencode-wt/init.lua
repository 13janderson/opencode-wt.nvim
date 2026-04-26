local M = {}
local State = require("opencode-wt.state")

M.terminals = {}
M.win_id = nil
M.last_path = nil
M.prompt_win_id = nil
M.config = {
  size = 70,
  prompt_size = 8,
  direction = "vertical",
  opencode_cmd = "opencode",
  keymaps = {
    toggle = "<leader>ot",
    prompt = "<leader>O",
  },
}

function M.get_current_path()
  local ok, state = pcall(require, "git-worktree.state")
  if ok then
    local data = state:data()
    if data.current_worktree then
      return data.current_worktree
    end
  end

  local git_ok, git = pcall(require, "git-worktree.git")
  if git_ok then
    local toplevel = git.toplevel_dir()
    if toplevel then
      return toplevel
    end
  end

  return vim.fn.getcwd()
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  local ok, Hooks = pcall(require, "git-worktree.hooks")
  if not ok then
    vim.notify("[opencode-wt] git-worktree.nvim not found", vim.log.levels.ERROR)
    return
  end

  Hooks.register(Hooks.type.SWITCH, function(path, _prev_path)
    M.on_switch(path)
  end)

  Hooks.register(Hooks.type.DELETE, function(path)
    M.on_delete(path)
  end)

  vim.api.nvim_create_autocmd("DirChanged", {
    callback = function()
      M.on_dir_changed()
    end,
  })

  vim.api.nvim_create_user_command("OpencodeWTToggle", function()
    M.toggle()
  end, { desc = "Toggle opencode terminal for current worktree" })

  vim.api.nvim_create_user_command("OpencodeWTPrompt", function()
    M.toggle_prompt()
  end, { desc = "Toggle opencode prompt buffer" })

  vim.api.nvim_create_user_command("OpencodeWTSend", function(opts_arg)
    M.send_to_terminal(opts_arg.args)
  end, { desc = "Send text to opencode terminal", nargs = "?", range = true })

  vim.api.nvim_create_user_command("OpencodeWTSessionInfo", function()
    M.print_session_info()
  end, { desc = "Show session info for current worktree" })

  vim.api.nvim_create_user_command("OpencodeWTSessionRefresh", function()
    M.refresh_current_session()
  end, { desc = "Refresh session ID for current worktree" })

  if M.config.keymaps.toggle then
    vim.keymap.set("n", M.config.keymaps.toggle, function()
      M.toggle()
    end, { desc = "Toggle opencode terminal" })
  end

  if M.config.keymaps.prompt then
    vim.keymap.set("n", M.config.keymaps.prompt, function()
      M.toggle_prompt()
    end, { desc = "Toggle opencode prompt buffer" })
  end
end

function M.build_opencode_cmd(path)
  local session_id = State:validate_session(path)
  if session_id then
    return M.config.opencode_cmd .. " -s " .. session_id
  end

  local has_sessions = false
  local ok, output = pcall(function()
    return vim.fn.system("opencode session list --format json -n 50")
  end)
  if ok and vim.v.shell_error == 0 then
    local sessions = State.safe_json_decode(output, "build_opencode_cmd session lookup")
    if sessions then
      for _, session in ipairs(sessions) do
        if session.directory == path then
          State:set_session(path, session.id)
          has_sessions = true
          break
        end
      end
    end
  end

  if has_sessions then
    return M.config.opencode_cmd .. " -s " .. State:get_session(path)
  end

  return M.config.opencode_cmd
end

function M.on_switch(path)
  if path == M.last_path then
    return
  end
  M.last_path = path
  local had_prompt = M.prompt_win_id and vim.api.nvim_win_is_valid(M.prompt_win_id)
  M.close_terminal_window()
  M.open_for_worktree(path, false)
  if had_prompt then
    M.open_prompt(path)
  end
end

function M.on_dir_changed()
  local path = M.get_current_path()
  if path == M.last_path then
    return
  end
  M.last_path = path
  if M.win_id and vim.api.nvim_win_is_valid(M.win_id) then
    local had_prompt = M.prompt_win_id and vim.api.nvim_win_is_valid(M.prompt_win_id)
    M.close_terminal_window()
    M.open_for_worktree(path, false)
    if had_prompt then
      M.open_prompt(path)
    end
  end
end

function M.on_delete(path)
  local entry = M.terminals[path]
  if entry then
    if entry.bufnr and vim.api.nvim_buf_is_valid(entry.bufnr) then
      vim.api.nvim_buf_delete(entry.bufnr, { force = true })
    end
    if entry.prompt_bufnr and vim.api.nvim_buf_is_valid(entry.prompt_bufnr) then
      vim.api.nvim_buf_delete(entry.prompt_bufnr, { force = true })
    end
  end
  M.terminals[path] = nil
end

function M.get_entry(path)
  path = path or M.get_current_path()
  return M.terminals[path]
end

function M.current_job_id(path)
  local entry = M.get_entry(path)
  if entry and entry.job_id then
    return entry.job_id
  end
  return nil
end

function M.get_prompt_bufnr(path)
  local entry = M.get_entry(path)
  if entry and entry.prompt_bufnr and vim.api.nvim_buf_is_valid(entry.prompt_bufnr) then
    return entry.prompt_bufnr
  end
  return nil
end

function M.open_for_worktree(path, focus)
  if focus == nil then
    focus = true
  end

  local prev_win = vim.api.nvim_get_current_win()
  local entry = M.terminals[path]
  local existing = entry and entry.bufnr and vim.api.nvim_buf_is_valid(entry.bufnr)

  local bufnr
  if existing then
    bufnr = entry.bufnr
  else
    bufnr = vim.api.nvim_create_buf(false, true)
  end

  M.open_terminal_window(bufnr)

  if not existing then
    local cmd = M.build_opencode_cmd(path)
    local job_id = vim.fn.termopen(cmd, {
      cwd = path,
      on_exit = function(_, exit_code)
        if exit_code ~= 0 then
          return
        end
        vim.schedule(function()
          State:refresh_session(path)
        end)
      end,
    })
    M.terminals[path] = M.terminals[path] or {}
    M.terminals[path].bufnr = bufnr
    M.terminals[path].job_id = job_id
  end

  if not focus then
    vim.api.nvim_set_current_win(prev_win)
  end
end

function M.open_terminal_window(bufnr)
  if M.config.direction == "vertical" then
    vim.cmd("belowright vsplit")
  else
    vim.cmd("belowright split")
  end

  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, bufnr)

  if M.config.direction == "vertical" then
    vim.api.nvim_win_set_width(win, M.config.size)
    vim.api.nvim_set_option_value("winfixwidth", true, { win = win })
  else
    vim.api.nvim_win_set_height(win, M.config.size)
    vim.api.nvim_set_option_value("winfixheight", true, { win = win })
  end

  M.win_id = win

  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    callback = function()
      M.win_id = nil
      M.prompt_win_id = nil
    end,
  })
end

function M.close_terminal_window()
  M.close_prompt_window()
  if M.win_id and vim.api.nvim_win_is_valid(M.win_id) then
    vim.api.nvim_win_close(M.win_id, true)
  end
  M.win_id = nil
end

function M.toggle()
  if M.win_id and vim.api.nvim_win_is_valid(M.win_id) then
    M.close_terminal_window()
    return
  end

  local path = M.get_current_path()
  M.open_for_worktree(path, true)
  M.open_prompt(path)
end

function M.create_prompt_buf(path)
  local existing = M.get_prompt_bufnr(path)
  if existing then
    return existing
  end

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = bufnr })
  vim.api.nvim_set_option_value("bufhidden", "hide", { buf = bufnr })
  vim.api.nvim_set_option_value("swapfile", false, { buf = bufnr })
  vim.api.nvim_set_option_value("filetype", "opencode-prompt", { buf = bufnr })
  vim.api.nvim_buf_set_name(bufnr, "opencode-prompt://" .. path)

  vim.api.nvim_buf_set_keymap(bufnr, "n", "<CR>", "", {
    callback = function()
      M.send_prompt(path, true)
    end,
    desc = "Send prompt to opencode and clear",
  })
  vim.api.nvim_buf_set_keymap(bufnr, "i", "<CR>", "", {
    callback = function()
      M.send_prompt(path, true)
    end,
    desc = "Send prompt to opencode and clear",
  })
  vim.api.nvim_buf_set_keymap(bufnr, "i", "<C-j>", "", {
    callback = function()
      vim.api.nvim_put({ "" }, "l", true, false)
    end,
    desc = "Insert newline in prompt",
  })
  vim.api.nvim_buf_set_keymap(bufnr, "v", "<CR>", "", {
    callback = function()
      M.send_visual_selection(path)
    end,
    desc = "Send visual selection to opencode",
  })
  vim.api.nvim_buf_set_keymap(bufnr, "n", "<C-l>", "", {
    callback = function()
      M.send_line_to_terminal(path)
    end,
    desc = "Send current line to opencode",
  })
  vim.api.nvim_buf_set_keymap(bufnr, "n", "q", "", {
    callback = function()
      M.close_prompt_window()
    end,
    desc = "Close prompt buffer",
  })

  M.terminals[path] = M.terminals[path] or {}
  M.terminals[path].prompt_bufnr = bufnr
  return bufnr
end

function M.toggle_prompt()
  if M.prompt_win_id and vim.api.nvim_win_is_valid(M.prompt_win_id) then
    M.close_prompt_window()
    return
  end

  M.open_prompt()
end

function M.open_prompt(path)
  path = path or M.get_current_path()

  if not M.win_id or not vim.api.nvim_win_is_valid(M.win_id) then
    vim.notify("[opencode-wt] open the opencode terminal first", vim.log.levels.WARN)
    return
  end

  if M.prompt_win_id and vim.api.nvim_win_is_valid(M.prompt_win_id) then
    return
  end

  local bufnr = M.create_prompt_buf(path)

  local prompt_win
  vim.api.nvim_win_call(M.win_id, function()
    vim.cmd("belowright split")
    prompt_win = vim.api.nvim_get_current_win()
  end)

  vim.api.nvim_win_set_buf(prompt_win, bufnr)
  vim.api.nvim_win_set_height(prompt_win, M.config.prompt_size)
  vim.api.nvim_set_option_value("winfixheight", true, { win = prompt_win })
  vim.api.nvim_set_option_value("number", false, { win = prompt_win })
  vim.api.nvim_set_option_value("relativenumber", false, { win = prompt_win })
  vim.api.nvim_set_option_value("signcolumn", "no", { win = prompt_win })

  M.prompt_win_id = prompt_win
  vim.api.nvim_set_current_win(prompt_win)
  vim.cmd("startinsert")
end

function M.close_prompt_window()
  if M.prompt_win_id and vim.api.nvim_win_is_valid(M.prompt_win_id) then
    vim.api.nvim_win_close(M.prompt_win_id, true)
  end
  M.prompt_win_id = nil
end

function M.send_to_terminal(text, submit, path)
  if not text or text == "" then
    return
  end
  local job_id = M.current_job_id(path)
  if not job_id then
    vim.notify("[opencode-wt] no active opencode terminal", vim.log.levels.WARN)
    return
  end
  vim.fn.chansend(job_id, text)
  if submit then
    vim.defer_fn(function()
      vim.fn.chansend(job_id, "\r")
    end, 50)
  end
end

function M.get_prompt_text(path)
  local bufnr = M.get_prompt_bufnr(path)
  if not bufnr then
    return nil
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return table.concat(lines, "\n")
end

function M.clear_prompt(path)
  local bufnr = M.get_prompt_bufnr(path)
  if bufnr then
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
  end
end

function M.send_prompt(path, clear_after)
  local text = M.get_prompt_text(path)
  if not text or text == "" then
    return
  end
  M.send_to_terminal(text, true, path)
  if clear_after then
    M.clear_prompt(path)
  end
end

function M.send_visual_selection(path)
  local bufnr = M.get_prompt_bufnr(path)
  if not bufnr then
    return
  end
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local lines = vim.api.nvim_buf_get_lines(
    bufnr,
    start_pos[2] - 1,
    end_pos[2],
    false
  )
  local text = table.concat(lines, "\n")
  M.send_to_terminal(text, true, path)
end

function M.send_line_to_terminal(path)
  local bufnr = M.get_prompt_bufnr(path)
  if not bufnr then
    return
  end
  local cursor_row = vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.api.nvim_buf_get_lines(bufnr, cursor_row - 1, cursor_row, false)[1]
  if line then
    M.send_to_terminal(line, true, path)
  end
end

function M.print_session_info()
  local path = M.get_current_path()
  local session_id = State:get_session(path)
  local entry = M.get_entry(path)
  if session_id then
    print("[opencode-wt] worktree: " .. path .. " | session: " .. session_id)
  else
    print("[opencode-wt] worktree: " .. path .. " | no saved session")
  end
  if entry then
    print("  job_id: " .. tostring(entry.job_id) .. " | bufnr: " .. tostring(entry.bufnr))
  end
end

function M.refresh_current_session()
  local path = M.get_current_path()
  local session_id = State:refresh_session(path)
  if session_id then
    print("[opencode-wt] refreshed session: " .. session_id)
  else
    print("[opencode-wt] no session found for " .. path)
  end
end

return M
