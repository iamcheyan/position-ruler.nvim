local ruler = require("position-ruler")

local marker = ruler.build_ruler(1, 40)
assert(marker == "....+...10....+...20....+...30....+...40",
  "ruler must use dots, fifth-column ticks, and labels ending at real tenth columns")
assert(#marker == 40, "ruler width must match the visible window width")

-- Labels remain absolute after horizontal scrolling.
local scrolled = ruler.build_ruler(101, 40)
assert(scrolled == "....+..110....+..120....+..130....+..140",
  "scrolled ruler must show real absolute columns")
-- --- setup, jump and range -------------------------------------------------
ruler.setup({})

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ" })
vim.bo[buf].filetype = "text"
vim.api.nvim_set_current_buf(buf)

assert(vim.tbl_contains(ruler.config.filetypes, vim.bo[buf].filetype), "text must be supported by default")

local win = vim.api.nvim_get_current_win()
ruler.render()
assert(vim.api.nvim_get_option_value("winbar", { win = win, scope = "local" }):find("render_winbar", 1, true),
  "winbar must be configured for the ruler")
assert(ruler.render_winbar():find("PositionRulerNumber", 1, true) ~= nil,
  "ruler winbar must highlight tenth columns")

assert(vim.api.nvim_get_option_value("statusline", { win = win, scope = "local" }):find("render_statusline", 1, true),
  "statusline must include the live position component")
assert(ruler.render_statusline():find("Ln 1  Col 1  Pos 1", 1, true), "statusline position format")
vim.api.nvim_win_set_cursor(win, { 1, 35 })
assert(ruler.render_statusline():find("Ln 1  Col 36  Pos 36", 1, true), "statusline position updates with cursor movement")
assert(vim.api.nvim_get_option_value("cursorcolumn", { win = vim.api.nvim_get_current_win(), scope = "local" }) == true,
  "cursorcolumn must be enabled for supported buffers")

-- Jump to a column inside the line.
ruler.jump(21)
local cursor = vim.api.nvim_win_get_cursor(0)
assert(cursor[2] == 20, "PositionJump should move the cursor to column 21 (0-based 20)")

-- Jump beyond the end of the line clamps to the last character.
ruler.jump(999)
local clamped = vim.api.nvim_win_get_cursor(0)
assert(clamped[2] == 35, "jump past end of line must clamp to the last character")

-- Visual selection span.
vim.api.nvim_win_set_cursor(0, { 1, 11 })
vim.cmd("normal! v")
vim.api.nvim_win_set_cursor(0, { 1, 15 })
vim.cmd("normal! \27")
local text = ruler.range()
assert(text == "POSITION(12:16)", "range must report POSITION(12:16), got " .. tostring(text))

-- Unsupported filetype: no ruler, no crosshair.
local other = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(other, 0, -1, false, { "plain" })
vim.bo[other].filetype = "lua"
vim.api.nvim_set_current_buf(other)
ruler.refresh()
assert(vim.api.nvim_get_option_value("cursorcolumn", { win = vim.api.nvim_get_current_win(), scope = "local" }) == false,
  "cursorcolumn must be restored for unsupported buffers")

print("position_ruler_spec: OK")
