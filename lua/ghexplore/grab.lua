--- Single-file grab (ghgrab parity). No git, no UI picker here.
--- Uses `gh` for HTTP, `url` for parsing. M2 implements; M0 holds the contract.
local M = {}

--- Grab one file URL to `dest` (file or dir). Notifies on success/failure.
---@param file_url string e.g. "https://github.com/owner/repo/blob/main/README.md"
---@param dest string|nil file or directory; nil => config.download_path
function M.grab(file_url, dest)
  vim.notify("ghexplore.grab: not implemented (M2)", vim.log.levels.WARN)
end

return M
