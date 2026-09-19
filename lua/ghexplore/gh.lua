--- Forge HTTP layer. The ONLY place that runs curl (DRY).
--- Uses `vim.system({"curl",...})`; maps HTTP status to typed errors:
--- { code = "InvalidToken"|"RateLimit"|"NotFound"|"ApiError", ... }.
--- M2 implements this; M0 holds the contract.
local M = {}

--- Low-level GET. Returns body string or (nil, err-table).
---@param url string
---@param token string|nil
---@param extra_args string[]|nil extra curl args (e.g. Range header)
---@return string|nil body, table|nil err
function M.request(url, token, extra_args)
  error("ghexplore.gh: not implemented (M2)")
end

--- List a directory via the forge contents API. Decoded array or (nil, err).
---@param api_url string from url.contents_api_url()
---@param token string|nil
---@return table|nil items, table|nil err
function M.fetch_contents(api_url, token)
  error("ghexplore.gh: not implemented (M2)")
end

--- Download raw bytes. Returns string (may be binary) or (nil, err).
---@param raw_url string from url.raw_file_url()
---@param token string|nil
---@return string|nil data, table|nil err
function M.fetch_bytes(raw_url, token)
  error("ghexplore.gh: not implemented (M2)")
end

--- Download at most `max_bytes` (Range header) for previews.
---@param raw_url string
---@param token string|nil
---@param max_bytes integer default 8192
---@return string|nil data, table|nil err
function M.fetch_partial(raw_url, token, max_bytes)
  error("ghexplore.gh: not implemented (M2)")
end

return M
