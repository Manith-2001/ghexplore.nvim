--- UI only. The ONLY module that calls vim.ui.* / nvim_open_win (orthogonality).
--- Never runs git/curl directly: delegates to `sandbox` / `grab` / `gh`.
--- M4 implements the picker + float; M0 stubs notify so commands exist early.
local M = {}

--- Open a sandbox: prompt when empty, then tabnew + tcd + edit (M3/M4).
---@param url string empty => prompt via vim.ui.input
function M.open(url)
  vim.notify("ghexplore: open not implemented (M3/M4)", vim.log.levels.WARN)
end

--- List/resume sandboxes (M4 float; M3 vim.ui.select fallback).
function M.list()
  vim.notify("ghexplore: list not implemented (M3/M4)", vim.log.levels.WARN)
end

--- Discard a sandbox, with confirm unless `bang`.
---@param name string empty => prompt
---@param bang boolean skip confirm
function M.discard(name, bang)
  vim.notify("ghexplore: discard not implemented (M3/M4)", vim.log.levels.WARN)
end

return M
