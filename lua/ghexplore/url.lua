--- Pure URL parsing. No vim.*, no IO, no network. Fully headless-testable.
--- Port of ghgrab `github.rs` URL layer (see GHGRAB_IMPLEMENTATION.md §4).
local M = {}

local function trim(s)
  return s:match("^%s*(.-)%s*$") or s
end

local function strip_dot_git(repo)
  if repo:sub(-4) == ".git" then
    return repo:sub(1, -5)
  end
  return repo
end

local function sanitize_branch(branch)
  return (branch:gsub("[^A-Za-z0-9_.-]", "_"))
end

local function pct_encode(str)
  return (str:gsub("[^A-Za-z0-9%-%_%.%~]", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

-- Encode a repo path segment-wise? For GitLab we need full path encode
-- where "/" becomes %2F. So encode_path encodes everything except "~" etc
-- but also encodes "/". Helper encode_component does that. For owner%2Frepo
-- we encode "/" as %2F as well.
local function encode_component(s)
  return pct_encode(s)
end

--- Detect forge platform from host + path segments.
---@param host string e.g. "github.com"
---@param segments string[] non-empty path segments
---@return string platform "github"|"gitlab"|"gitea"
function M.detect_platform(host, segments)
  host = host:lower()
  if host == "github.com" then
    return "github"
  end
  if host == "gitlab.com" then
    return "gitlab"
  end
  if host == "codeberg.org" then
    return "gitea"
  end
  if segments and #segments >= 3 and segments[3] == "-" then
    return "gitlab"
  end
  return "gitea"
end

--- Parse a forge URL into its parts.
---@param url_str string e.g. "https://github.com/owner/repo/tree/main/src"
---@return table|nil parsed { platform, host, owner, repo, branch, path, kind }, string|nil err
function M.parse(url_str)
  if type(url_str) ~= "string" then
    return nil, "url must be a string"
  end
  local s = trim(url_str)
  if s == "" then
    return nil, "empty url"
  end

  -- Handle scp-like `git@host:owner/repo.git` -> https://host/owner/repo
  local ssh_host, ssh_path = s:match("^git@([^:]+):(.+)$")
  if ssh_host and ssh_path then
    s = "https://" .. ssh_host .. "/" .. ssh_path
  end

  -- Need scheme://host
  local scheme, host, rest = s:match("^(https?://)([^/%?#]+)(.*)$")
  if not host then
    return nil, "not a url"
  end
  -- host lower for detection but keep original lowercased
  local host_lc = host:lower()
  -- strip query/fragment from rest to get path
  local path_part = rest:match("^([^%?#]*)") or ""
  -- strip port? keep host as given without port normalization for api builders
  -- segments: split on "/", drop empties, drop trailing empty
  local segments = {}
  for seg in path_part:gmatch("[^/]+") do
    segments[#segments + 1] = seg
  end

  if #segments < 2 then
    return nil, "URL must contain owner and repository"
  end

  local owner = segments[1]
  local repo = strip_dot_git(segments[2])
  if owner == "" or repo == "" then
    return nil, "URL must contain owner and repository"
  end

  local platform = M.detect_platform(host_lc, segments)

  local branch = "main"
  local subpath = ""
  local kind = "root"

  if platform == "github" then
    if #segments >= 3 and (segments[3] == "tree" or segments[3] == "blob") then
      if #segments < 4 then
        return nil, "missing branch in url"
      end
      branch = segments[4]
      kind = segments[3] -- "tree" | "blob"
      if #segments > 4 then
        local parts = {}
        for i = 5, #segments do
          parts[#parts + 1] = segments[i]
        end
        subpath = table.concat(parts, "/")
      else
        subpath = ""
      end
    else
      branch = "main"
      subpath = ""
      kind = "root"
    end
  elseif platform == "gitlab" then
    -- /-/tree/<branch>/<path> or /-/blob/<branch>/<path>
    if #segments >= 5 and segments[3] == "-" and (segments[4] == "tree" or segments[4] == "blob") then
      branch = segments[5]
      kind = segments[4]
      if #segments > 5 then
        local parts = {}
        for i = 6, #segments do
          parts[#parts + 1] = segments[i]
        end
        subpath = table.concat(parts, "/")
      else
        subpath = ""
      end
    else
      branch = "main"
      subpath = ""
      kind = "root"
    end
  else -- gitea (codeberg, forgejo)
    -- /src/branch/<branch>/<path>  or  /src/commit/<sha>/<path> etc
    if #segments >= 5 and segments[3] == "src" then
      -- segments[4] is the ref type (branch/commit/tag), segments[5] is the branch/sha
      -- Some instances use `src/branch/main`, others `src/tag/v1.0` etc. We take seg[5] as branch
      -- Guard: if segments[4] is known ref type, branch is seg[5], else fall back to seg[4]
      local ref_type = segments[4]
      if ref_type == "branch" or ref_type == "commit" or ref_type == "tag" then
        if #segments >= 5 then
          branch = segments[5]
          kind = "tree"
          if #segments > 5 then
            local parts = {}
            for i = 6, #segments do
              parts[#parts + 1] = segments[i]
            end
            subpath = table.concat(parts, "/")
          else
            subpath = ""
          end
        end
      else
        -- fallback: earlier ghgrab heuristic: branch = seg[4], path = seg[5..]
        branch = segments[4]
        kind = "tree"
        if #segments > 4 then
          local parts = {}
          for i = 5, #segments do
            parts[#parts + 1] = segments[i]
          end
          subpath = table.concat(parts, "/")
        else
          subpath = ""
        end
      end
    else
      branch = "main"
      subpath = ""
      kind = "root"
    end
  end

  return {
    platform = platform,
    host = host_lc,
    owner = owner,
    repo = repo,
    branch = branch,
    path = subpath,
    kind = kind,
    raw = s,
  }
end

--- Build the directory-listing API URL for a parsed URL + subpath.
---@param parsed table output of M.parse
---@param path string|nil subpath override; nil => parsed.path
---@return string api url
function M.contents_api_url(parsed, path)
  assert(parsed and parsed.platform and parsed.owner and parsed.repo, "invalid parsed")
  local p = path
  if p == nil then
    p = parsed.path or ""
  end
  local owner = parsed.owner
  local repo = parsed.repo
  local branch = parsed.branch or "main"
  local host = parsed.host
  local platform = parsed.platform

  if platform == "github" then
    local base = string.format("https://api.github.com/repos/%s/%s/contents", owner, repo)
    if p ~= "" then
      base = base .. "/" .. p
    end
    return base .. "?ref=" .. pct_encode(branch)
  elseif platform == "gitlab" then
    -- https://{host}/api/v4/projects/{owner%2Frepo}/repository/tree?path={enc}&ref={branch}&per_page=100
    local pid = encode_component(owner .. "/" .. repo) -- %2F for slash
    local encoded_path = encode_component(p)
    -- For empty path GitLab still expects path param? Keep it empty string
    return string.format(
      "https://%s/api/v4/projects/%s/repository/tree?path=%s&ref=%s&per_page=100",
      host,
      pid,
      encoded_path,
      pct_encode(branch)
    )
  else -- gitea
    local base = string.format("https://%s/api/v1/repos/%s/%s/contents", host, owner, repo)
    if p ~= "" then
      base = base .. "/" .. p
    end
    return base .. "?ref=" .. pct_encode(branch)
  end
end

--- Build the raw-download URL for a file path.
---@param parsed table output of M.parse
---@param file_path string repo-relative file path
---@return string raw url
function M.raw_file_url(parsed, file_path)
  assert(parsed and parsed.platform and parsed.owner and parsed.repo, "invalid parsed")
  assert(type(file_path) == "string" and file_path ~= "", "file_path required")
  local owner = parsed.owner
  local repo = parsed.repo
  local branch = parsed.branch or "main"
  local host = parsed.host
  local platform = parsed.platform
  -- Normalize file_path: strip leading "/"
  file_path = file_path:gsub("^/+", "")

  if platform == "github" then
    return string.format("https://raw.githubusercontent.com/%s/%s/%s/%s", owner, repo, branch, file_path)
  elseif platform == "gitlab" then
    return string.format("https://%s/%s/%s/-/raw/%s/%s", host, owner, repo, branch, file_path)
  else -- gitea
    return string.format("https://%s/%s/%s/raw/branch/%s/%s", host, owner, repo, branch, file_path)
  end
end

--- True when the URL points at a single file (blob), not a tree.
---@param parsed table output of M.parse
---@return boolean
function M.is_file_url(parsed)
  return parsed and parsed.kind == "blob"
end

--- Filesystem-safe sandbox id: "<owner>__<repo>__<branch>".
--- The ONLY sanitizer; `sandbox.lua` must delegate here (DRY).
---@param parsed table output of M.parse
---@return string id
function M.sandbox_id(parsed)
  assert(parsed and parsed.owner and parsed.repo and parsed.branch, "invalid parsed")
  local b = sanitize_branch(parsed.branch)
  local o = sanitize_branch(parsed.owner)
  local r = sanitize_branch(parsed.repo)
  -- keep owner/repo as-is except sanitized for branch only? Spec says sanitize whole id.
  -- We sanitize each part to keep "__" separator intact.
  return o .. "__" .. r .. "__" .. b
end

return M
