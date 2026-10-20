local ruler = require("position-ruler")

local marker = ruler.build_ruler(1, 40)
assert(marker == "1...+...10....+...20....+...30....+...40",
  "ruler must use dots, fifth-column ticks, and labels ending at real tenth columns")
local at_first = ruler.build_ruler(1, 10)
assert(at_first == "1...+...10", "the first ruler column must be marked at text column 1")
local at_tenth = ruler.build_ruler(10, 1)
assert(at_tenth == "0", "column 10 label must end exactly at text column 10")
local boundary = ruler.build_ruler(9, 2)
assert(boundary == "10", "column 10 label must span text columns 9 and 10")

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
vim.wo[win].number = true
vim.wo[win].relativenumber = true
vim.wo[win].signcolumn = "yes"
vim.wo[win].foldcolumn = "2"
ruler.refresh(win)
vim.wait(50)
local textoff = vim.fn.getwininfo(win)[1].textoff
local rendered = ruler.render_winbar()
local visible = rendered:gsub("%%#.-#", ""):gsub("%%[*]", "")
assert(#visible == vim.api.nvim_win_get_width(win), "ruler must include gutter padding and fill window width")
assert(visible:sub(1, textoff):match("^%s+$"), "gutter area must contain only alignment spaces")
assert(visible:sub(textoff + 1, textoff + 1) == "1", "first text column marker must align after gutters")
assert(visible:sub(textoff + 9, textoff + 10) == "10", "column 10 label must align after gutters")

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
