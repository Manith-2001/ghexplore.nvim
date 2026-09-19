--- UI only. The ONLY module that calls vim.ui.* / nvim_open_win (orthogonality).
--- Never runs git/curl directly: delegates to `sandbox` / `grab` / `gh`.
--- M4: float picker for `:GhexploreList` + fetch_partial preview floats.
local M = {}

--- Active picker window/buffer (single instance; reopening hides the old one).
M._picker_win = nil
M._picker_buf = nil

local function active_config()
  local ok, init = pcall(require, "ghexplore")
  if ok and init and init.config then
    return init.config
  end
  local ok2, cfg = pcall(require, "ghexplore.config")
  if ok2 and cfg and cfg.defaults then
    return cfg.defaults
  end
  return { open_cmd = "tabnew | tcd %s | edit %s", confirm_discard = true, picker = "float" }
end

--- Plain `vim.ui.select` picker. Zero deps by design: telescope/snacks
--- override `vim.ui.select` when installed, so `picker = "select"`
--- auto-delegates with no hard dependency (compose, don't bundle).
local function select_picker(items, title, on_pick)
  vim.ui.select(items, { prompt = title .. ":", format_item = format_item }, function(choice)
    if choice then
      on_pick(choice)
    end
  end)
end

local function is_valid_win(win)
  return type(win) == "number" and vim.api.nvim_win_is_valid(win)
end

--- Close the active picker without side effects. Safe when none is open.
function M.close_picker()
  if is_valid_win(M._picker_win) then
    pcall(vim.api.nvim_win_hide, M._picker_win)
  end
  M._picker_win = nil
  M._picker_buf = nil
end

--- Generic centered float. Buffer-local `q`/`<Esc>` close only; never global maps.
---@param opts table|nil { width?, height?, title?, filetype? }
---@return integer buf, integer win
function M.float_win(opts)
  opts = opts or {}
  local cols = vim.o.columns > 0 and vim.o.columns or 80
  local lines = vim.o.lines > 0 and vim.o.lines or 24
  local width = math.min(opts.width or 72, math.max(cols - 4, 20))
  local height = math.min(opts.height or 16, math.max(lines - 4, 5))
  local row = math.max(math.floor((lines - height) / 2 - 1), 0)
  local col = math.max(math.floor((cols - width) / 2), 0)
  -- single instance: hide the old picker before opening a new float
  M.close_picker()
  local buf = vim.api.nvim_create_buf(false, true)
  local win_opts = {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
  }
  if opts.title and opts.title ~= "" then
    win_opts.title = " " .. opts.title .. " "
    win_opts.title_pos = "center"
  end
  local win = vim.api.nvim_open_win(buf, true, win_opts)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  if opts.filetype and opts.filetype ~= "" then
    pcall(function()
      vim.bo[buf].filetype = opts.filetype
    end)
  end
  vim.wo[win].cursorline = true
  pcall(function()
    vim.wo[win].number = false
  end)
  pcall(function()
    vim.wo[win].relativenumber = false
  end)
  local function close()
    if is_valid_win(win) then
      pcall(vim.api.nvim_win_hide, win)
    end
    if M._picker_win == win then
      M._picker_win = nil
      M._picker_buf = nil
    end
  end
  vim.keymap.set("n", "q", close, { buffer = buf, nowait = true, desc = "Ghexplore: close" })
  vim.keymap.set("n", "<Esc>", close, { buffer = buf, nowait = true, desc = "Ghexplore: close" })
  return buf, win
end

local function present(dir, url_or_id)
  local sandbox = require("ghexplore.sandbox")
  local target = sandbox.edit_target(dir, url_or_id or dir)
  local cfg = active_config()
  local fmt = cfg.open_cmd
  if type(fmt) ~= "string" or fmt == "" then
    fmt = "tabnew | tcd %s | edit %s"
  end
  local ok, err = pcall(vim.cmd, string.format(fmt, vim.fn.fnameescape(dir), vim.fn.fnameescape(target)))
  if not ok then
    vim.notify("ghexplore: cannot open sandbox: " .. tostring(err), vim.log.levels.ERROR)
    return false
  end
  return true
end

--- Open a sandbox: prompt when empty, then tabnew + tcd + edit.
---@param url string empty => prompt via vim.ui.input
function M.open(url)
  if url == nil or (type(url) == "string" and vim.trim(url) == "") then
    vim.ui.input({ prompt = "Ghexplore URL: ", default = "https://github.com/" }, function(input)
      if input ~= nil and vim.trim(input) ~= "" then
        M.open(input)
      end
    end)
    return
  end
  local input = vim.trim(url)
  vim.notify("ghexplore: opening " .. input .. " …", vim.log.levels.INFO)
  local sandbox = require("ghexplore.sandbox")
  sandbox.open(input, {
    on_done = function(dir, err)
      vim.schedule(function()
        if not dir then
          vim.notify("ghexplore: " .. (err or "open failed"), vim.log.levels.ERROR)
          return
        end
        if present(dir, input) then
          local id = sandbox.id_for(input) or dir:match("([^/]+)$") or dir
          vim.notify("ghexplore: opened " .. id, vim.log.levels.INFO)
        end
      end)
    end,
  })
end

local function format_item(it)
  local meta = it.meta or {}
  local when = ""
  if it.last_opened and it.last_opened > 0 then
    when = " (" .. os.date("%Y-%m-%d %H:%M", it.last_opened) .. ")"
  end
  local branch = meta.branch and meta.branch ~= "" and (" @" .. meta.branch) or ""
  return it.id .. branch .. when
end

--- Float picker over sandbox items. Buffer-local `<CR>/d/q` only
--- (`j/k` are native cursor motions; no global maps).
--- `<CR>` resumes (or `opts.on_pick`), `d` discards, `q`/`<Esc>` closes.
---@param items table[] from sandbox.list()
---@param opts table|nil { title?, on_pick?: fun(item) }
---@return integer|nil buf, integer|nil win
function M.open_picker(items, opts)
  opts = opts or {}
  local on_pick = opts.on_pick
  if type(on_pick) ~= "function" then
    on_pick = function(choice)
      M.open(choice.id)
    end
  end
  if not items or #items == 0 then
    vim.notify("ghexplore: no sandboxes", vim.log.levels.INFO)
    return nil, nil
  end
  local lines = {}
  for _, it in ipairs(items) do
    lines[#lines + 1] = format_item(it)
  end
  local buf, win
  local ok, err = pcall(function()
    buf, win = M.float_win({
      width = 72,
      height = math.min(math.max(#lines, 5), 16),
      title = opts.title or "Ghexplore sandboxes",
      filetype = "ghexplore",
    })
  end)
  if not ok or not buf or not win then
    -- headless / UI-less fallback: plain vim.ui.select (zero deps)
    select_picker(items, opts.title or "Ghexplore sandboxes", on_pick)
    return nil, nil
  end
  M._picker_buf = buf
  M._picker_win = win
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly = true
  pcall(vim.api.nvim_win_set_cursor, win, { 1, 0 })

  local function current_choice()
    local cursor = vim.api.nvim_win_get_cursor(win)
    return items[cursor[1]]
  end
  vim.keymap.set("n", "<CR>", function()
    local choice = current_choice()
    M.close_picker()
    if choice then
      on_pick(choice)
    end
  end, { buffer = buf, nowait = true, desc = "Ghexplore: resume sandbox" })
  vim.keymap.set("n", "d", function()
    local choice = current_choice()
    M.close_picker()
    if choice then
      M.discard(choice.id, false)
    end
  end, { buffer = buf, nowait = true, desc = "Ghexplore: discard sandbox" })
  return buf, win
end

--- List/resume sandboxes. `picker = "select"` uses vim.ui.select
--- (telescope/snacks delegate); default "float" uses the float picker
--- with a vim.ui.select fallback when no window UI is available.
function M.list()
  local sandbox = require("ghexplore.sandbox")
  local items = sandbox.list()
  if #items == 0 then
    vim.notify("ghexplore: no sandboxes", vim.log.levels.INFO)
    return
  end
  if active_config().picker == "select" then
    select_picker(items, "Ghexplore sandboxes", function(choice)
      M.open(choice.id)
    end)
    return
  end
  M.open_picker(items, { title = "Ghexplore sandboxes" })
end

--- Discard a sandbox, with confirm unless `bang`.
--- Empty name => pick via float picker first.
---@param name string empty => prompt
---@param bang boolean skip confirm
function M.discard(name, bang)
  local input = type(name) == "string" and vim.trim(name) or ""
  local sandbox = require("ghexplore.sandbox")
  if input == "" then
    local items = sandbox.list()
    M.open_picker(items, {
      title = "Discard sandbox",
      on_pick = function(choice)
        M.discard(choice.id, bang)
      end,
    })
    return
  end
  local function do_discard()
    local ok, err = sandbox.discard(input, true)
    if ok then
      vim.notify("ghexplore: discarded " .. input, vim.log.levels.INFO)
    else
      vim.notify("ghexplore: " .. (err or "discard failed"), vim.log.levels.ERROR)
    end
  end
  local cfg = active_config()
  if bang or cfg.confirm_discard == false then
    do_discard()
    return
  end
  vim.ui.select({ "Yes", "No" }, { prompt = "Discard sandbox " .. input .. "?" }, function(choice)
    if choice == "Yes" then
      do_discard()
    end
  end)
end

--- Preview a remote file (first 8KB) in a float. No clone, no disk write.
--- Filetype is detected from the filename; highlighting reuses Treesitter.
---@param file_url string empty => prompt via vim.ui.input
---@param opts table|nil { max_bytes?, title? }
---@return integer|nil buf, integer|nil win
function M.preview(file_url, opts)
  opts = opts or {}
  if file_url == nil or (type(file_url) == "string" and vim.trim(file_url) == "") then
    vim.ui.input({ prompt = "Ghexplore file URL: ", default = "https://github.com/" }, function(input)
      if input ~= nil and vim.trim(input) ~= "" then
        M.preview(input, opts)
      end
    end)
    return nil, nil
  end
  local url_mod = require("ghexplore.url")
  local parsed, perr = url_mod.parse(file_url)
  if not parsed then
    vim.notify("ghexplore: " .. (perr or "invalid url"), vim.log.levels.ERROR)
    return nil, nil
  end
  if parsed.kind ~= "blob" or parsed.path == "" then
    vim.notify("ghexplore: not a file url (expected .../blob/<branch>/<path>)", vim.log.levels.ERROR)
    return nil, nil
  end
  local max_bytes = opts.max_bytes or 8192
  local raw = url_mod.raw_file_url(parsed, parsed.path)
  local cfg = active_config()
  local auth_ok, auth = pcall(require, "ghexplore.auth")
  local token = auth_ok and auth and auth.resolve_token({ token = cfg.token }) or nil
  local gh = require("ghexplore.gh")
  local data, gerr = gh.fetch_partial(raw, token, max_bytes)
  if not data then
    local msg = gerr
        and (gerr.code .. (gerr.status and (" (" .. gerr.status .. ")") or "") .. ": " .. (gerr.message or ""))
      or "preview failed"
    vim.notify("ghexplore: " .. msg, vim.log.levels.ERROR)
    return nil, nil
  end
  local name = parsed.path:match("([^/]+)$") or parsed.path
  local body_lines
  if data:find("\0", 1, true) then
    body_lines = { "-- binary file (preview truncated) --" }
  else
    body_lines = vim.split(data, "\n", { plain = true })
    if #body_lines > 400 then
      body_lines = vim.list_slice(body_lines, 1, 400)
      body_lines[#body_lines + 1] = "… (truncated)"
    end
  end
  local buf, win = M.float_win({ width = 80, height = 20, title = opts.title or name })
  local ft = vim.filetype.match({ filename = name })
  if ft then
    pcall(function()
      vim.bo[buf].filetype = ft
    end)
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, body_lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly = true
  pcall(vim.api.nvim_win_set_cursor, win, { 1, 0 })
  return buf, win
end

return M
