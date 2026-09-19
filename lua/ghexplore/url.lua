--- Pure URL parsing. No vim.*, no IO, no network. Fully headless-testable.
--- Port of ghgrab `github.rs` URL layer (see GHGRAB_IMPLEMENTATION.md §4).
--- M1 implements this; M0 holds the contract (signatures + docs).
local M = {}

--- Detect forge platform from host + path segments.
---@param host string e.g. "github.com"
---@param segments string[] non-empty path segments
---@return string "github"|"gitlab"|"gitea"
function M.detect_platform(host, segments)
  error("ghexplore.url: not implemented (M1)")
end

--- Parse a forge URL into its parts.
---@param url_str string e.g. "https://github.com/owner/repo/tree/main/src"
---@return table|nil parsed { platform, host, owner, repo, branch, path, kind }, string|nil err
---@example
---  parse("https://github.com/rust-lang/rust/tree/master/src/tools")
---  --> { platform="github", host="github.com", owner="rust-lang",
---        repo="rust", branch="master", path="src/tools", kind="tree" }
function M.parse(url_str)
  error("ghexplore.url: not implemented (M1)")
end

--- Build the directory-listing API URL for a parsed URL + subpath.
---@param parsed table output of M.parse
---@param path string|nil subpath override; nil => parsed.path
---@return string api url
function M.contents_api_url(parsed, path)
  error("ghexplore.url: not implemented (M1)")
end

--- Build the raw-download URL for a file path.
---@param parsed table output of M.parse
---@param file_path string repo-relative file path
---@return string raw url
function M.raw_file_url(parsed, file_path)
  error("ghexplore.url: not implemented (M1)")
end

--- True when the URL points at a single file (blob), not a tree.
---@param parsed table output of M.parse
---@return boolean
function M.is_file_url(parsed)
  error("ghexplore.url: not implemented (M1)")
end

--- Filesystem-safe sandbox id: "<owner>__<repo>__<branch>".
--- The ONLY sanitizer; `sandbox.lua` must delegate here (DRY).
---@param parsed table output of M.parse
---@return string id
function M.sandbox_id(parsed)
  error("ghexplore.url: not implemented (M1)")
end

return M
