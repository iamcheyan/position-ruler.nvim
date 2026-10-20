local ruler = require("position-ruler")

-- --- ruler rendering -------------------------------------------------------
local marker, digits = ruler.build_ruler(1, 40)
assert(digits == "1234567890123456789012345678901234567890", "digit row must repeat 1-9,0")
assert(marker:sub(9, 10) == "10", "tenth column marker must end at column 10")
assert(marker:sub(19, 20) == "20", "twentieth column marker must end at column 20")
assert(marker:sub(29, 30) == "30", "thirtieth column marker must end at column 30")
assert(marker:sub(39, 40) == "40", "fortieth column marker must end at column 40")
assert(#marker == 40 and #digits == 40, "ruler rows must match the requested width")

-- Horizontal scroll: the ruler follows leftcol.
local scrolled_marker, scrolled_digits = ruler.build_ruler(11, 20)
assert(scrolled_digits == "12345678901234567890", "scrolled digit row continues the sequence")
assert(scrolled_marker:sub(9, 10) == "20", "scrolled marker keeps absolute column numbers")

-- Position text is right aligned inside the ruler row.
local position_label = "Line:1 Col:2 Pos:2"
local with_position = select(1, ruler.build_ruler(1, 40, position_label))
assert(with_position:sub(-#position_label) == position_label, "position text must sit at the row end")
assert(#with_position == 40, "position text must not exceed the row width")

-- --- setup, jump and range -------------------------------------------------
ruler.setup({})

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ" })
vim.bo[buf].filetype = "text"
vim.api.nvim_set_current_buf(buf)

assert(vim.tbl_contains(ruler.config.filetypes, vim.bo[buf].filetype), "text must be supported by default")

-- The ruler is rendered in winbar; its text should be available there.
ruler.render()
assert(vim.wo.winbar:find("position%-ruler") ~= nil or vim.wo.winbar:find("render_winbar") ~= nil,
  "winbar must be configured for the ruler")
assert(ruler.render_winbar():find("PositionRulerNumber", 1, true) ~= nil,
  "ruler winbar must highlight tenth columns")

-- Crosshair column is enabled while the plugin is active.
ruler.refresh()
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
