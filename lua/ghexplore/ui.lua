--- UI only. The ONLY module that calls vim.ui.* / nvim_open_win (orthogonality).
--- Never runs git/curl directly: delegates to `sandbox` / `grab` / `gh`.
--- M3 ships headless-working select/input flows; M4 adds the float picker.
local M = {}

local function active_config()
  local ok, init = pcall(require, "ghexplore")
  if ok and init and init.config then
    return init.config
  end
  local ok2, cfg = pcall(require, "ghexplore.config")
  if ok2 and cfg and cfg.defaults then
    return cfg.defaults
  end
  return { open_cmd = "tabnew | tcd %s | edit %s", confirm_discard = true }
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
    vim.ui.input({ prompt = "Ghexplore URL: ", default = "" }, function(input)
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

--- List/resume sandboxes via vim.ui.select (M4 upgrades to a float).
function M.list()
  local sandbox = require("ghexplore.sandbox")
  local items = sandbox.list()
  if #items == 0 then
    vim.notify("ghexplore: no sandboxes", vim.log.levels.INFO)
    return
  end
  vim.ui.select(items, {
    prompt = "Ghexplore sandboxes:",
    format_item = format_item,
  }, function(choice)
    if choice then
      M.open(choice.id)
    end
  end)
end

--- Discard a sandbox, with confirm unless `bang`.
--- Empty name => pick via vim.ui.select first.
---@param name string empty => prompt
---@param bang boolean skip confirm
function M.discard(name, bang)
  local input = type(name) == "string" and vim.trim(name) or ""
  local sandbox = require("ghexplore.sandbox")
  if input == "" then
    local items = sandbox.list()
    if #items == 0 then
      vim.notify("ghexplore: no sandboxes", vim.log.levels.INFO)
      return
    end
    vim.ui.select(items, {
      prompt = "Discard sandbox:",
      format_item = format_item,
    }, function(choice)
      if choice then
        M.discard(choice.id, bang)
      end
    end)
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

return M
