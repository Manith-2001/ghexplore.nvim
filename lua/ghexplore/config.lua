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
  -- Sandbox picker: "float" (default, buffer-local <CR>/d/q) or
  -- "select" (plain vim.ui.select, auto-delegates to telescope/snacks
  -- when those override vim.ui.select; no hard dependency).
  picker = "float",
}

--- Merge user opts over defaults. Pure, no side effects.
---@param opts table|nil
---@return table merged config
function M.merge(opts)
  return vim.tbl_deep_extend("force", M.defaults, opts or {})
end

--- Validate a merged config. Warn-only; returns true when usable.
--- M5: full checks (types + ranges + writability of data_dir/download_path).
--- Never creates dirs or touches the network; pure + fs-stat only.
---@param cfg table
---@return boolean ok, string[] errors
function M.validate(cfg)
  local errors = {}
  local function add(msg)
    errors[#errors + 1] = msg
  end
  if type(cfg) ~= "table" then
    return false, { "config must be a table" }
  end
  if type(cfg.jobs) ~= "number" or cfg.jobs < 1 or cfg.jobs > 64 then
    add("jobs must be a number in 1..64")
  end
  if type(cfg.clone_depth) ~= "number" or cfg.clone_depth < 0 then
    add("clone_depth must be a number >= 0")
  end
  if type(cfg.clone_args) ~= "table" then
    add("clone_args must be a list of strings")
  else
    for i, a in ipairs(cfg.clone_args) do
      if type(a) ~= "string" then
        add("clone_args[" .. i .. "] must be a string")
        break
      end
    end
  end
  -- A missing dir is fine when some existing ancestor is a writable dir
  -- (sandbox/grab mkdir -p on demand). Walk up to the nearest ancestor.
  local function creatable(dir)
    local cur = vim.fn.expand(dir)
    for _ = 1, 32 do
      local st = vim.uv.fs_stat(cur)
      if st then
        return st.type == "directory" and vim.fn.filewritable(cur) == 2
      end
      local parent = vim.fn.fnamemodify(cur, ":h")
      if parent == cur then
        return false
      end
      cur = parent
    end
    return false
  end
  if type(cfg.data_dir) ~= "string" or cfg.data_dir == "" then
    add("data_dir must be a non-empty string")
  elseif not creatable(cfg.data_dir) then
    add("data_dir is not writable: " .. cfg.data_dir)
  end
  if type(cfg.download_path) ~= "string" or cfg.download_path == "" then
    add("download_path must be a non-empty string")
  elseif not creatable(cfg.download_path) then
    add("download_path is not writable: " .. cfg.download_path)
  end
  if type(cfg.reuse) ~= "boolean" then
    add("reuse must be a boolean")
  end
  if type(cfg.open_cmd) ~= "string" or cfg.open_cmd == "" then
    add("open_cmd must be a non-empty string")
  end
  if type(cfg.confirm_discard) ~= "boolean" then
    add("confirm_discard must be a boolean")
  end
  if cfg.token ~= nil and type(cfg.token) ~= "string" and type(cfg.token) ~= "function" then
    add("token must be a string, function, or nil")
  end
  if type(cfg.keymaps) ~= "table" then
    add("keymaps must be a table")
  end
  if cfg.picker ~= "float" and cfg.picker ~= "select" then
    add('picker must be "float" or "select"')
  end
  return #errors == 0, errors
end

return M
