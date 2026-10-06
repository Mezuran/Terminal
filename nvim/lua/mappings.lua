require "nvchad.mappings"

-- add yours here

local map = vim.keymap.set

map("n", ";", ":", { desc = "CMD enter command mode" })
map("i", "jk", "<ESC>")
map("n", "<leader>uT", function()
  require("base46").toggle_theme()
end, { desc = "toggle Charm dark/light theme" })

-- map({ "n", "i", "v" }, "<C-s>", "<cmd> w <cr>")
