--- Token resolution. Single canonical auth path (DRY).
--- Precedence: opts.token (string|function) -> GHGRAB_GITHUB_TOKEN ->
--- GITHUB_TOKEN -> `gh auth token` (non-strict). Never echoes the token.
--- M1 implements this; M0 holds the contract.
local M = {}

--- Resolve a token for `platform`. Returns nil for anonymous use.
---@param opts table|nil { token?: string|fun():string|nil, platform?: string }
---@return string|nil token
function M.resolve_token(opts)
  error("ghexplore.auth: not implemented (M1)")
end

--- Build the Authorization header value for a platform.
--- GitLab uses `Bearer`, GitHub/Gitea use `token`.
---@param token string
---@param platform string "github"|"gitlab"|"gitea"
---@return string header value
function M.auth_header(token, platform)
  error("ghexplore.auth: not implemented (M1)")
end

return M
