-- Charm-inspired palette based on the colors used on charm.land.
local M = {}

M.base_30 = {
  white = "#fffdf5",
  darker_black = "#17151c",
  black = "#201f26",
  black2 = "#292630",
  one_bg = "#302d3a",
  one_bg2 = "#3a3546",
  one_bg3 = "#484252",
  grey = "#625b6a",
  grey_fg = "#857d8e",
  grey_fg2 = "#9b93a3",
  light_grey = "#c4bdcc",
  red = "#ff6daa",
  baby_pink = "#ff84ff",
  pink = "#ff7bf5",
  line = "#3a3546",
  green = "#00ffb2",
  vibrant_green = "#ecfd65",
  blue = "#b5a3ff",
  nord_blue = "#9671ff",
  seablue = "#0adcd9",
  yellow = "#ecfd65",
  sun = "#e8fe96",
  purple = "#c89cff",
  dark_purple = "#6b50ff",
  teal = "#00d6a2",
  orange = "#ff9d76",
  cyan = "#0adcd9",
  statusline_bg = "#27232f",
  lightbg = "#302d3a",
  pmenu_bg = "#c89cff",
  folder_bg = "#9671ff",
}

M.base_16 = {
  base00 = "#201f26",
  base01 = "#292630",
  base02 = "#3a3546",
  base03 = "#625b6a",
  base04 = "#9b93a3",
  base05 = "#e6dfed",
  base06 = "#fffaf1",
  base07 = "#fffdf5",
  base08 = "#ff7bf5",
  base09 = "#ff9d76",
  base0A = "#ecfd65",
  base0B = "#00ffb2",
  base0C = "#0adcd9",
  base0D = "#9671ff",
  base0E = "#c89cff",
  base0F = "#ff6daa",
}

M.type = "dark"

return require("base46").override_theme(M, "charm_dark")
