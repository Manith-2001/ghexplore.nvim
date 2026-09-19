-- M1: url module tests. Requires plenary.test_harness or runs via headless asserts.
-- Covers GHGRAB_IMPLEMENTATION.md §4 fixtures + PLAN.md M1 acceptance.
describe("ghexplore.url", function()
  local url = require("ghexplore.url")

  it("detect_platform", function()
    assert(url.detect_platform("github.com", { "owner", "repo" }) == "github")
    assert(url.detect_platform("GitHub.com", { "owner", "repo" }) == "github")
    assert(url.detect_platform("gitlab.com", { "owner", "repo" }) == "gitlab")
    assert(url.detect_platform("codeberg.org", { "owner", "repo" }) == "gitea")
    -- self-hosted gitlab marker
    assert(url.detect_platform("git.example.com", { "owner", "repo", "-", "tree", "main" }) == "gitlab")
    assert(url.detect_platform("git.example.com", { "owner", "repo", "src" }) == "gitea")
  end)

  it("parse github tree/blob/root", function()
    local p = assert(url.parse("https://github.com/rust-lang/rust/tree/master/src/tools"))
    assert(p.platform == "github")
    assert(p.owner == "rust-lang" and p.repo == "rust")
    assert(p.branch == "master" and p.path == "src/tools" and p.kind == "tree")

    local p2 = assert(url.parse("https://github.com/owner/repo"))
    assert(p2.branch == "main" and p2.path == "" and p2.kind == "root")

    local p3 = assert(url.parse("https://github.com/owner/repo.git"))
    assert(p3.repo == "repo" and p3.branch == "main")

    local p4 = assert(url.parse("https://github.com/owner/repo/blob/main/README.md"))
    assert(p4.branch == "main" and p4.path == "README.md" and p4.kind == "blob")
    assert(url.is_file_url(p4) == true)
    assert(url.is_file_url(p) == false)

    local p5 = assert(url.parse("https://github.com/owner/repo/tree/main"))
    assert(p5.path == "" and p5.kind == "tree")

    local p6 = assert(url.parse("git@github.com:owner/repo.git"))
    assert(p6.host == "github.com" and p6.owner == "owner" and p6.repo == "repo")

    -- .git suffix stripped + owner/repo case preservation for display but host lower
    local p7 = assert(url.parse("https://GitHub.com/Owner/Repo.git"))
    assert(p7.host == "github.com")
  end)

  it("parse gitlab", function()
    local p = assert(url.parse("https://gitlab.com/user/repo/-/tree/develop/src/core"))
    assert(p.platform == "gitlab")
    assert(p.owner == "user" and p.repo == "repo")
    assert(p.branch == "develop" and p.path == "src/core" and p.kind == "tree")

    local p2 = assert(url.parse("https://gitlab.com/user/repo/-/blob/main/README.md"))
    assert(p2.kind == "blob" and p2.path == "README.md")

    local p3 = assert(url.parse("https://gitlab.example.com/user/repo/-/tree/main"))
    assert(p3.platform == "gitlab" and p3.branch == "main" and p3.path == "")
  end)

  it("parse gitea/codeberg", function()
    local p = assert(url.parse("https://codeberg.org/user/repo/src/branch/main/docs/guide"))
    assert(p.platform == "gitea")
    assert(p.owner == "user" and p.repo == "repo")
    assert(p.branch == "main" and p.path == "docs/guide")

    local p2 = assert(url.parse("https://codeberg.org/user/repo"))
    assert(p2.branch == "main" and p2.path == "" and p2.kind == "root")
  end)

  it("parse errors", function()
    local _, e1 = url.parse("not a url")
    assert(e1 and e1:find("not a url"))
    local _, e2 = url.parse("https://github.com/owner")
    assert(e2 and e2:find("owner and repository"))
    local _, e3 = url.parse("")
    assert(e3)
    local _, e4 = url.parse("   ")
    assert(e4)
  end)

  it("contents_api_url", function()
    local p = assert(url.parse("https://github.com/owner/repo/blob/main/src/a.lua"))
    assert(url.contents_api_url(p, nil) == "https://api.github.com/repos/owner/repo/contents/src/a.lua?ref=main")
    assert(url.contents_api_url(p, "docs") == "https://api.github.com/repos/owner/repo/contents/docs?ref=main")
    local bare = assert(url.parse("https://github.com/owner/repo"))
    assert(url.contents_api_url(bare, nil) == "https://api.github.com/repos/owner/repo/contents?ref=main")
    assert(url.contents_api_url(bare, "") == "https://api.github.com/repos/owner/repo/contents?ref=main")

    local gl = assert(url.parse("https://gitlab.com/user/repo/-/tree/develop/src/core"))
    local gl_api = url.contents_api_url(gl, nil)
    assert(gl_api:find("api/v4/projects/user%2Frepo/repository/tree", 1, true))
    assert(gl_api:find("ref=develop", 1, true))

    local cb = assert(url.parse("https://codeberg.org/user/repo/src/branch/main/docs/guide"))
    assert(url.contents_api_url(cb, nil) == "https://codeberg.org/api/v1/repos/user/repo/contents/docs/guide?ref=main")
  end)

  it("raw_file_url", function()
    local gh = assert(url.parse("https://github.com/owner/repo/tree/main"))
    assert(url.raw_file_url(gh, "src/a.lua") == "https://raw.githubusercontent.com/owner/repo/main/src/a.lua")
    assert(url.raw_file_url(gh, "/src/a.lua") == "https://raw.githubusercontent.com/owner/repo/main/src/a.lua")

    local gl = assert(url.parse("https://gitlab.com/user/repo/-/tree/develop/src"))
    assert(url.raw_file_url(gl, "src/core/foo.lua") == "https://gitlab.com/user/repo/-/raw/develop/src/core/foo.lua")

    local ga = assert(url.parse("https://codeberg.org/user/repo/src/branch/main/docs/guide.md"))
    assert(url.raw_file_url(ga, "docs/guide.md") == "https://codeberg.org/user/repo/raw/branch/main/docs/guide.md")
  end)

  it("sandbox_id", function()
    local p = assert(url.parse("https://github.com/owner/repo/tree/main"))
    assert(url.sandbox_id(p) == "owner__repo__main")
    local slash_branch = { owner = "o", repo = "r", branch = "feature/foo" }
    assert(url.sandbox_id(slash_branch) == "o__r__feature_foo")
    local special = { owner = "o", repo = "r", branch = "feat/bar-baz.v2" }
    assert(url.sandbox_id(special) == "o__r__feat_bar-baz.v2")
  end)

  it("ambiguous branch limitation documented", function()
    -- https://github.com/owner/repo/tree/feature/foo/src/core
    -- is ambiguous: ghgrab's ambiguous_ref_candidates would try both.
    -- Our M1 parser takes first segment as branch, remainder as path.
    local p = assert(url.parse("https://github.com/owner/repo/tree/feature/foo/src"))
    assert(p.branch == "feature" and p.path == "foo/src")
    -- This is the documented limitation; M3 branch fallback handles retry.
  end)
end)
