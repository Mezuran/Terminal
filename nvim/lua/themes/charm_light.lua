-- Light counterpart to the Charm-inspired dark theme.
local M = {}

M.base_30 = {
  white = "#201f26",
  darker_black = "#f5edff",
  black = "#fffdf5",
  black2 = "#f5edff",
  one_bg = "#eee7f7",
  one_bg2 = "#e5dcee",
  one_bg3 = "#d9cee9",
  grey = "#bfbcc8",
  grey_fg = "#81798c",
  grey_fg2 = "#70697c",
  light_grey = "#575161",
  red = "#b42352",
  baby_pink = "#b43f91",
  pink = "#982d91",
  line = "#e5dcee",
  green = "#087a56",
  vibrant_green = "#657800",
  blue = "#5540c6",
  nord_blue = "#6b50ff",
  seablue = "#007c80",
  yellow = "#895c00",
  sun = "#9a6400",
  purple = "#7644ad",
  dark_purple = "#5939ac",
  teal = "#007f7e",
  orange = "#b95738",
  cyan = "#007c85",
  statusline_bg = "#f4eff9",
  lightbg = "#eee7f7",
  pmenu_bg = "#6b50ff",
  folder_bg = "#6b50ff",
}

M.base_16 = {
  base00 = "#fffdf5",
  base01 = "#f5edff",
  base02 = "#e5dcee",
  base03 = "#bfbcc8",
  base04 = "#81798c",
  base05 = "#332b3c",
  base06 = "#201f26",
  base07 = "#17151c",
  base08 = "#b42352",
  base09 = "#b95738",
  base0A = "#895c00",
  base0B = "#087a56",
  base0C = "#007c80",
  base0D = "#5540c6",
  base0E = "#7644ad",
  base0F = "#8f5039",
}

M.type = "light"

return require("base46").override_theme(M, "charm_light")
