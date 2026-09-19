-- M5: config.validate full coverage + health masked-token/actionable checks.
-- No network. Stubs executables/paths where hermeticity needs it.
describe("ghexplore.config validate", function()
  local config = require("ghexplore.config")

  it("defaults validate clean", function()
    local ok, errs = config.validate(config.merge(nil))
    assert(ok, vim.inspect(errs))
  end)

  it("flags every bad key", function()
    local bad = config.merge({
      jobs = 0,
      clone_depth = -1,
      clone_args = { "--depth", 5 },
      data_dir = "",
      download_path = "",
      reuse = "yes",
      open_cmd = "",
      confirm_discard = "no",
      token = 42,
      keymaps = "x",
      picker = "bogus",
    })
    local ok, errs = config.validate(bad)
    assert(not ok)
    local joined = table.concat(errs, ";")
    for _, needle in ipairs({
      "jobs",
      "clone_depth",
      "clone_args",
      "data_dir",
      "download_path",
      "reuse",
      "open_cmd",
      "confirm_discard",
      "token",
      "keymaps",
      "picker",
    }) do
      assert(joined:find(needle, 1, true), "missing " .. needle .. " in " .. joined)
    end
  end)

  it("accepts missing data_dir under a writable parent", function()
    local tmp = vim.fn.tempname()
    local cfg = config.merge({ data_dir = tmp .. "/sub/dir" })
    local ok, errs = config.validate(cfg)
    -- /tmp is writable, so a missing nested data_dir is creatable, not an error
    assert(ok, vim.inspect(errs))
  end)

  it("rejects data_dir under a non-writable/nonexistent parent", function()
    local cfg = config.merge({ data_dir = "/proc/nope-xyz-ghexplore/sub" })
    local ok, errs = config.validate(cfg)
    assert(not ok)
    assert(table.concat(errs, ";"):find("data_dir", 1, true), vim.inspect(errs))
  end)

  it("rejects non-table config", function()
    local ok, errs = config.validate(nil)
    assert(not ok and #errs == 1)
  end)

  it("accepts function token and select picker", function()
    local cfg = config.merge({
      token = function()
        return nil
      end,
      picker = "select",
    })
    local ok, errs = config.validate(cfg)
    assert(ok, vim.inspect(errs))
  end)
end)

describe("ghexplore.health", function()
  local health = require("ghexplore.health")

  it("masks tokens abcd...wxyz style, never full", function()
    assert(health._mask_token("abcd1234wxyz") == "abcd…wxyz")
    assert(health._mask_token("short") == nil)
    assert(health._mask_token(nil) == nil)
    assert(health._mask_token("") == nil)
  end)

  it("check runs without network and reports sandboxes", function()
    local tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp, "p")
    require("ghexplore").setup({ data_dir = tmp .. "/data", jobs = 1, token = "health-token-123456" })
    local sandbox = require("ghexplore.sandbox")
    assert(sandbox.meta_write(sandbox.dir_for("h__e__main"), { last_opened = 1 }))
    -- capture health report calls
    local seen = {}
    local orig = {
      start = vim.health.start,
      ok = vim.health.ok,
      warn = vim.health.warn,
      error = vim.health.error,
      info = vim.health.info,
    }
    vim.health.start = function(name)
      seen[#seen + 1] = "start:" .. name
    end
    vim.health.ok = function(msg)
      seen[#seen + 1] = "ok:" .. msg
    end
    vim.health.warn = function(msg)
      seen[#seen + 1] = "warn:" .. msg
    end
    vim.health.error = function(msg)
      seen[#seen + 1] = "error:" .. msg
    end
    vim.health.info = function(msg)
      seen[#seen + 1] = "info:" .. msg
    end
    local ok, err = pcall(health.check)
    vim.health.start, vim.health.ok, vim.health.warn, vim.health.error, vim.health.info =
      orig.start, orig.ok, orig.warn, orig.error, orig.info
    assert(ok, tostring(err))
    local joined = table.concat(seen, "\n")
    assert(joined:find("start:ghexplore", 1, true), joined)
    assert(joined:find("config valid", 1, true), joined)
    -- sandbox count line
    assert(joined:find("sandbox", 1, true), joined)
    -- masked, never the full token
    assert(not joined:find("health%-token%-123456", 1, true), joined)
    assert(joined:find("heal…3456", 1, true) or joined:find("token present", 1, true), joined)
    assert(sandbox.discard("h__e__main", true))
  end)

  it("check warns (not errors) on invalid config", function()
    require("ghexplore").setup({ jobs = 0 })
    local warns = {}
    local orig_warn = vim.health.warn
    vim.health.warn = function(msg)
      warns[#warns + 1] = msg
    end
    local orig_err = vim.health.error
    local errs = {}
    vim.health.error = function(msg)
      errs[#errs + 1] = msg
    end
    pcall(health.check)
    vim.health.warn, vim.health.error = orig_warn, orig_err
    assert(#warns >= 1 and table.concat(warns, ";"):find("jobs", 1, true), vim.inspect(warns))
    require("ghexplore").setup({ jobs = 1 })
  end)
end)
