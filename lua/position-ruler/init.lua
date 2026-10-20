-- position-ruler.nvim
-- A character-position ruler for fixed-width text files
-- (txt / dat / lst / ctl / csv) and COBOL data files.
--
-- The ruler uses the window winbar so it stays visible when the cursor is on
-- the first line. Neovim does not render virt_lines above line 1. It follows
-- horizontal scrolling and reports the cursor position. Requires Neovim 0.10+.

local M = {}

local ns = vim.api.nvim_create_namespace("position-ruler")
local winbar_token = "%{%v:lua.require'position-ruler'.render_winbar()%}"

local defaults = {
  enabled = true,
  -- Default filetypes. `.dat`, `.lst` and `.ctl` are mapped to `text` by the
  -- plugin spec; see README.
  filetypes = { "text", "csv" },
  -- Draw the single-row fixed-width ruler in the window winbar.
  ruler = true,
  -- Show the cursor location in the bottom statusline using StatusLine colors.
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
  saved_winhighlight = {},
  scheduled = {},
  saved_winbar = {},
  saved_statusline = {},
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

local function set_option(name, value, win)
  pcall(vim.api.nvim_set_option_value, name, value, { win = win, scope = "local" })
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

-- Width of the actual text area, excluding every screen gutter reported by Neovim.
function M.text_width(win)
  local info = vim.fn.getwininfo(win)[1]
  local width = vim.api.nvim_win_get_width(win)
  local textoff = info and tonumber(info.textoff) or 0
  return math.max(1, width - textoff)
end

-- Build a fixed-column ruler: dots at ordinary columns, '+' every fifth
-- column, and the real column number ending exactly at each tenth column.
function M.build_ruler(start_col, width)
  start_col = math.max(1, start_col or 1)
  width = math.max(1, width or 1)
  local cells = {}
  for i = 0, width - 1 do
    local col = start_col + i
    cells[i + 1] = (col % 5 == 0) and "+" or "."
  end
  if start_col == 1 then
    cells[1] = "1"
  end
  for col = math.ceil(start_col / 10) * 10, start_col + width - 1, 10 do
    local label = tostring(col)
    local first_col = col - #label + 1
    for offset = 0, #label - 1 do
      local target_col = first_col + offset
      if target_col >= start_col and target_col < start_col + width then
        cells[target_col - start_col + 1] = label:sub(offset + 1, offset + 1)
      end
    end
  end
  return table.concat(cells)
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
  return string.format("Ln %d  Col %d  Pos %d", line, col, pos)
end

function M.render_winbar()
  local win = vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_win_get_buf(win)
  if not M.config.ruler or not is_active(bufnr) then
    return ""
  end

  local info = vim.fn.getwininfo(win)[1]
  local textoff = info and tonumber(info.textoff) or 0
  local view = vim.api.nvim_win_call(win, vim.fn.winsaveview)
  -- Neovim hides the first text cell beneath textoff columns. Keep logical
  -- fixed-file column 1 aligned to that first visible text cell.
  local start_col = (view.leftcol or 0) + 1
  local width = math.max(1, vim.api.nvim_win_get_width(win) - textoff)
  local text = M.build_ruler(start_col, width)
  local parts = { string.rep(" ", textoff) }
  local current_hl
  for i = 1, #text do
    local col = start_col + i - 1
    local hl = (col % 10 == 0) and "%#PositionRulerNumber#" or "%#PositionRulerTick#"
    if hl ~= current_hl then
      parts[#parts + 1] = hl
      current_hl = hl
    end
    parts[#parts + 1] = text:sub(i, i)
  end
  parts[#parts + 1] = "%*"
  return table.concat(parts)
end

local function statusline_token()
  return "%{%v:lua.require'position-ruler'.render_statusline()%}"
end

function M.render_statusline()
  local win = vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_win_get_buf(win)
  if not M.config.show_position or not is_active(bufnr) then
    return ""
  end
  return "%#StatusLine#" .. M.position_text(win) .. "%*"
end

local function set_ruler_winbar(win, active)
  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  if active then
    if state.saved_winbar[win] == nil then
      state.saved_winbar[win] = get_option("winbar", win, "")
    end
    -- Keep a user's existing winbar intact. The normal Neovim config has an
    -- empty winbar on text/csv buffers, while Heirline owns other filetypes.
    local current = get_option("winbar", win, "")
    if current == "" or current == winbar_token then
      set_option("winbar", winbar_token, win)
    end
  elseif state.saved_winbar[win] ~= nil then
    local current = get_option("winbar", win, "")
    if current == winbar_token then
      set_option("winbar", state.saved_winbar[win] or "", win)
    end
    state.saved_winbar[win] = nil
  end
end

local function set_position_statusline(win, active)
  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  if active and M.config.show_position then
    if state.saved_statusline[win] == nil then
      state.saved_statusline[win] = get_option("statusline", win, "")
    end
    local current = get_option("statusline", win, "")
    if current == "" or current:find("render_statusline", 1, true) then
      set_option("statusline", "%=" .. statusline_token(), win)
    elseif not current:find(statusline_token(), 1, true) then
      set_option("statusline", current .. "%=" .. statusline_token(), win)
    end
  elseif state.saved_statusline[win] ~= nil then
    local current = get_option("statusline", win, "")
    if current:find(statusline_token(), 1, true) then
      set_option("statusline", state.saved_statusline[win] or "", win)
    end
    state.saved_statusline[win] = nil
  end
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
  local active = M.config.ruler and is_active(bufnr)
  set_ruler_winbar(win, active)
  set_position_statusline(win, active)
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
  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  if enable then
    if M.config.cursorcolumn and state.saved_cursorcolumn[win] == nil then
      state.saved_cursorcolumn[win] = get_option("cursorcolumn", win, false)
    end
    if M.config.cursorcolumn then
      set_option("cursorcolumn", true, win)
    end
    if state.saved_winhighlight[win] == nil then
      state.saved_winhighlight[win] = get_option("winhighlight", win, "")
    end
    local current = get_option("winhighlight", win, "")
    local mappings = {}
    for entry in current:gmatch("[^,]+") do
      local key, value = entry:match("^([^:]+):(.+)$")
      if key ~= "CursorColumn" and key ~= "CursorLine" then
        mappings[#mappings + 1] = entry
      end
    end
    mappings[#mappings + 1] = "CursorColumn:CursorLine"
    set_option("winhighlight", table.concat(mappings, ","), win)
  else
    if state.saved_cursorcolumn[win] ~= nil then
      set_option("cursorcolumn", state.saved_cursorcolumn[win], win)
      state.saved_cursorcolumn[win] = nil
    end
    if state.saved_winhighlight[win] ~= nil then
      set_option("winhighlight", state.saved_winhighlight[win], win)
      state.saved_winhighlight[win] = nil
    end
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
  set_ruler_winbar(win, false)
  set_position_statusline(win, false)
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
