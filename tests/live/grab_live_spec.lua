-- M6: live network suite. Runs ONLY in CI (GHEXPLORER_LIVE=1) or when
-- invoked manually with a token. Never selected by the CI step itself;
-- the file pattern below is excluded there via --ignore.
-- Local run: GHEXPLORER_LIVE=1 GITHUB_TOKEN=... nvim --headless -u ...
--   -c "lua require('plenary.test_harness').test_directory('tests/live', ...)"

local live = vim.env.GHEXPLORER_LIVE == "1"
if not live then
  describe("ghexplore.live (skipped: set GHEXPLORER_LIVE=1)", function()
    it("skipped without network gate", function()
      assert(true)
    end)
  end)
  return
end

describe("ghexplore.live grab", function()
  local grab = require("ghexplore.grab")

  it("grabs Hello-World README byte-identical to curl", function()
    local tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp, "p")
    local target = tmp .. "/README"
    local written, err = grab.grab("https://github.com/octocat/Hello-World/blob/master/README", target)
    assert(written, vim.inspect(err))
    local ref =
      vim.system({ "curl", "-sSL", "https://raw.githubusercontent.com/octocat/Hello-World/master/README" }):wait()
    assert(ref.code == 0, vim.inspect(ref))
    local f = assert(io.open(target, "rb"))
    local got = f:read("*a")
    f:close()
    assert(got == ref.stdout, "grab differs from curl reference")
  end)

  it("404 produces a friendly error, not a stacktrace", function()
    local tmp = vim.fn.tempname()
    local _, err = grab.grab("https://github.com/octocat/Hello-World/blob/master/NOPE-missing.txt", tmp)
    assert(err and err:find("NotFound", 1, true), vim.inspect(err))
  end)

  it("works with and without token (public repo)", function()
    require("ghexplore").setup({ jobs = 1, token = nil })
    local tmp = vim.fn.tempname()
    local written, err = grab.grab("https://github.com/octocat/Hello-World/blob/master/README", tmp)
    assert(written, vim.inspect(err))
  end)
end)

describe("ghexplore.live sandbox", function()
  local sandbox = require("ghexplore.sandbox")

  it("clones shallow and reuses offline", function()
    local tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp, "p")
    require("ghexplore").setup({ data_dir = tmp .. "/data", jobs = 1 })
    local dir, err = sandbox.clone("https://github.com/octocat/Hello-World", {})
    assert(dir, vim.inspect(err))
    assert(vim.uv.fs_stat(dir .. "/README") ~= nil)
    local meta = sandbox.meta_read(dir)
    assert(meta.branch and meta.branch ~= "", vim.inspect(meta))
    local ok, derr = sandbox.discard(sandbox.id_for("https://github.com/octocat/Hello-World") or "", true)
    assert(ok, vim.inspect(derr))
  end)
end)
