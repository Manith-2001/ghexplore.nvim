describe("ghexplore.auth", function()
  local auth = require("ghexplore.auth")

  it("auth_header", function()
    assert(auth.auth_header("tok", "github") == "token tok")
    assert(auth.auth_header("tok", "gitea") == "token tok")
    assert(auth.auth_header("tok", "gitlab") == "Bearer tok")
  end)

  it("_parse_gh_stdout dedupes and trims", function()
    assert(vim.deep_equal(auth._parse_gh_stdout(" tok1 \n tok1 \n tok2 \n\n"), { "tok1", "tok2" }))
    assert(vim.deep_equal(auth._parse_gh_stdout(""), {}))
    assert(vim.deep_equal(auth._parse_gh_stdout("  \n  \n"), {}))
  end)

  it("precedence: opts.token string wins", function()
    local tok = auth.resolve_token({ token = " explicit " })
    assert(tok == "explicit", "expected explicit, got " .. tostring(tok))
  end)

  it("precedence: opts.token function", function()
    local tok = auth.resolve_token({
      token = function()
        return " from-fn "
      end,
    })
    assert(tok == "from-fn")
  end)

  it("opts.token nil falls to env", function()
    local orig = vim.env.GHGRAB_GITHUB_TOKEN
    vim.env.GHGRAB_GITHUB_TOKEN = "env-token"
    vim.env.GITHUB_TOKEN = nil
    -- stub gh away so env wins without hitting gh
    local orig_exec = vim.fn.executable
    vim.fn.executable = function(_)
      return 0
    end
    local tok = auth.resolve_token({})
    vim.fn.executable = orig_exec
    vim.env.GHGRAB_GITHUB_TOKEN = orig
    assert(tok == "env-token")
  end)

  it("GHGRAB_GITHUB_TOKEN wins over GITHUB_TOKEN", function()
    local o1, o2 = vim.env.GHGRAB_GITHUB_TOKEN, vim.env.GITHUB_TOKEN
    vim.env.GHGRAB_GITHUB_TOKEN = "first"
    vim.env.GITHUB_TOKEN = "second"
    local orig_exec = vim.fn.executable
    vim.fn.executable = function(_)
      return 0
    end
    local tok = auth.resolve_token({})
    vim.fn.executable = orig_exec
    vim.env.GHGRAB_GITHUB_TOKEN, vim.env.GITHUB_TOKEN = o1, o2
    assert(tok == "first")
  end)

  it("auto/gh goes to gh when executable", function()
    local orig_exec = vim.fn.executable
    local orig_system = vim.system
    vim.fn.executable = function(cmd)
      return cmd == "gh" and 1 or 0
    end
    vim.system = function(args, opts)
      assert(args[1] == "gh")
      return {
        wait = function()
          return { code = 0, stdout = "gh-token\n", stderr = "" }
        end,
      }
    end
    local tok = auth.resolve_token({ token = "auto" })
    vim.fn.executable, vim.system = orig_exec, orig_system
    assert(tok == "gh-token")
  end)

  it("token never printed — grep sanity", function()
    -- Resolve should not notify. This is a smoke check that no vim.notify
    -- path leaked the token string. Actual leak grep is manual.
    local seen = {}
    local orig_notify = vim.notify
    vim.notify = function(msg, ...)
      seen[#seen + 1] = tostring(msg)
      return orig_notify(msg, ...)
    end
    local orig_exec = vim.fn.executable
    vim.fn.executable = function(_)
      return 0
    end
    local tok = auth.resolve_token({ token = "SUPERSECRET123" })
    vim.fn.executable = orig_exec
    vim.notify = orig_notify
    assert(tok == "SUPERSECRET123")
    for _, m in ipairs(seen) do
      assert(not m:find("SUPERSECRET"), "leaked token in notify: " .. m)
    end
  end)
end)
