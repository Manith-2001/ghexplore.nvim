local M = {}

function M.check()
  vim.health.start("ghexplore")
  if vim.fn.has("nvim-0.12") == 1 then
    vim.health.ok("Neovim >= 0.12")
  else
    vim.health.error("Needs Neovim >= 0.12 (vim.pack + vim.system)")
  end
  if vim.fn.executable("git") == 1 then
    vim.health.ok("git found: " .. vim.fn.exepath("git"))
  else
    vim.health.error("git missing (needed for sandboxes)")
  end
  if vim.fn.executable("curl") == 1 then
    vim.health.ok("curl found: " .. vim.fn.exepath("curl"))
  else
    vim.health.error("curl missing (needed for grab)")
  end
  if vim.fn.executable("gh") == 1 then
    vim.health.ok("gh found (optional, for token)")
  else
    vim.health.warn("gh not found (optional, only for `gh auth token` fallback)")
  end
end

return M
