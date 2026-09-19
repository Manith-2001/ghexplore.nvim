-- M4: float picker + preview tests. Picker open/close/keys are UI-only (no network);
-- preview content assertions use a stubbed gh.fetch_partial (no network).
describe("ghexplore.ui picker", function()
  local ui = require("ghexplore.ui")

  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp, "p")
  require("ghexplore").setup({ data_dir = tmp .. "/data", jobs = 1 })
  local sandbox = require("ghexplore.sandbox")

  local function sandbox_items(n)
    for i = 1, n do
      assert(sandbox.meta_write(sandbox.dir_for(string.format("o__r%d__main", i)), { last_opened = i }))
    end
    local items = sandbox.list()
    assert(#items >= n)
    return items
  end

  it("open_picker renders one line per item, buffers-local q/Esc/<CR>/d", function()
    local items = sandbox_items(3)
    local buf, win = ui.open_picker(items, { title = "test" })
    assert(buf and win, "picker did not open")
    assert(vim.api.nvim_win_is_valid(win))
    assert(vim.bo[buf].filetype == "ghexplore")
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert(#lines == #items, vim.inspect(lines))
    local maps = vim.api.nvim_buf_get_keymap(buf, "n")
    local lhs = {}
    for _, m in ipairs(maps) do
      lhs[m.lhs] = true
    end
    assert(lhs["q"] and lhs["<Esc>"] and lhs["<CR>"] and lhs["d"], vim.inspect(lhs))
    -- no global maps polluted
    for _, m in ipairs(vim.api.nvim_get_keymap("n")) do
      assert(m.lhs ~= "(GhexplorePickerTest)", "global map leaked")
    end
    ui.close_picker()
    assert(not vim.api.nvim_win_is_valid(win))
    assert(sandbox.discard("o__r1__main", true))
    assert(sandbox.discard("o__r2__main", true))
    assert(sandbox.discard("o__r3__main", true))
  end)

  it("close_picker is safe with nothing open", function()
    ui.close_picker()
    ui.close_picker()
  end)

  it("open_picker with no items notifies and returns nil", function()
    local notified = nil
    local orig = vim.notify
    vim.notify = function(msg, level)
      notified = msg
    end
    local buf, win = ui.open_picker({}, {})
    vim.notify = orig
    assert(buf == nil and win == nil)
    assert(notified and notified:find("no sandboxes", 1, true), vim.inspect(notified))
  end)

  it("preview rejects tree urls without network", function()
    local notified = nil
    local orig = vim.notify
    vim.notify = function(msg, level)
      notified = msg
    end
    local buf, win = ui.preview("https://github.com/o/r/tree/main/src", {})
    vim.notify = orig
    assert(buf == nil and win == nil)
    assert(notified and notified:find("not a file url", 1, true), vim.inspect(notified))
  end)

  it("preview renders stubbed bytes with detected filetype", function()
    local gh = require("ghexplore.gh")
    local orig_partial = gh.fetch_partial
    gh.fetch_partial = function()
      return "print('hi')\n", nil
    end
    local buf, win = ui.preview("https://github.com/o/r/blob/main/a.lua", {})
    gh.fetch_partial = orig_partial
    assert(buf and win, "preview did not open")
    assert(vim.bo[buf].filetype == "lua", vim.inspect(vim.bo[buf].filetype))
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert(lines[1] == "print('hi')", vim.inspect(lines))
    ui.close_picker()
  end)

  it("float_win honors ftplugin buffer-local opts", function()
    local items = sandbox_items(2)
    local buf, win = ui.open_picker(items, {})
    assert(buf and win)
    -- ftplugin ran on BufEnter/filetype set (headless still applies opt_local)
    assert(vim.bo[buf].filetype == "ghexplore")
    ui.close_picker()
    assert(sandbox.discard("o__r1__main", true))
    assert(sandbox.discard("o__r2__main", true))
  end)
end)
