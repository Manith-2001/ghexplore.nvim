# ghexplore.nvim

Sandbox a GitHub repo inside Neovim: explore, build, edit — then discard or resume later. Plus single-file grab without cloning (ghgrab parity).

> Status: **M6 CI + release**. Pinned `v0.1.0` below; `master` tracks development.

## Install (prod)

```lua
vim.pack.add({
  { src = "https://github.com/Manith-2001/ghexplore.nvim", version = "v0.1.0" },
})

require("ghexplore").setup({
  download_path = vim.fn.expand("~/Downloads"),
  jobs = 4,
  picker = "float", -- or "select" (auto-delegates to telescope/snacks)
  -- token = vim.env.GHGRAB_GITHUB_TOKEN or vim.env.GITHUB_TOKEN,
})
```

Then `:restart`, confirm install, `:checkhealth ghexplore`, `:help ghexplore`.

Suggested mapping (user config, never forced by the plugin):

```lua
vim.keymap.set("n", "<leader>gx", "<Plug>(GhexploreOpen)")
```

## Dev (local checkout)

`vim.pack` cannot live-edit; use a symlink + `packadd` (do not commit this hunk):

```bash
mkdir -p ~/.local/share/nvim/site/pack/mine/opt
ln -sfn /home/coder/dev/ghexplore.nvim ~/.local/share/nvim/site/pack/mine/opt/ghexplore.nvim
```

```lua
-- DEV ONLY
vim.cmd.packadd("ghexplore.nvim")
require("ghexplore").setup({ jobs = 1 })
```

## Usage

```vim
:Ghexplore https://github.com/owner/repo
:GhexploreGrab https://github.com/owner/repo/blob/main/README.md
:GhexploreList                    " float: <CR> resume, d discard, q close
:GhexplorePreview https://github.com/owner/repo/blob/main/README.md  " no clone
:GhexploreDiscard
```

Then `:checkhealth ghexplore`, `:help ghexplore`. All `setup()` keys are
validated (warn-only); health reports executables, dirs, sandbox count,
and token presence masked as `abcd…wxyz`.
```

## Layout

- `lua/ghexplore/` — `init` (public API) → `ui` → `{sandbox, grab}` → `gh` → `{url, auth}` → `config`
- `plugin/ghexplore.lua` — commands + `<Plug>` maps only
- `doc/ghexplore.txt` — `:help ghexplore`
- `tests/` — `minimal-init.lua` + `spec/*_spec.lua`
