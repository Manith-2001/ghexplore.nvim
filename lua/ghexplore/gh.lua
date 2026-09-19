--- Forge HTTP layer. The ONLY place that runs curl (DRY).
--- Uses `vim.system({"curl",...})`; maps HTTP status to typed errors:
--- { code = "InvalidToken"|"RateLimit"|"NotFound"|"ApiError"|"CurlError"|"DecodeError", ... }.
local M = {}

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Pick the Authorization header value for a URL + token.
--- GitLab uses `Bearer`, GitHub/Gitea use `token` (see `auth.auth_header`).
---@param token string
---@param url string request url (used to infer platform)
---@return string header value
function M._header_value(token, url)
  local platform = "github"
  if url:find("/api/v4/", 1, true) or url:find("gitlab", 1, true) then
    platform = "gitlab"
  end
  local ok, auth = pcall(require, "ghexplore.auth")
  if ok and auth and auth.auth_header then
    return auth.auth_header(token, platform)
  end
  if platform == "gitlab" then
    return "Bearer " .. token
  end
  return "token " .. token
end

--- Parse a curl `-D` header dump: last HTTP status + rate-limit remaining.
---@param head string raw header dump
---@return integer|nil status, string|nil remaining
function M._parse_headers(head)
  if type(head) ~= "string" or head == "" then
    return nil, nil
  end
  local status = nil
  for code in head:gmatch("HTTP/%S+ (%d%d%d)") do
    status = tonumber(code)
  end
  -- header names are case-insensitive; scan lines, keep last match
  local remaining = nil
  for line in head:gmatch("[^\r\n]+") do
    local name, val = line:match("^%s*([^:]+)%s*:%s*(%S+)")
    if name and val and name:lower() == "x-ratelimit-remaining" then
      remaining = trim(val)
    end
  end
  return status, remaining
end

local function read_file_bin(path)
  local f, ferr = io.open(path, "rb")
  if not f then
    return nil, ferr
  end
  local data = f:read("*a")
  f:close()
  return data or ""
end

local function map_status(status, url, has_token, remaining)
  if status >= 200 and status <= 299 then
    return nil
  end
  if status == 401 and has_token then
    return { code = "InvalidToken", status = status, url = url, message = "Invalid token. Check GITHUB_TOKEN." }
  end
  if status == 403 then
    if remaining == "0" then
      return {
        code = "RateLimit",
        status = status,
        url = url,
        message = "Rate limit reached. Set GITHUB_TOKEN to raise the limit.",
      }
    end
    if has_token then
      return { code = "InvalidToken", status = status, url = url, message = "Forbidden: token may be invalid." }
    end
    return { code = "RateLimit", status = status, url = url, message = "Forbidden (possible rate limit)." }
  end
  if status == 404 then
    return { code = "NotFound", status = status, url = url, message = "Not found: " .. url }
  end
  return { code = "ApiError", status = status, url = url, message = "HTTP " .. tostring(status) .. " for " .. url }
end

--- Low-level GET. Returns body string or (nil, err-table).
---@param url string
---@param token string|nil
---@param extra_args string[]|nil extra curl args (e.g. { "-H", "Range: bytes=0-100" })
---@return string|nil body, table|nil err
function M.request(url, token, extra_args)
  assert(type(url) == "string" and url ~= "", "url required")
  if vim.fn.executable("curl") ~= 1 then
    return nil, { code = "CurlError", url = url, message = "curl not found in PATH" }
  end
  local body_tmp = vim.fn.tempname()
  local head_tmp = vim.fn.tempname()
  local args = {
    "curl",
    "-sS",
    "-L",
    "--max-time",
    "30",
    "-D",
    head_tmp,
    "-o",
    body_tmp,
    "-H",
    "User-Agent: ghexplore.nvim",
    "-H",
    "Accept: application/vnd.github+json",
  }
  if token and token ~= "" then
    args[#args + 1] = "-H"
    args[#args + 1] = "Authorization: " .. M._header_value(token, url)
  end
  if extra_args then
    for _, a in ipairs(extra_args) do
      args[#args + 1] = a
    end
  end
  args[#args + 1] = url

  local ok, result = pcall(function()
    return vim.system(args):wait()
  end)
  if not ok or not result then
    pcall(os.remove, body_tmp)
    pcall(os.remove, head_tmp)
    return nil, { code = "CurlError", url = url, message = "failed to run curl" }
  end
  if result.code ~= 0 then
    local stderr = ""
    if type(result.stderr) == "string" then
      stderr = trim(result.stderr)
    end
    pcall(os.remove, body_tmp)
    pcall(os.remove, head_tmp)
    return nil, { code = "CurlError", url = url, message = stderr ~= "" and stderr or "curl exited " .. result.code }
  end

  local head = read_file_bin(head_tmp) or ""
  local body = read_file_bin(body_tmp)
  pcall(os.remove, body_tmp)
  pcall(os.remove, head_tmp)
  if body == nil then
    return nil, { code = "CurlError", url = url, message = "could not read curl response body" }
  end

  local status, remaining = M._parse_headers(head)
  if not status then
    return nil, { code = "CurlError", url = url, message = "could not parse HTTP status from curl headers" }
  end
  local err = map_status(status, url, token ~= nil and token ~= "", remaining)
  if err then
    return nil, err
  end
  return body, nil
end

--- List a directory via the forge contents API. Decoded JSON or (nil, err).
---@param api_url string from url.contents_api_url()
---@param token string|nil
---@return table|nil items, table|nil err
function M.fetch_contents(api_url, token)
  local body, err = M.request(api_url, token)
  if not body then
    return nil, err
  end
  local ok, decoded = pcall(vim.json.decode, body)
  if not ok or decoded == nil then
    return nil, { code = "DecodeError", url = api_url, message = "could not decode JSON from " .. api_url }
  end
  return decoded, nil
end

--- Download raw bytes. Returns string (may be binary) or (nil, err).
---@param raw_url string from url.raw_file_url()
---@param token string|nil
---@return string|nil data, table|nil err
function M.fetch_bytes(raw_url, token)
  return M.request(raw_url, token)
end

--- Download at most `max_bytes` (Range header) for previews.
---@param raw_url string
---@param token string|nil
---@param max_bytes integer|nil default 8192
---@return string|nil data, table|nil err
function M.fetch_partial(raw_url, token, max_bytes)
  max_bytes = max_bytes or 8192
  assert(type(max_bytes) == "number" and max_bytes >= 1, "max_bytes must be >= 1")
  -- 206 Partial Content and 200 OK both accepted by request()'s 2xx mapping.
  return M.request(raw_url, token, { "-H", string.format("Range: bytes=0-%d", max_bytes - 1) })
end

return M
