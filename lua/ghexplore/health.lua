--- Health checks: nvim version, executables, dirs, config, token (masked).
--- Actionable: every failure says what to install/set. No network.
local M = {}

local function mask_token(tok)
  if type(tok) ~= "string" or #tok < 8 then
    return nil -- too short to mask usefully; report presence only
  end
  return tok:sub(1, 4) .. "…" .. tok:sub(-4)
end

local function active_config()
  local ok, init = pcall(require, "ghexplore")
  if ok and init and init.config then
    return init.config
  end
  local ok2, cfg = pcall(require, "ghexplore.config")
  if ok2 and cfg then
    return cfg.merge(nil)
  end
  return {}
end

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
  -- config: warn-only, never errors (plugin works on defaults)
  local cfg = active_config()
  local ok_cfg, errs = pcall(require, "ghexplore.config")
  if ok_cfg and errs and errs.validate then
    local valid, problems = errs.validate(cfg)
    if valid then
      vim.health.ok("config valid")
    else
      vim.health.warn("config: " .. table.concat(problems, "; "))
    end
  end
  -- dirs: data_dir + download_path must be writable or creatable under a
  -- writable ancestor (walk up; a missing nested dir is not an error).
  local function dir_status(dir)
    local cur = dir
    for _ = 1, 32 do
      local st = vim.uv.fs_stat(cur)
      if st then
        if st.type == "directory" and vim.fn.filewritable(cur) == 2 then
          return cur == dir and "ok" or "create"
        end
        return "bad"
      end
      local parent = vim.fn.fnamemodify(cur, ":h")
      if parent == cur then
        return "bad"
      end
      cur = parent
    end
    return "bad"
  end
  local data_dir = type(cfg.data_dir) == "string" and vim.fn.expand(cfg.data_dir) or ""
  if data_dir == "" then
    vim.health.error("data_dir is empty; set setup({ data_dir = ... })")
  else
    local st = dir_status(data_dir)
    if st == "ok" then
      vim.health.ok("data_dir writable: " .. data_dir)
    elseif st == "create" then
      vim.health.warn("data_dir will be created: " .. data_dir)
    else
      vim.health.error("data_dir not writable: " .. data_dir)
    end
  end
  local dl = type(cfg.download_path) == "string" and vim.fn.expand(cfg.download_path) or ""
  if dl == "" then
    vim.health.error("download_path is empty; set setup({ download_path = ... })")
  else
    local st = dir_status(dl)
    if st == "ok" then
      vim.health.ok("download_path writable: " .. dl)
    elseif st == "create" then
      vim.health.warn("download_path will be created: " .. dl)
    else
      vim.health.error("download_path not writable: " .. dl)
    end
  end
  -- sandbox count (proof metadata is readable)
  local ok_sb, sandbox = pcall(require, "ghexplore.sandbox")
  if ok_sb and sandbox and sandbox.list then
    local ok_list, items = pcall(sandbox.list)
    if ok_list and type(items) == "table" then
      vim.health.info(#items .. " sandbox(es) in " .. data_dir .. "/sandboxes")
    else
      vim.health.warn("could not list sandboxes: " .. tostring(items))
    end
  end
  -- token presence only, masked like ghgrab `config list` (abcd…wxyz).
  -- resolve_token hits `gh` (a subprocess) but never the network.
  local ok_auth, auth = pcall(require, "ghexplore.auth")
  if ok_auth and auth and auth.resolve_token then
    local tok = auth.resolve_token({ token = cfg.token })
    if tok and tok ~= "" then
      local masked = mask_token(tok)
      if masked then
        vim.health.ok("token present (" .. masked .. ")")
      else
        vim.health.ok("token present")
      end
    else
      vim.health.warn("no token: public repos only (set GITHUB_TOKEN for private repos + higher rate limits)")
    end
  end
end

-- exposed for tests only
M._mask_token = mask_token

return M
