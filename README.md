# opencode-wt.nvim

A Neovim plugin that integrates the [opencode](https://opencode.ai) AI coding assistant with [git-worktree.nvim](https://github.com/ThePrimeagen/git-worktree.nvim). It automatically manages a dedicated opencode terminal per git worktree, including session persistence and a prompt buffer.

## Features

- **Per-worktree terminals** — Each git worktree gets its own opencode terminal; switching worktrees automatically closes the old terminal and opens the new one.
- **Session persistence** — opencode session IDs are saved per worktree and validated on terminal open, so you resume where you left off.
- **Prompt buffer** — A small scratch buffer attached to the terminal for sending prompts, with keymaps for submit, insert newline, send line, and send visual selection - makes editing prompts a breeze.
- **Toggle commands** — Open/close the terminal and prompt buffer with a single keymap or command.

## Requirements

- Neovim >= 0.9
- [opencode](https://opencode.ai) CLI installed and on `$PATH`
- [git-worktree.nvim](https://github.com/ThePrimeagen/git-worktree.nvim)

## Installation

With lazy.nvim:

```lua
{
  "13janderson/opencode-wt.nvim",
  dependencies = {
    "ThePrimeagen/git-worktree.nvim",
  },
  opts = {},
}
```

With packer.nvim:

```lua
use({
  "13janderson/opencode-wt.nvim",
  requires = { "13janderson/git-worktree.nvim" },
  config = function()
    require("opencode-wt").setup({})
  end,
})
```

## Configuration

Default options:

```lua
require("opencode-wt").setup({
  size = 70,                    -- terminal width (vertical) or height (horizontal)
  prompt_size = 8,              -- prompt buffer height
  direction = "vertical",       -- "vertical" or "horizontal"
  opencode_cmd = "opencode",    -- path to the opencode binary
  keymaps = {
    toggle = "<leader>ot",      -- toggle terminal
    prompt = "<leader>O",       -- toggle prompt buffer
  },
})
```

## Commands

| Command | Description |
|---|---|
| `:OpencodeWTToggle` | Toggle opencode terminal for current worktree |
| `:OpencodeWTPrompt` | Toggle prompt buffer |
| `:OpencodeWTSend <text>` | Send text to the opencode terminal |
| `:OpencodeWTSessionInfo` | Show session info for current worktree |
| `:OpencodeWTSessionRefresh` | Refresh session ID for current worktree |

## Keymaps (prompt buffer)

| Key | Mode | Action |
|---|---|---|
| `<CR>` | Normal / Insert | Send prompt and clear |
| `<C-j>` | Insert | Insert newline |
| `<CR>` | Visual | Send visual selection |
| `<C-l>` | Normal | Send current line |
| `q` | Normal | Close prompt buffer |

## How it works

1. When you toggle the terminal, the plugin resolves the current git worktree path and opens an opencode terminal in a split.
2. A prompt buffer is attached below (or beside) the terminal for quick prompting.
3. When you switch worktrees (via git-worktree.nvim's hooks or Neovim's `DirChanged` event), the plugin closes the old terminal and opens a new one for the active worktree.
4. Session IDs are persisted to `stdpath("data")/opencode-wt/sessions.json` and validated on each terminal open to ensure stale sessions are not reused.
