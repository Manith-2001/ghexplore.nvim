-- M3: sandbox lifecycle tests. No network: local `git init` fixtures only.
describe("ghexplore.sandbox local", function()
  local sandbox = require("ghexplore.sandbox")

  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp, "p")
  require("ghexplore").setup({ data_dir = tmp .. "/data", jobs = 1 })

  it("id_for delegates to url.sandbox_id", function()
    local id, err = sandbox.id_for("https://github.com/owner/repo/tree/main")
    assert(err == nil, tostring(err))
    assert(id == "owner__repo__main", tostring(id))
  end)

  it("rejects invalid urls", function()
    local id, err = sandbox.id_for("not a url")
    assert(id == nil and err)
  end)

  it("meta roundtrip + list sorted by last_opened", function()
    local root = sandbox.root()
    assert(root == vim.fn.expand(tmp .. "/data") .. "/sandboxes" or root:find("sandboxes", 1, true))
    local d1 = sandbox.dir_for("a__b__main")
    local d2 = sandbox.dir_for("c__d__main")
    assert(sandbox.meta_write(d1, { last_opened = 10 }))
    assert(sandbox.meta_write(d2, { last_opened = 20 }))
    assert(sandbox.meta_read(d1).last_opened == 10)
    local items = sandbox.list()
    assert(#items >= 2)
    -- newest first: c__d__main before a__b__main
    local pos = {}
    for i, it in ipairs(items) do
      pos[it.id] = i
    end
    assert(pos["c__d__main"] < pos["a__b__main"])
    assert(sandbox.discard("a__b__main", true))
    assert(sandbox.discard("c__d__main", true))
  end)

  it("redacts tokens in errors", function()
    local red = sandbox._redact("https://secret123@github.com/o/r.git failed")
    assert(not red:find("secret123", 1, true), red)
    assert(red:find("***@", 1, true), red)
  end)

  it("discard refuses outside root + missing", function()
    local ok, err = sandbox.discard("/tmp", true)
    assert(ok == false and err:find("refusing", 1, true), vim.inspect(err))
    local ok2, err2 = sandbox.discard("nope__nope__main", true)
    assert(ok2 == false and err2:find("no such sandbox", 1, true), vim.inspect(err2))
  end)

  it("clones a local fixture and reuses offline", function()
    local fixture = tmp .. "/fixture-repo"
    vim.fn.mkdir(fixture, "p")
    assert(vim.system({ "git", "init", "-b", "main", fixture }):wait().code == 0)
    assert(vim.system({ "git", "-C", fixture, "config", "user.email", "t@t" }):wait().code == 0)
    assert(vim.system({ "git", "-C", fixture, "config", "user.name", "t" }):wait().code == 0)
    local f = assert(io.open(fixture .. "/hello.txt", "w"))
    f:write("hi")
    f:close()
    assert(vim.system({ "git", "-C", fixture, "add", "." }):wait().code == 0)
    assert(vim.system({ "git", "-C", fixture, "commit", "-m", "init" }):wait().code == 0)

    local dir, err = sandbox.clone("https://github.com/fixture/owner", { clone_src = fixture, branch = "main" })
    assert(dir, vim.inspect(err))
    assert(vim.uv.fs_stat(dir .. "/hello.txt") ~= nil)
    local meta = sandbox.meta_read(dir)
    assert(meta.branch == "main" and meta.last_opened and meta.last_opened > 0)

    -- reuse: offline reopen bumps last_opened without network
    local before = meta.last_opened
    os.execute("sleep 1")
    local dir2, err2 = sandbox.open("https://github.com/fixture/owner", {})
    assert(dir2 == dir, vim.inspect(err2))
    assert(sandbox.meta_read(dir).last_opened >= before)

    -- edit_target honors subpaths, falls back to dir
    assert(sandbox.edit_target(dir, "https://github.com/fixture/owner/tree/main") == dir)
    -- root of fixture has no subdir "nope", so falls back
    assert(sandbox.edit_target(dir, "https://github.com/fixture/owner/tree/main/nope") == dir)

    assert(sandbox.discard("fixture__owner__main", true))
    assert(vim.uv.fs_stat(dir) == nil)
  end)
end)
