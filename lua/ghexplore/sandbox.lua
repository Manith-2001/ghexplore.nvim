--- Sandbox lifecycle. The ONLY module that touches sandbox dirs + metadata (DRY).
--- Layout: <data_dir>/sandboxes/<owner>__<repo>__<branch>/.ghexplore.json
--- Never prompts (orthogonality: prompting lives in the UI module).
local M = {}

local url_mod = require("ghexplore.url")

local META_NAME = ".ghexplore.json"

local function active_config()
  local ok, init = pcall(require, "ghexplore")
  if ok and init and init.config then
    return init.config
  end
  local ok2, cfg = pcall(require, "ghexplore.config")
  if ok2 and cfg and cfg.defaults then
    return cfg.defaults
  end
  return { data_dir = vim.fn.stdpath("data") .. "/ghexplore", clone_depth = 1, clone_args = {}, reuse = true }
end

local function is_dir(path)
  local st = vim.uv.fs_stat(path)
  return st ~= nil and st.type == "directory"
end

local function mkdir_p(dir)
  if dir == "" or dir == "." then
    return true
  end
  if is_dir(dir) then
    return true
  end
  local ok = pcall(vim.fn.mkdir, dir, "p")
  return ok and is_dir(dir)
end

--- Redact an embedded token so errors never leak credentials.
---@param s string
---@return string
function M._redact(s)
  if type(s) ~= "string" then
    return s
  end
  return (s:gsub("(https?://)[^@%s]+@", "%1***@"))
end

--- Root dir holding all sandboxes. Creates it on demand.
---@return string path
function M.root()
  local cfg = active_config()
  local root = cfg.data_dir .. "/sandboxes"
  mkdir_p(root)
  return root
end

--- Sandbox id for a URL string. Delegates to `url.sandbox_id` (no second sanitizer).
---@param url_str string
---@return string|nil id, string|nil err
function M.id_for(url_str)
  local parsed, perr = url_mod.parse(url_str)
  if not parsed then
    return nil, perr or "invalid url"
  end
  local ok, id = pcall(url_mod.sandbox_id, parsed)
  if not ok or type(id) ~= "string" then
    return nil, "could not derive sandbox id"
  end
  return id, nil
end

--- Absolute dir for a sandbox id (no IO).
---@param id string
---@return string dir
function M.dir_for(id)
  return M.root() .. "/" .. id
end

local function meta_path(dir)
  return dir .. "/" .. META_NAME
end

--- Read `.ghexplore.json` for a sandbox dir. Returns {} when absent/unreadable.
---@param dir string
---@return table meta
function M.meta_read(dir)
  local f = io.open(meta_path(dir), "r")
  if not f then
    return {}
  end
  local data = f:read("*a")
  f:close()
  if not data or data == "" then
    return {}
  end
  local ok, decoded = pcall(vim.json.decode, data)
  if not ok or type(decoded) ~= "table" then
    return {}
  end
  return decoded
end

--- Write `.ghexplore.json`. The ONLY metadata writer.
---@param dir string
---@param meta table
---@return boolean ok, string|nil err
function M.meta_write(dir, meta)
  if not mkdir_p(dir) then
    return false, "cannot create directory " .. dir
  end
  local ok, encoded = pcall(vim.json.encode, meta)
  if not ok then
    return false, "cannot encode metadata"
  end
  local f, ferr = io.open(meta_path(dir), "w")
  if not f then
    return false, "cannot write metadata: " .. tostring(ferr)
  end
  f:write(encoded)
  f:close()
  return true, nil
end

--- List sandboxes sorted by last_opened desc.
---@return table[] { id, dir, meta, last_opened }
function M.list()
  local root = M.root()
  if not is_dir(root) then
    return {}
  end
  local names = vim.fn.readdir(root)
  local items = {}
  for _, name in ipairs(names) do
    if name ~= "." and name ~= ".." then
      local dir = root .. "/" .. name
      if is_dir(dir) then
        local meta = M.meta_read(dir)
        items[#items + 1] = { id = name, dir = dir, meta = meta, last_opened = tonumber(meta.last_opened) or 0 }
      end
    end
  end
  table.sort(items, function(a, b)
    return a.last_opened > b.last_opened
  end)
  return items
end

--- Build the git clone source for a parsed URL, injecting a token when available.
--- The token is ephemeral (never stored); callers must redact errors via `M._redact`.
---@param parsed table output of url.parse
---@param token string|nil
---@return string clone url
function M._clone_src(parsed, token)
  local base = string.format("https://%s/%s/%s.git", parsed.host, parsed.owner, parsed.repo)
  if token and token ~= "" then
    return string.format("https://%s@%s/%s/%s.git", token, parsed.host, parsed.owner, parsed.repo)
  end
  return base
end

local function resolve_token()
  local cfg = active_config()
  local ok, auth = pcall(require, "ghexplore.auth")
  if not ok or not auth then
    return nil
  end
  return auth.resolve_token({ token = cfg.token })
end

--- Default branch via `git ls-remote --symref <src> HEAD`. Returns nil when unknown.
---@param src string clone source (may contain an ephemeral token)
---@return string|nil branch
function M._ls_remote_default(src)
  if vim.fn.executable("git") ~= 1 then
    return nil
  end
  local ok, result = pcall(function()
    return vim.system({ "git", "ls-remote", "--symref", src, "HEAD" }, { text = true }):wait()
  end)
  if not ok or not result or result.code ~= 0 then
    return nil
  end
  local out = result.stdout or ""
  local ref = out:match("ref:%s+refs/heads/([^\t\r\n%s]+)")
  if ref and ref ~= "" then
    return ref
  end
  return nil
end

--- Clone `src` into `dest` (sync). One canonical git-clone wrapper.
---@param src string git remote (path or https url)
---@param dest string empty target dir (must not exist)
---@param branch string|nil single branch to clone (nil => remote default)
---@param depth integer|nil 0/nil => full clone, else --depth N
---@param extra_args string[]|nil appended after standard flags
---@return boolean ok, string|nil err (redacted)
function M._git_clone(src, dest, branch, depth, extra_args)
  if vim.fn.executable("git") ~= 1 then
    return false, "git not found in PATH"
  end
  if is_dir(dest) or vim.uv.fs_stat(dest) ~= nil then
    return false, "target already exists: " .. M._redact(dest)
  end
  local args = { "git", "clone" }
  if depth and depth > 0 then
    args[#args + 1] = "--depth"
    args[#args + 1] = tostring(depth)
  end
  if branch and branch ~= "" then
    args[#args + 1] = "--branch"
    args[#args + 1] = branch
  end
  if extra_args then
    for _, a in ipairs(extra_args) do
      args[#args + 1] = a
    end
  end
  args[#args + 1] = src
  args[#args + 1] = dest
  local ok, result = pcall(function()
    return vim.system(args, { text = true }):wait()
  end)
  if not ok or not result then
    return false, "failed to run git clone for " .. M._redact(src)
  end
  if result.code ~= 0 then
    local stderr = M._redact(tostring(result.stderr or ""))
    stderr = stderr:gsub("^%s+", ""):gsub("%s+$", "")
    if stderr == "" then
      stderr = "git clone exited " .. tostring(result.code)
    end
    -- never leave a half-clone behind; retry logic depends on a clean dest
    pcall(vim.fn.delete, dest, "rf")
    return false, stderr
  end
  return true, nil
end

local function dedup_append(list, seen, val)
  if val and val ~= "" and not seen[val] then
    seen[val] = true
    list[#list + 1] = val
  end
end

local function rm_rf(dir)
  local ok = pcall(vim.fn.delete, dir, "rf")
  if ok and vim.fn.delete then
    return vim.uv.fs_stat(dir) == nil
  end
  if vim.fn.executable("rm") == 1 then
    local rok = pcall(function()
      return vim.system({ "rm", "-rf", dir }):wait()
    end)
    return rok and vim.uv.fs_stat(dir) == nil
  end
  return false
end

local function is_inside(root, dir)
  local r = root:gsub("/+$", "")
  if dir == r then
    return false -- the root itself is never a discard target
  end
  return dir:sub(1, #r + 1) == r .. "/"
end

--- Resolve `url_or_id` to (id, dir, parsed|nil, exists).
---@param url_or_id string
---@return string|nil id, string|nil dir, table|nil parsed, boolean exists
function M._resolve(url_or_id)
  if type(url_or_id) ~= "string" or vim.trim(url_or_id) == "" then
    return nil, nil, nil, false
  end
  local parsed = url_mod.parse(vim.trim(url_or_id))
  if parsed then
    local id = M.id_for(url_or_id)
    if not id then
      return nil, nil, nil, false
    end
    local dir = M.dir_for(id)
    return id, dir, parsed, is_dir(dir)
  end
  -- not a URL: treat as a sandbox id
  local id = vim.trim(url_or_id):gsub("/+$", "")
  id = id:match("([^/]+)$") or id
  local dir = M.dir_for(id)
  return id, dir, nil, is_dir(dir)
end

--- Bump last_opened on an existing sandbox. Best-effort (never fails open).
---@param dir string
---@return table meta
function M._touch(dir)
  local meta = M.meta_read(dir)
  meta.last_opened = os.time()
  M.meta_write(dir, meta)
  return meta
end

--- Initial edit target for a sandbox: dir/subpath when the subpath exists, else dir.
---@param dir string sandbox root
---@param url_or_id string original url (or id, which has no subpath)
---@return string target
function M.edit_target(dir, url_or_id)
  if type(url_or_id) == "string" and url_or_id ~= "" then
    local parsed = url_mod.parse(url_or_id)
    if parsed and parsed.path and parsed.path ~= "" then
      local candidate = dir .. "/" .. parsed.path
      if is_dir(candidate) or vim.uv.fs_stat(candidate) ~= nil then
        return candidate
      end
    end
  end
  return dir
end

--- Sync clone worker. Tries explicit branch, then ls-remote default,
--- then main/master, then remote default (no --branch).
---@param url_str string
---@param opts table|nil { clone_src?, branch?, depth?, clone_args?, token? }
---@return string|nil dir, string|nil err
function M._clone_sync(url_str, opts)
  opts = opts or {}
  local parsed, perr = url_mod.parse(url_str)
  if not parsed then
    return nil, perr or "invalid url"
  end
  local id, iderr = M.id_for(url_str)
  if not id then
    return nil, iderr or "invalid url"
  end
  local cfg = active_config()
  local dest = M.dir_for(id)
  if is_dir(dest) then
    return nil, "sandbox already exists: " .. id
  end
  local depth = opts.depth ~= nil and opts.depth or cfg.clone_depth
  local extra = opts.clone_args ~= nil and opts.clone_args or cfg.clone_args
  local token = opts.token ~= nil and opts.token or resolve_token()
  local src = opts.clone_src or M._clone_src(parsed, token)

  local candidates = {}
  local seen = {}
  if opts.branch and opts.branch ~= "" then
    dedup_append(candidates, seen, opts.branch)
  elseif parsed.kind ~= "root" then
    dedup_append(candidates, seen, parsed.branch)
  end
  if not opts.clone_src or opts.branch == nil then
    -- ls-remote against the real remote; skip for injected local fixtures
    -- unless an explicit branch override was not given (still useful).
    local def = M._ls_remote_default(src)
    dedup_append(candidates, seen, def)
  end
  dedup_append(candidates, seen, "main")
  dedup_append(candidates, seen, "master")

  local last_err = nil
  for _, branch in ipairs(candidates) do
    local ok, err = M._git_clone(src, dest, branch, depth, extra)
    if ok then
      local now = os.time()
      M.meta_write(dest, {
        url = url_str,
        owner = parsed.owner,
        repo = parsed.repo,
        branch = branch,
        subpath = parsed.path or "",
        created = now,
        last_opened = now,
        clone_args = extra or {},
      })
      return dest, nil
    end
    last_err = err
  end
  -- final fallback: let the remote pick its default (no --branch)
  do
    local ok, err = M._git_clone(src, dest, nil, depth, extra)
    if ok then
      local now = os.time()
      M.meta_write(dest, {
        url = url_str,
        owner = parsed.owner,
        repo = parsed.repo,
        branch = parsed.branch or "main",
        subpath = parsed.path or "",
        created = now,
        last_opened = now,
        clone_args = extra or {},
      })
      return dest, nil
    end
    last_err = err
  end
  return nil, last_err or ("could not clone " .. M._redact(src))
end

local function done_cb(opts, dir, err)
  if opts and type(opts.on_done) == "function" then
    local ok, cb_err = pcall(opts.on_done, dir, err)
    if not ok then
      vim.notify("ghexplore: on_done failed: " .. tostring(cb_err), vim.log.levels.ERROR)
    end
  end
end

--- Clone (sync core; calls `opts.on_done` when given for M4 async callers).
---@param url_str string
---@param opts table|nil { on_done?: fun(dir, err), clone_src?, branch?, depth?, clone_args? }
---@return string|nil dir, string|nil err
function M.clone(url_str, opts)
  opts = opts or {}
  if type(url_str) ~= "string" or vim.trim(url_str) == "" then
    local err = "usage: :Ghexplore <url>"
    done_cb(opts, nil, err)
    return nil, err
  end
  local dir, err = M._clone_sync(url_str, opts)
  done_cb(opts, dir, err)
  return dir, err
end

--- Resolve existing (when reuse) or clone, then `on_done(dir|nil, err|nil)`.
--- Reopening an existing sandbox touches nothing on disk except `last_opened`
--- and never hits the network (offline-after-clone).
---@param url_or_id string
---@param opts table|nil { on_done?: fun(dir, err), reuse?: boolean, clone_src?, branch?, depth? }
---@return string|nil dir, string|nil err
function M.open(url_or_id, opts)
  opts = opts or {}
  if type(url_or_id) ~= "string" or vim.trim(url_or_id) == "" then
    local err = "usage: :Ghexplore <url>"
    done_cb(opts, nil, err)
    return nil, err
  end
  local cfg = active_config()
  local reuse = opts.reuse
  if reuse == nil then
    reuse = cfg.reuse
    if reuse == nil then
      reuse = true
    end
  end
  local id, dir, parsed, exists = M._resolve(url_or_id)
  if not id or not dir then
    local err = "invalid url or sandbox id"
    done_cb(opts, nil, err)
    return nil, err
  end
  if exists then
    if reuse then
      M._touch(dir)
      done_cb(opts, dir, nil)
      return dir, nil
    end
    -- reuse disabled: fresh clone
    local ok = rm_rf(dir)
    if not ok then
      local err = "cannot remove existing sandbox: " .. id
      done_cb(opts, nil, err)
      return nil, err
    end
  end
  if not parsed then
    -- an id with no local checkout and no URL to clone from
    local err = "no such sandbox: " .. id
    done_cb(opts, nil, err)
    return nil, err
  end
  local cdir, cerr = M._clone_sync(vim.trim(url_or_id), opts)
  done_cb(opts, cdir, cerr)
  return cdir, cerr
end

--- Delete a sandbox dir. The ONLY remover. Never prompts (UI confirms).
--- Refuses targets outside the sandbox root (safety).
---@param id_or_url string
---@param force boolean|nil accepted for API compat; always deletes without prompting
---@param on_done fun(ok: boolean, err: string|nil)|nil
---@return boolean ok, string|nil err
function M.discard(id_or_url, force, on_done)
  -- `force` is API compat (confirm lives in ui.lua); deletion is unconditional here.
  local _ = force
  local cb = nil
  if type(on_done) == "function" then
    cb = on_done
  elseif type(force) == "function" then
    cb = force -- tolerate discard(id, on_done)
  end
  local function finish(ok, err)
    if cb then
      pcall(cb, ok, err)
    end
    return ok, err
  end
  if type(id_or_url) ~= "string" or vim.trim(id_or_url) == "" then
    return finish(false, "usage: :GhexploreDiscard <name>")
  end
  local id, dir, _, exists = M._resolve(id_or_url)
  if not id or not dir then
    return finish(false, "invalid sandbox: " .. vim.trim(id_or_url))
  end
  local root = M.root()
  if not is_inside(root, dir) then
    return finish(false, "refusing to discard outside sandbox root: " .. dir)
  end
  if not exists then
    return finish(false, "no such sandbox: " .. id)
  end
  if rm_rf(dir) and vim.uv.fs_stat(dir) == nil then
    return finish(true, nil)
  end
  return finish(false, "could not discard " .. id)
end

return M
