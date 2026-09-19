-- Minimal init for isolated testing: nvim --clean -u tests/minimal-init.lua
vim.opt.runtimepath:prepend("/home/coder/dev/ghexplore.nvim")
require("ghexplore").setup({ jobs = 1 })
