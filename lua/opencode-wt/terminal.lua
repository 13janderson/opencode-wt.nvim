local M = {}
local State = require("opencode-wt.state")

M.win_id = nil
M.terminals = {}

function M.get_entry(path, get_current_path_fn)
  path = path or get_current_path_fn()
  return M.terminals[path]
end

function M.current_job_id(path, get_current_path_fn)
  local entry = M.get_entry(path, get_current_path_fn)
  if entry and entry.job_id then
    return entry.job_id
  end
  return nil
end

function M.build_opencode_cmd(path, opencode_cmd)
  local session_id = State:validate_session(path)
  if session_id then
    return opencode_cmd .. " -s " .. session_id
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
    return opencode_cmd .. " -s " .. State:get_session(path)
  end

  return opencode_cmd
end

function M.open_terminal_window(bufnr, config)
  if config.direction == "vertical" then
    vim.cmd("belowright vsplit")
  else
    vim.cmd("belowright split")
  end

  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, bufnr)

  if config.direction == "vertical" then
    vim.api.nvim_win_set_width(win, config.size)
    vim.api.nvim_set_option_value("winfixwidth", true, { win = win })
  else
    vim.api.nvim_win_set_height(win, config.size)
    vim.api.nvim_set_option_value("winfixheight", true, { win = win })
  end

  M.win_id = win

  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    callback = function()
      M.win_id = nil
      require("opencode-wt.prompt").win_id = nil
    end,
  })
end

function M.close_terminal_window(close_prompt_fn)
  close_prompt_fn()
  if M.win_id and vim.api.nvim_win_is_valid(M.win_id) then
    vim.api.nvim_win_close(M.win_id, true)
  end
  M.win_id = nil
end

function M.open_for_worktree(path, focus, config)
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
    vim.api.nvim_set_option_value("scrollback", config.scrollback or 10000, { buf = bufnr })
  end

  M.open_terminal_window(bufnr, config)

  if not existing then
    local cmd = M.build_opencode_cmd(path, config.opencode_cmd)
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
    
    -- Terminal buffer keymaps for easier navigation
    vim.api.nvim_buf_set_keymap(bufnr, "t", "<Esc>", "<C-\\><C-n>", { noremap = true, silent = true, desc = "Exit terminal mode" })
    vim.api.nvim_buf_set_keymap(bufnr, "t", "<C-[>", "<C-\\><C-n>", { noremap = true, silent = true, desc = "Exit terminal mode" })
    
    -- Normal mode scrolling in terminal (send to opencode)
    -- Matches tui.json: ctrl+k scrolls up, ctrl+l scrolls down
    vim.api.nvim_buf_set_keymap(bufnr, "n", "<C-k>", "i<C-k><C-\\><C-n>", { noremap = true, silent = true, desc = "Scroll up" })
    vim.api.nvim_buf_set_keymap(bufnr, "n", "<C-j>", "i<C-l><C-\\><C-n>", { noremap = true, silent = true, desc = "Scroll down" })
    vim.api.nvim_buf_set_keymap(bufnr, "n", "gg", "i<C-g><C-\\><C-n>", { noremap = true, silent = true, desc = "Jump to first message" })
    vim.api.nvim_buf_set_keymap(bufnr, "n", "G", "i<M-C-g><C-\\><C-n>", { noremap = true, silent = true, desc = "Jump to last message" })
    
    M.terminals[path] = M.terminals[path] or {}
    M.terminals[path].bufnr = bufnr
    M.terminals[path].job_id = job_id
  end

  if not focus then
    vim.api.nvim_set_current_win(prev_win)
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

return M
