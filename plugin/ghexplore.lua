-- Sourced automatically at startup when on 'runtimepath'. Keep tiny.
-- Canonical home of user commands (so they exist without setup()).
-- Lazy-require heavy modules inside callbacks; never at top level.
if vim.g.loaded_ghexplore then
  return
end
vim.g.loaded_ghexplore = 1

vim.api.nvim_create_user_command("Ghexplore", function(args)
  require("ghexplore").open(args.args)
end, { nargs = "?", desc = "Open a sandboxed GitHub repo" })

vim.api.nvim_create_user_command("GhexploreGrab", function(args)
  local file_url = args.fargs[1] or ""
  local dest = args.fargs[2]
  require("ghexplore").grab(file_url, dest)
end, { nargs = "*", desc = "Grab a single file without cloning", complete = "file" })

vim.api.nvim_create_user_command("GhexploreList", function()
  require("ghexplore").list()
end, { desc = "List sandboxes to resume" })

vim.api.nvim_create_user_command("GhexplorePreview", function(args)
  require("ghexplore").preview(args.args ~= "" and args.args or nil)
end, { nargs = "?", desc = "Preview a remote file without cloning" })

vim.api.nvim_create_user_command("GhexploreDiscard", function(args)
  require("ghexplore").discard(args.args, args.bang)
end, { nargs = "?", bang = true, desc = "Discard a sandbox" })

-- <Plug> maps let users remap without forcing keys (see :h lua-plugin).
vim.keymap.set("n", "<Plug>(GhexploreOpen)", function()
  require("ghexplore").open()
end, { desc = "Ghexplore: open" })
vim.keymap.set("n", "<Plug>(GhexploreGrab)", function()
  require("ghexplore").grab()
end, { desc = "Ghexplore: grab" })

-- Do NOT call require("ghexplore").setup() here. The user does that.
