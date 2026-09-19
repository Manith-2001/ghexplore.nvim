--- Single source of defaults. No side effects. Pure table merge.
--- See PLAN.md §2.3. `init.setup()` is the only writer of the active config.
local M = {}

--- Default options. All keys documented in `doc/ghexplore.txt`.
M.defaults = {
  -- Where sandboxes live: <data_dir>/sandboxes/<owner>__<repo>__<branch>/
  data_dir = vim.fn.stdpath("data") .. "/ghexplore",
  -- Where `:GhexploreGrab` writes single files.
  download_path = vim.fn.expand("~/Downloads"),
  -- git clone depth. 1 = shallow, 0 = full history.
  clone_depth = 1,
  -- Extra args appended to `git clone` (e.g. `{ "--filter=blob:none" }`).
  clone_args = {},
  -- Reuse an existing sandbox instead of re-cloning.
  reuse = true,
  -- How to present a sandbox dir. %s = dir, then %s = initial edit target.
  -- Keep as a format string so users can swap `edit` for `Oil`.
  open_cmd = "tabnew | tcd %s | edit %s",
  confirm_discard = true,
  -- Parallel downloads for grab (M2+).
  jobs = 4,
  -- nil => auth.resolve() chain. string | fun(): string|nil also accepted.
  token = nil,
  -- Never bound by default (see :h lua-plugin). Doc suggests <leader>gx.
  -- Example: { open = "<leader>gx", grab = "<leader>gX" }
  keymaps = {},
}

--- Merge user opts over defaults. Pure, no side effects.
---@param opts table|nil
---@return table merged config
function M.merge(opts)
  return vim.tbl_deep_extend("force", M.defaults, opts or {})
end

--- Validate a merged config. Warn-only; returns true when usable.
--- Full checks land in M5; M0 covers types that would crash M3.
---@param cfg table
---@return boolean ok, string[] errors
function M.validate(cfg)
  local errors = {}
  if type(cfg.jobs) ~= "number" or cfg.jobs < 1 or cfg.jobs > 64 then
    errors[#errors + 1] = "jobs must be a number in 1..64"
  end
  if type(cfg.clone_depth) ~= "number" or cfg.clone_depth < 0 then
    errors[#errors + 1] = "clone_depth must be a number >= 0"
  end
  if type(cfg.data_dir) ~= "string" or cfg.data_dir == "" then
    errors[#errors + 1] = "data_dir must be a non-empty string"
  end
  if type(cfg.download_path) ~= "string" or cfg.download_path == "" then
    errors[#errors + 1] = "download_path must be a non-empty string"
  end
  return #errors == 0, errors
end

return M
