-- M0 contract tests: module loads and exposes the M1 API surface.
-- Precedence tests land in M1.
describe("ghexplore.auth contract", function()
  it("loads", function()
    local auth = require("ghexplore.auth")
    assert(type(auth.resolve_token) == "function")
    assert(type(auth.auth_header) == "function")
  end)
end)
