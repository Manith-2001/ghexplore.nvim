--- Public Lua API. Thin delegating layer only: no git, no curl, no vim.ui here.
--- Dependency rule: init -> { ui, grab } -> { sandbox, gh } -> { url, auth } -> config
--- All heavy requires are lazy (inside functions) so `require("ghexplore")` stays cheap.
local M = {}

local config_module = require("ghexplore.config")

--- Active config. Replaced wholesale by `setup()`. Read-only for other modules.
M.config = config_module.merge(nil)

--- Setup. Idempotent: merges opts over defaults, applies keymaps.
--- Does NOT create user commands (those live in `plugin/ghexplore.lua`
--- so they exist even without `setup()`). See :h lua-plugin.
---@param opts table|nil
---@return table active config
function M.setup(opts)
  M.config = config_module.merge(opts)
  local ok, errs = config_module.validate(M.config)
  if not ok then
    vim.notify("ghexplore: invalid config: " .. table.concat(errs, "; "), vim.log.levels.WARN)
  end
  local km = M.config.keymaps
  if km and km.open then
    vim.keymap.set("n", km.open, function()
      M.open()
    end, { desc = "Ghexplore: open sandbox" })
  end
  if km and km.grab then
    vim.keymap.set("n", km.grab, function()
      M.grab()
    end, { desc = "Ghexplore: grab file" })
  end
  return M.config
end

--- Open a sandbox for `url`. Empty/nil => ui prompts for a URL.
---@param url string|nil e.g. "https://github.com/owner/repo"
function M.open(url)
  require("ghexplore.ui").open(url or "")
end

--- Grab a single file without cloning. Empty/nil => ui prompts.
---@param file_url string|nil e.g. "https://github.com/owner/repo/blob/main/README.md"
---@param dest string|nil file or directory target; nil => download_path
function M.grab(file_url, dest)
  require("ghexplore.grab").grab(file_url or "", dest)
end

--- Pick a sandbox to resume in a float picker.
function M.list()
  require("ghexplore.ui").list()
end

--- Discard a sandbox. Empty/nil => float picker.
---@param name string|nil sandbox id or url
---@param bang boolean|nil true => skip confirm
function M.discard(name, bang)
  require("ghexplore.ui").discard(name or "", bang or false)
end

--- Preview a remote file in a float (first 8KB). No clone, no disk write.
--- Empty/nil => ui prompts for a file URL.
---@param file_url string|nil e.g. "https://github.com/owner/repo/blob/main/README.md"
---@param opts table|nil { max_bytes?, title? }
function M.preview(file_url, opts)
  -- empty => delegate to ui.preview, which owns the only vim.ui prompt
  require("ghexplore.ui").preview(file_url or "", opts)
end

return M
