# position-ruler.nvim

A character-position ruler for fixed-width text and COBOL data files, written in Lua for Neovim 0.10+.

It helps when you must know the exact byte/column position in fixed-length records: bank data files, `TXT`, `DAT`, `LST`, `CTL`, `CSV` exports, and COBOL data files.

## Features

1. **Ruler at the top of the window** — drawn above the first visible line:

   ```text
            10        20        30        40
   1234567890123456789012345678901234567890
   ```

2. **Follows horizontal scrolling** — the ruler always reflects the visible columns, so `leftcol` shifts are shown correctly.
4. **Live cursor position** — shows `Ln 34  Col 107  Pos 107` in the bottom statusline area.
5. **`:PositionRange`** — after a visual selection, reports the selected span, e.g. `POSITION(12:16)`.
6. **`:PositionJump 120`** — jumps straight to column 120 and scrolls it into view.
7. **Enabled by default for** `txt`, `dat`, `lst`, `ctl`, `csv`.
8. **Large-file safe** — files above `max_file_size` (default 100 MB) skip the ruler, and updates are coalesced per tick to avoid frequent redraws.
9. **Winbar rendered** — stays visible with the cursor on the first line; no buffer text is modified.
10. **Crosshair** — enables `cursorcolumn` while active, so the vertical line lines up with the ruler column; it is restored when you leave the buffer.

This is a single-line fixed-width file viewer, not a code-editor ruler.


## Installation (lazy.nvim)

```lua
{
  "iamcheyan/position-ruler.nvim",
  ft = { "text", "csv" },
  cmd = { "PositionJump", "PositionRange", "PositionRulerToggle" },
  opts = {},
  config = function(_, opts)
    require("position-ruler").setup(opts)
  end,
}
```

Map the data-file extensions to a filetype once, so the plugin activates for them:

```lua
vim.filetype.add({
  extension = {
    dat = "text",
    lst = "text",
    ctl = "text",
  },
})
```

`.txt` is already `text` and `.csv` is already `csv`.

## Commands

| Command | Description |
|---|---|
| `:PositionJump <col>` | Move the cursor to column `<col>` (scrolls it into view) |
| `:PositionRange` | Report the visual selection span: `POSITION(12:16)` |
| `:PositionRulerToggle` | Toggle the ruler |
| `:PositionRulerEnable` / `:PositionRulerDisable` | Enable / disable the ruler |

## Default options

```lua
{
  enabled = true,
  filetypes = { "text", "csv" },
  ruler = true,
  show_position = true,
  cursorcolumn = true,
  max_file_size = 100 * 1024 * 1024, -- bytes
  copy_to_clipboard = false,          -- copy :PositionRange output to + register
}
```

## Highlights

| Group | Default link | Used for |
|---|---|---|
| `PositionRulerTick` | `Comment` | Ordinary ruler cells |
| `PositionRulerNumber` | `Comment` | Real tenth-column labels |

All groups are created with `default = true`, so a colorscheme can override them.

## Notes

- The ruler width is the window width minus the number, sign and fold gutters; this is an approximation for `signcolumn=auto`.
- `:PositionRange` reports `POSITION(line:col-line:col)` when the selection spans multiple lines.

## Tests

```sh
bash scripts/test.sh
```
