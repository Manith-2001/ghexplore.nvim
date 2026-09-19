-- M0 contract tests: module loads and exposes the M1 API surface.
-- Real fixtures land in M1.
describe("ghexplore.url contract", function()
  it("loads", function()
    local url = require("ghexplore.url")
    assert(type(url.parse) == "function")
    assert(type(url.detect_platform) == "function")
    assert(type(url.contents_api_url) == "function")
    assert(type(url.raw_file_url) == "function")
    assert(type(url.is_file_url) == "function")
    assert(type(url.sandbox_id) == "function")
  end)
end)
