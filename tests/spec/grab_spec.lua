-- M2 + M6: gh header parsing + error taxonomy are pure (no network).
-- Live network assertions live in grab_live_spec.lua, gated on opts.env
-- (plenary runs each file in its own nvim with cwd = repo root).
describe("ghexplore.gh headers", function()
  local gh = require("ghexplore.gh")

  it("parses status from last response (redirects)", function()
    local head = "HTTP/1.1 301 Moved\r\nlocation: x\r\n\r\nHTTP/2 200 \r\ncontent-type: y\r\n"
    local status, _ = gh._parse_headers(head)
    assert(status == 200)
  end)

  it("reads rate-limit remaining case-insensitively", function()
    local head = "HTTP/1.1 403 Forbidden\r\nX-RateLimit-Remaining: 0\r\n"
    local status, rem = gh._parse_headers(head)
    assert(status == 403 and rem == "0")
    local head2 = "HTTP/2 403 \r\nx-ratelimit-remaining: 12\r\n"
    local _, rem2 = gh._parse_headers(head2)
    assert(rem2 == "12")
  end)

  it("header value: token vs Bearer", function()
    assert(gh._header_value("t", "https://api.github.com/x") == "token t")
    assert(gh._header_value("t", "https://gitlab.com/api/v4/x") == "Bearer t")
  end)
end)

-- M2: grab target-path resolution (pure: no network, no writes).
describe("ghexplore.grab target_path", function()
  local grab = require("ghexplore.grab")

  it("dir target joins basename", function()
    local target, err = grab.target_path("https://github.com/owner/repo/blob/main/README.md", "/tmp")
    assert(err == nil, tostring(err))
    assert(target == "/tmp/README.md")
  end)

  it("rejects tree urls", function()
    local target, err = grab.target_path("https://github.com/owner/repo/tree/main/src", "/tmp")
    assert(target == nil)
    assert(err and err:find("not a file url"))
  end)

  it("rejects invalid urls", function()
    local target, err = grab.target_path("not a url", "/tmp")
    assert(target == nil and err)
  end)

  it("bare filename anchors under download_path", function()
    local cfg = require("ghexplore").config
    local target = assert(grab.target_path("https://github.com/owner/repo/blob/main/a/b.lua", "out.lua"))
    assert(target == vim.fn.expand(cfg.download_path) .. "/out.lua")
  end)
end)
