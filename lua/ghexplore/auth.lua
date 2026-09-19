--- Token resolution. Single canonical auth path (DRY).
--- Precedence: opts.token (string|function) -> GHGRAB_GITHUB_TOKEN ->
--- GITHUB_TOKEN -> `gh auth token` (non-strict). Never echoes the token.
local M = {}

local function trim(s)
  if type(s) ~= "string" then
    return s
  end
  return s:match("^%s*(.-)%s*$") or s
end

local function is_auto(s)
  if type(s) ~= "string" then
    return false
  end
  local t = trim(s):lower()
  return t == "auto" or t == "gh"
end

local function get_env(name)
  local v = nil
  if vim and vim.env and vim.env[name] ~= nil then
    v = vim.env[name]
  end
  if v == nil and os and os.getenv then
    v = os.getenv(name)
  end
  if type(v) == "string" then
    v = trim(v)
    if v ~= "" then
      return v
    end
  end
  return nil
end

local function parse_gh_stdout(out)
  local seen = {}
  local tokens = {}
  if not out or out == "" then
    return tokens
  end
  for line in out:gmatch("[^\r\n]+") do
    local t = trim(line)
    if t ~= "" and not seen[t] then
      seen[t] = true
      tokens[#tokens + 1] = t
    end
  end
  return tokens
end

local function try_gh_token()
  if vim.fn.executable("gh") ~= 1 then
    return nil
  end
  local ok, result = pcall(function()
    return vim.system({ "gh", "auth", "token" }, { text = true }):wait()
  end)
  if not ok or not result then
    return nil
  end
  if result.code ~= 0 then
    return nil
  end
  local tokens = parse_gh_stdout(result.stdout or "")
  if #tokens == 0 then
    return nil
  end
  return tokens[1]
end

--- Resolve a token for `platform`. Returns nil for anonymous use.
---@param opts table|nil { token?: string|fun():string|nil }
---@return string|nil token
function M.resolve_token(opts)
  opts = opts or {}
  local provided = opts.token

  if provided ~= nil then
    local tok = provided
    if type(tok) == "function" then
      local ok, val = pcall(tok)
      if ok then
        tok = val
      else
        tok = nil
      end
    end
    if type(tok) == "string" then
      tok = trim(tok)
      if tok ~= "" then
        if is_auto(tok) then
          return try_gh_token()
        end
        return tok
      end
      -- empty string falls through to env
    end
    -- function returned nil/empty or wrong type falls through
  end

  local env_val = get_env("GHGRAB_GITHUB_TOKEN")
  if env_val == nil then
    env_val = get_env("GITHUB_TOKEN")
  end
  if env_val ~= nil then
    if is_auto(env_val) then
      return try_gh_token()
    end
    return env_val
  end

  -- config file skipped in v1

  return try_gh_token()
end

--- Build the Authorization header value for a platform.
--- GitLab uses `Bearer`, GitHub/Gitea use `token`.
---@param token string
---@param platform string "github"|"gitlab"|"gitea"
---@return string header value
function M.auth_header(token, platform)
  assert(type(token) == "string" and token ~= "", "token required")
  if platform == "gitlab" then
    return "Bearer " .. token
  end
  return "token " .. token
end

-- exposed for tests only
M._parse_gh_stdout = parse_gh_stdout
M._is_auto = is_auto

return M
