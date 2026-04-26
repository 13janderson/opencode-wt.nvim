local M = {}
local State = require("opencode-wt.state")
local Terminal = require("opencode-wt.terminal")
local Prompt = require("opencode-wt.prompt")

M.last_path = nil
M.config = {
  size = 70,
  prompt_size = 8,
  direction = "vertical",
  opencode_cmd = "opencode",
  scrollback = 10000,
  keymaps = {
    toggle = "<leader>oc",
    prompt = "<leader>os",
    focus = "<leader>O",
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
    Terminal.on_delete(path)
  end)

  vim.api.nvim_create_autocmd("DirChanged", {
    callback = function()
      M.on_dir_changed()
    end,
  })

  -- User commands
  vim.api.nvim_create_user_command("OpencodeWTToggle", function()
    M.toggle()
  end, { desc = "Toggle opencode terminal for current worktree" })

  vim.api.nvim_create_user_command("OpencodeWTPrompt", function()
    M.toggle_prompt()
  end, { desc = "Toggle opencode prompt buffer" })

  vim.api.nvim_create_user_command("OpencodeWTSend", function(opts_arg)
    Prompt.send_to_terminal(opts_arg.args, true, nil, M.get_current_path, Terminal.current_job_id)
  end, { desc = "Send text to opencode terminal", nargs = "?", range = true })

  vim.api.nvim_create_user_command("OpencodeWTSessionInfo", function()
    M.print_session_info()
  end, { desc = "Show session info for current worktree" })

  vim.api.nvim_create_user_command("OpencodeWTSessionRefresh", function()
    M.refresh_current_session()
  end, { desc = "Refresh session ID for current worktree" })

  -- Keymaps
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

  if M.config.keymaps.focus then
    vim.keymap.set("n", M.config.keymaps.focus, function()
      M.focus()
    end, { desc = "Focus opencode terminal" })
  end
end

function M.on_switch(path)
  if path == M.last_path then
    return
  end
  M.last_path = path
  local had_prompt = Prompt.win_id and vim.api.nvim_win_is_valid(Prompt.win_id)
  Terminal.close_terminal_window(Prompt.close_window)
  Terminal.open_for_worktree(path, false, M.config)
  if had_prompt then
    Prompt.open(path, Terminal.win_id, M.config, Terminal.terminals, M.get_current_path, Terminal.current_job_id)
  end
end

function M.on_dir_changed()
  local path = M.get_current_path()
  if path == M.last_path then
    return
  end
  M.last_path = path
  if Terminal.win_id and vim.api.nvim_win_is_valid(Terminal.win_id) then
    local had_prompt = Prompt.win_id and vim.api.nvim_win_is_valid(Prompt.win_id)
    Terminal.close_terminal_window(Prompt.close_window)
    Terminal.open_for_worktree(path, false, M.config)
    if had_prompt then
      Prompt.open(path, Terminal.win_id, M.config, Terminal.terminals, M.get_current_path, Terminal.current_job_id)
    end
  end
end

function M.toggle()
  if Terminal.win_id and vim.api.nvim_win_is_valid(Terminal.win_id) then
    Terminal.close_terminal_window(Prompt.close_window)
    return
  end

  local path = M.get_current_path()
  Terminal.open_for_worktree(path, true, M.config)
  Prompt.open(path, Terminal.win_id, M.config, Terminal.terminals, M.get_current_path, Terminal.current_job_id)
end

function M.toggle_prompt()
  if Prompt.win_id and vim.api.nvim_win_is_valid(Prompt.win_id) then
    Prompt.close_window()
    return
  end

  Prompt.open(nil, Terminal.win_id, M.config, Terminal.terminals, M.get_current_path, Terminal.current_job_id)
end

function M.focus()
  if Terminal.win_id and vim.api.nvim_win_is_valid(Terminal.win_id) then
    vim.api.nvim_set_current_win(Terminal.win_id)
    vim.cmd("startinsert")
    return
  end

  local path = M.get_current_path()
  Terminal.open_for_worktree(path, true, M.config)
  vim.cmd("startinsert")
end

function M.print_session_info()
  local path = M.get_current_path()
  local session_id = State:get_session(path)
  local entry = Terminal.get_entry(path, M.get_current_path)
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
