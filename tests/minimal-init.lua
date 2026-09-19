-- Minimal init for isolated testing: nvim --clean -u tests/minimal-init.lua
-- Portable: $GHEXPLORER_ROOT wins (CI sets it to the checkout), then the
-- local dev checkout, then cwd (plenary harness spawns children with cwd
-- set to the repo root, and `set rtp+=.` already covers that case).
local root = vim.env.GHEXPLORER_ROOT
if not root or root == "" or vim.fn.isdirectory(root) ~= 1 then
  root = "/home/coder/dev/ghexplore.nvim"
end
if vim.fn.isdirectory(root) ~= 1 then
  root = vim.fn.getcwd()
end
vim.opt.runtimepath:prepend(root)
require("ghexplore").setup({ jobs = 1 })
