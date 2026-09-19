--- Sandbox lifecycle. The ONLY module that touches sandbox dirs + metadata (DRY).
--- Layout: <data_dir>/sandboxes/<owner>__<repo>__<branch>/.ghexplore.json
--- Never calls vim.ui.* (orthogonality: UI lives in `ui.lua`).
--- M3 implements this; M0 holds the contract.
local M = {}

--- Root dir holding all sandboxes. Creates it on demand.
---@return string path
function M.root()
  error("ghexplore.sandbox: not implemented (M3)")
end

--- Sandbox id for a URL string. Delegates to `url.sandbox_id` (no second sanitizer).
---@param url_str string
---@return string id
function M.id_for(url_str)
  error("ghexplore.sandbox: not implemented (M3)")
end

--- Read `.ghexplore.json` for a sandbox dir. Returns {} when absent.
---@param dir string
---@return table meta
function M.meta_read(dir)
  error("ghexplore.sandbox: not implemented (M3)")
end

--- Write `.ghexplore.json`. The ONLY metadata writer.
---@param dir string
---@param meta table
function M.meta_write(dir, meta)
  error("ghexplore.sandbox: not implemented (M3)")
end

--- List sandboxes sorted by last_opened desc.
---@return table[] { id, dir, meta }
function M.list()
  error("ghexplore.sandbox: not implemented (M3)")
end

--- Clone (async) or reuse a sandbox. Calls `on_done(dir|nil, err|nil)`.
---@param url_str string
---@param opts table|nil { on_done?: fun(dir, err) }
function M.clone(url_str, opts)
  error("ghexplore.sandbox: not implemented (M3)")
end

--- Resolve existing (when reuse) or clone, then `on_done(dir|nil, err|nil)`.
---@param url_or_id string
---@param opts table|nil { on_done?: fun(dir, err) }
function M.open(url_or_id, opts)
  error("ghexplore.sandbox: not implemented (M3)")
end

--- Delete a sandbox dir. The ONLY remover.
---@param id_or_url string
---@param force boolean|nil skip confirm when true
---@param on_done fun(ok: boolean, err: string|nil)|nil
function M.discard(id_or_url, force, on_done)
  error("ghexplore.sandbox: not implemented (M3)")
end

return M
