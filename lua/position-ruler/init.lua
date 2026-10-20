-- position-ruler.nvim
-- A character-position ruler for fixed-width text files
-- (txt / dat / lst / ctl / csv) and COBOL data files.
--
-- The ruler is drawn with extmarks (nvim_buf_set_extmark) above the first
-- visible line of the window, follows horizontal scrolling, and reports the
-- cursor position. Requires Neovim 0.10+.

local M = {}

local ns = vim.api.nvim_create_namespace("position-ruler")

local defaults = {
  enabled = true,
  -- Default filetypes. `.dat`, `.lst` and `.ctl` are mapped to `text` by the
  -- plugin spec; see README.
  filetypes = { "text", "csv" },
  -- Draw the ruler.
  ruler = true,
  -- Show `Line:… Col:… Pos:…` at the right end of the ruler row.
  show_position = true,
  -- Enable the vertical cursor line (crosshair) while the plugin is active.
  cursorcolumn = true,
  -- Files larger than this (bytes) skip the ruler to avoid frequent redraws.
  max_file_size = 100 * 1024 * 1024,
  -- Copy the result of :PositionRange to the system clipboard register.
  copy_to_clipboard = false,
}

local state = {
  saved_cursorcolumn = {},
  scheduled = {},
  setup_done = false,
}

local function normalize_win(win)
  if win == nil or win == 0 then
    return vim.api.nvim_get_current_win()
  end
  return win
end

local function get_option(name, win, default)
  local ok, value = pcall(vim.api.nvim_get_option_value, name, { win = win, scope = "local" })
  if ok and value ~= nil then
    return value
  end
  return default
end

local function is_supported(bufnr)
  if not M.config.enabled then
    return false
  end
  local ft = vim.bo[bufnr].filetype
  if ft == nil or ft == "" then
    return false
  end
  return vim.tbl_contains(M.config.filetypes, ft)
end

-- Large files: skip the ruler entirely so cursor movement stays cheap.
local function is_too_large(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == nil or name == "" then
    return false
  end
  local ok, size = pcall(vim.fn.getfsize, name)
  if not ok or type(size) ~= "number" or size <= 0 then
    return false
  end
  return size > M.config.max_file_size
end

local function is_active(bufnr)
  return is_supported(bufnr) and not is_too_large(bufnr)
end

-- Width of the text area (window width minus number/sign/fold gutters).
function M.text_width(win)
  local width = vim.api.nvim_win_get_width(win)
  local number = get_option("number", win, false)
  local relative = get_option("relativenumber", win, false)
  if number or relative then
    width = width - math.max(1, tonumber(get_option("numberwidth", win, 4)) or 4)
  end
  local signcolumn = tostring(get_option("signcolumn", win, "auto"))
  local sign = 0
  if signcolumn == "yes" then
    sign = 2
  elseif signcolumn == "auto" then
    sign = 1
  else
    sign = tonumber(signcolumn) or 0
  end
  local foldcolumn = get_option("foldcolumn", win, 0)
  local fold = tonumber(foldcolumn) or 0
  return math.max(1, width - sign - fold)
end

-- Build the two ruler rows for the visible columns [start_col, start_col+width-1].
-- Row 1 marks every tenth column, row 2 shows the ones digit of each column.
function M.build_ruler(start_col, width, position_text)
  start_col = math.max(1, start_col or 1)
  width = math.max(1, width or 1)

  local digits = {}
  for i = 0, width - 1 do
    local col = start_col + i
    digits[#digits + 1] = tostring(col % 10)
  end

  local cells = {}
  for _ = 1, width do
    cells[#cells + 1] = " "
  end

  local first = math.floor((start_col - 1) / 10) * 10
  local last = start_col + width
  for mark = first, last, 10 do
    if mark >= 10 then
      local text = tostring(mark)
      local start_index = mark - #text + 1 - start_col + 1
      for k = 1, #text do
        local index = start_index + k - 1
        if index >= 1 and index <= width then
          cells[index] = text:sub(k, k)
        end
      end
    end
  end

  local marker_row = table.concat(cells)
  if position_text ~= nil and #position_text > 0 and #position_text <= width then
    local start_index = width - #position_text + 1
    marker_row = marker_row:sub(1, start_index - 1) .. position_text
  end

  return marker_row, table.concat(digits)
end

function M.position_text(win)
  if not M.config.show_position then
    return nil
  end
  local cursor = vim.api.nvim_win_get_cursor(win)
  local line = cursor[1]
  local col = vim.fn.virtcol(".")
  local bufnr = vim.api.nvim_win_get_buf(win)
  local line_text = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1] or ""
  local pos = vim.fn.strcharlen(line_text) > 0 and math.min(col, vim.fn.strchars(line_text)) or col
  return string.format("Line:%d Col:%d Pos:%d", line, col, pos)
end

-- Draw (or clear) the ruler for `win`.
function M.render(win)
  win = normalize_win(win)
  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  local bufnr = vim.api.nvim_win_get_buf(win)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  if not M.config.ruler or not is_active(bufnr) then
    return
  end

  local view = vim.api.nvim_win_call(win, vim.fn.winsaveview)
  local leftcol = view.leftcol or 0
  local topline = view.topline or 1
  local width = M.text_width(win)

  local marker_row, digit_row = M.build_ruler(leftcol + 1, width, M.position_text(win))

  local row = math.max(0, topline - 1)
  local ok = pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, row, 0, {
    virt_lines = {
      { { marker_row, "PositionRulerNumber" } },
      { { digit_row, "PositionRulerTick" } },
    },
    virt_lines_above = true,
    priority = 10,
  })
  if not ok then
    return
  end
end

-- Coalesce repeated events into one render per tick; cheap for huge files.
local function schedule_render(win)
  if state.scheduled[win] then
    return
  end
  state.scheduled[win] = true
  vim.schedule(function()
    state.scheduled[win] = nil
    if vim.api.nvim_win_is_valid(win) then
      M.render(win)
    end
  end)
end

local function set_cursorcolumn(win, enable)
  if not M.config.cursorcolumn then
    return
  end
  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  if enable then
    if state.saved_cursorcolumn[win] == nil then
      state.saved_cursorcolumn[win] = get_option("cursorcolumn", win, false)
    end
    pcall(vim.api.nvim_set_option_value, "cursorcolumn", true, { win = win, scope = "local" })
  elseif state.saved_cursorcolumn[win] ~= nil then
    pcall(vim.api.nvim_set_option_value, "cursorcolumn", state.saved_cursorcolumn[win], { win = win, scope = "local" })
    state.saved_cursorcolumn[win] = nil
  end
end

-- Refresh the current window: ruler + crosshair, or clean up when inactive.
function M.refresh(win)
  win = normalize_win(win)
  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  local bufnr = vim.api.nvim_win_get_buf(win)
  if is_active(bufnr) then
    set_cursorcolumn(win, true)
    schedule_render(win)
  else
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    set_cursorcolumn(win, false)
  end
end

-- Jump so that column `col` is the cursor column and is visible.
function M.jump(col)
  col = tonumber(col)
  if col == nil or col < 1 then
    vim.notify("position-ruler: usage :PositionJump <column>", vim.log.levels.WARN)
    return false
  end
  local win = normalize_win(nil)
  local line = vim.api.nvim_win_get_cursor(win)[1]
  local bufnr = vim.api.nvim_win_get_buf(win)
  local line_text = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1] or ""
  -- nvim_win_set_cursor uses a 0-based byte column, so clamp on the index.
  local max_index = math.max(0, vim.fn.strchars(line_text) - 1)
  local target_index = math.min(math.floor(col) - 1, max_index)

  pcall(vim.api.nvim_win_set_cursor, win, { line, target_index })

  local target = target_index + 1
  local width = M.text_width(win)
  local leftcol = (vim.api.nvim_win_call(win, vim.fn.winsaveview)).leftcol or 0
  if target < leftcol + 1 or target > leftcol + width then
    local new_left = math.max(0, target - math.floor(width / 2))
    pcall(vim.fn.winrestview, { leftcol = new_left })
  end
  M.render(win)
  return true
end

-- Report the column span of the last visual selection: POSITION(12:16).
function M.range()
  local start_line = vim.fn.line("'<")
  local end_line = vim.fn.line("'>")
  if start_line == 0 or end_line == 0 then
    vim.notify("position-ruler: select a range in visual mode first", vim.log.levels.WARN)
    return nil
  end
  local start_col = vim.fn.virtcol("'<")
  local end_col = vim.fn.virtcol("'>")
  if end_col < start_col then
    start_col, end_col = end_col, start_col
  end

  local text
  if start_line == end_line then
    text = string.format("POSITION(%d:%d)", start_col, end_col)
  else
    text = string.format("POSITION(%d:%d-%d:%d)", start_line, start_col, end_line, end_col)
  end

  vim.api.nvim_echo({ { text, "None" } }, false, {})
  if M.config.copy_to_clipboard then
    pcall(vim.fn.setreg, "+", text)
  end
  return text
end

function M.enable()
  M.config.enabled = true
  M.refresh()
end

function M.disable()
  M.config.enabled = false
  local win = normalize_win(nil)
  local bufnr = vim.api.nvim_win_get_buf(win)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  set_cursorcolumn(win, false)
end

function M.toggle()
  if M.config.enabled then
    M.disable()
  else
    M.enable()
  end
  return M.config.enabled
end

local function setup_highlights()
  vim.api.nvim_set_hl(0, "PositionRulerNumber", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "PositionRulerTick", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "PositionRulerPosition", { link = "Special", default = true })
end

local function setup_commands()
  vim.api.nvim_create_user_command("PositionJump", function(args)
    M.jump(args.args)
  end, { nargs = "?", desc = "Jump to a character column" })

  vim.api.nvim_create_user_command("PositionRange", function()
    M.range()
  end, { range = true, desc = "Report the selected column span" })

  vim.api.nvim_create_user_command("PositionRulerToggle", function()
    M.toggle()
  end, { desc = "Toggle the position ruler" })

  vim.api.nvim_create_user_command("PositionRulerEnable", function()
    M.enable()
  end, { desc = "Enable the position ruler" })

  vim.api.nvim_create_user_command("PositionRulerDisable", function()
    M.disable()
  end, { desc = "Disable the position ruler" })
end

local function setup_autocmds()
  local group = vim.api.nvim_create_augroup("PositionRuler", { clear = true })
  local events = {
    "BufEnter",
    "WinEnter",
    "CursorMoved",
    "WinScrolled",
    "VimResized",
    "FileType",
  }
  vim.api.nvim_create_autocmd(events, {
    group = group,
    callback = function()
      M.refresh()
    end,
  })
  vim.api.nvim_create_autocmd("OptionSet", {
    group = group,
    pattern = { "number", "relativenumber", "signcolumn", "foldcolumn", "numberwidth" },
    callback = function()
      M.refresh()
    end,
  })
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), M.config or {}, opts or {})

  setup_highlights()
  setup_commands()
  if not state.setup_done then
    setup_autocmds()
    state.setup_done = true
  end
  M.refresh()
end

M.config = vim.deepcopy(defaults)
M.namespace = ns

return M
