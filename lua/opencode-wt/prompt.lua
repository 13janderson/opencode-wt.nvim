local M = {}

M.win_id = nil

function M.get_bufnr(path, terminals)
  local entry = terminals[path]
  if entry and entry.prompt_bufnr and vim.api.nvim_buf_is_valid(entry.prompt_bufnr) then
    return entry.prompt_bufnr
  end
  return nil
end

function M.get_text(path, terminals)
  local bufnr = M.get_bufnr(path, terminals)
  if not bufnr then
    return nil
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return table.concat(lines, "\n")
end

function M.clear(path, terminals)
  local bufnr = M.get_bufnr(path, terminals)
  if bufnr then
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
  end
end

function M.send_to_terminal(text, submit, path, get_current_path_fn, current_job_id_fn)
  if not text or text == "" then
    return
  end
  local job_id = current_job_id_fn(path, get_current_path_fn)
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

function M.send_prompt(path, clear_after, terminals, get_current_path_fn, current_job_id_fn)
  local text = M.get_text(path, terminals)
  if not text or text == "" then
    return
  end
  M.send_to_terminal(text, true, path, get_current_path_fn, current_job_id_fn)
  if clear_after then
    M.clear(path, terminals)
  end
end

function M.send_visual_selection(path, terminals, get_current_path_fn, current_job_id_fn)
  local bufnr = M.get_bufnr(path, terminals)
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
  M.send_to_terminal(text, true, path, get_current_path_fn, current_job_id_fn)
end

function M.send_line(path, terminals, get_current_path_fn, current_job_id_fn)
  local bufnr = M.get_bufnr(path, terminals)
  if not bufnr then
    return
  end
  local cursor_row = vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.api.nvim_buf_get_lines(bufnr, cursor_row - 1, cursor_row, false)[1]
  if line then
    M.send_to_terminal(line, true, path, get_current_path_fn, current_job_id_fn)
  end
end

function M.close_window()
  if M.win_id and vim.api.nvim_win_is_valid(M.win_id) then
    vim.api.nvim_win_close(M.win_id, true)
  end
  M.win_id = nil
end

function M.create_buf(path, terminals, get_current_path_fn, current_job_id_fn)
  local existing = M.get_bufnr(path, terminals)
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
      M.send_prompt(path, true, terminals, get_current_path_fn, current_job_id_fn)
    end,
    desc = "Send prompt to opencode and clear",
  })
  vim.api.nvim_buf_set_keymap(bufnr, "i", "<CR>", "", {
    callback = function()
      M.send_prompt(path, true, terminals, get_current_path_fn, current_job_id_fn)
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
      M.send_visual_selection(path, terminals, get_current_path_fn, current_job_id_fn)
    end,
    desc = "Send visual selection to opencode",
  })
  vim.api.nvim_buf_set_keymap(bufnr, "n", "<C-l>", "", {
    callback = function()
      M.send_line(path, terminals, get_current_path_fn, current_job_id_fn)
    end,
    desc = "Send current line to opencode",
  })
  vim.api.nvim_buf_set_keymap(bufnr, "n", "q", "", {
    callback = function()
      M.close_window()
    end,
    desc = "Close prompt buffer",
  })

  terminals[path] = terminals[path] or {}
  terminals[path].prompt_bufnr = bufnr
  return bufnr
end

function M.open(path, terminal_win_id, config, terminals, get_current_path_fn, current_job_id_fn)
  path = path or get_current_path_fn()

  if not terminal_win_id or not vim.api.nvim_win_is_valid(terminal_win_id) then
    vim.notify("[opencode-wt] open the opencode terminal first", vim.log.levels.WARN)
    return
  end

  if M.win_id and vim.api.nvim_win_is_valid(M.win_id) then
    return
  end

  local bufnr = M.create_buf(path, terminals, get_current_path_fn, current_job_id_fn)

  local prompt_win
  vim.api.nvim_win_call(terminal_win_id, function()
    vim.cmd("belowright split")
    prompt_win = vim.api.nvim_get_current_win()
  end)

  vim.api.nvim_win_set_buf(prompt_win, bufnr)
  vim.api.nvim_win_set_height(prompt_win, config.prompt_size)
  vim.api.nvim_set_option_value("winfixheight", true, { win = prompt_win })
  vim.api.nvim_set_option_value("number", false, { win = prompt_win })
  vim.api.nvim_set_option_value("relativenumber", false, { win = prompt_win })
  vim.api.nvim_set_option_value("signcolumn", "no", { win = prompt_win })

  M.win_id = prompt_win
  vim.api.nvim_set_current_win(prompt_win)
  vim.cmd("startinsert")
end

return M
