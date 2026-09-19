--- Single-file grab (ghgrab parity). No git, no UI picker here.
--- Uses `gh` for HTTP, `url` for parsing. M2 implements; M0 holds the contract.
local M = {}

local url_mod = require("ghexplore.url")
local auth_mod = require("ghexplore.auth")

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
  local ok, err = pcall(vim.fn.mkdir, dir, "p")
  if not ok or vim.v.shell_error ~= 0 then
    return false, err
  end
  return true
end

local function basename(path)
  return path:match("([^/]+)$") or path
end

local function active_config()
  local ok, init = pcall(require, "ghexplore")
  if ok and init and init.config then
    return init.config
  end
  local ok2, cfg = pcall(require, "ghexplore.config")
  if ok2 and cfg and cfg.defaults then
    return cfg.defaults
  end
  return { download_path = vim.fn.expand("~/Downloads") }
end

local function resolve_token()
  local cfg = active_config()
  return auth_mod.resolve_token({ token = cfg.token })
end

--- Where would `grab(file_url, dest)` write? Pure-ish: no IO, no network.
---@param file_url string
---@param dest string|nil file or directory; nil => config.download_path
---@return string|nil path, string|nil err
function M.target_path(file_url, dest)
  local parsed, perr = url_mod.parse(file_url)
  if not parsed then
    return nil, perr or "invalid url"
  end
  if parsed.kind ~= "blob" or parsed.path == "" then
    return nil, "not a file url (expected .../blob/<branch>/<path>)"
  end
  local base = dest
  if base == nil or base == "" then
    base = active_config().download_path
  end
  base = vim.fn.expand(base)
  -- Trailing "/" explicitly means a directory target (mkdir -p it).
  if base:sub(-1) == "/" then
    return base .. basename(parsed.path), nil
  end
  local st = vim.uv.fs_stat(base)
  if st and st.type == "directory" then
    return base .. "/" .. basename(parsed.path), nil
  end
  -- base is a file target (existing file or non-existent path with a parent).
  -- If it has no directory part (bare filename), anchor under download_path.
  if base:find("/", 1, true) == nil and (not st or st.type ~= "file") then
    local dl = vim.fn.expand(active_config().download_path)
    return dl .. "/" .. base, nil
  end
  return base, nil
end

--- Grab one file URL to `dest` (file or dir). Notifies on success/failure.
--- Uses `url.raw_file_url` + `gh.fetch_bytes`; token from M1 `auth.resolve_token`.
---@param file_url string e.g. "https://github.com/owner/repo/blob/main/README.md"
---@param dest string|nil file or directory; nil => config.download_path
---@return string|nil written_path, string|nil err
function M.grab(file_url, dest)
  if type(file_url) ~= "string" or vim.trim(file_url) == "" then
    local msg = "usage: :GhexploreGrab <file-url> [dest]"
    vim.notify("ghexplore: " .. msg, vim.log.levels.ERROR)
    return nil, msg
  end
  local parsed, perr = url_mod.parse(file_url)
  if not parsed then
    vim.notify("ghexplore: " .. (perr or "invalid url"), vim.log.levels.ERROR)
    return nil, perr or "invalid url"
  end
  if parsed.kind ~= "blob" or parsed.path == "" then
    local msg = "not a file url (expected .../blob/<branch>/<path>)"
    vim.notify("ghexplore: " .. msg, vim.log.levels.ERROR)
    return nil, msg
  end

  local target, terr = M.target_path(file_url, dest)
  if not target then
    vim.notify("ghexplore: " .. terr, vim.log.levels.ERROR)
    return nil, terr
  end

  local gh = require("ghexplore.gh")
  local raw = url_mod.raw_file_url(parsed, parsed.path)
  local token = resolve_token()
  local data, gerr = gh.fetch_bytes(raw, token)
  if not data then
    local msg = gerr
        and (gerr.code .. (gerr.status and (" (" .. gerr.status .. ")") or "") .. ": " .. (gerr.message or ""))
      or "download failed"
    vim.notify("ghexplore: " .. msg, vim.log.levels.ERROR)
    return nil, msg
  end

  local parent = vim.fn.fnamemodify(target, ":h")
  local ok, merr = mkdir_p(parent)
  if not ok then
    local msg = "cannot create directory " .. parent .. (merr and (": " .. tostring(merr)) or "")
    vim.notify("ghexplore: " .. msg, vim.log.levels.ERROR)
    return nil, msg
  end
  local f, ferr = io.open(target, "wb")
  if not f then
    local msg = "cannot write " .. target .. ": " .. tostring(ferr)
    vim.notify("ghexplore: " .. msg, vim.log.levels.ERROR)
    return nil, msg
  end
  f:write(data)
  f:close()
  vim.notify("ghexplore: grabbed " .. target, vim.log.levels.INFO)
  return target, nil
end

return M
