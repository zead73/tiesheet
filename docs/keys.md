# TieSheet keys

TiePaper's keys are used wherever they mean something in a sheet. **Control commands:** hold Ctrl and
press the key, *or* tap and release Ctrl and then press the key (the status line shows `CTRL`). Capital
letters mean Ctrl+Shift. Press **F1** in the program for this list.

## Moving and selecting

| Keys | Action |
|------|--------|
| arrows | Move one cell |
| Ctrl+arrows | Jump to the edge of a block of cells |
| Home / End | First column / last used column |
| Ctrl+Home / Ctrl+End | Top left / the last used cell |
| PgUp / PgDn | A screen up / down |
| Ctrl+G | Go to a cell, e.g. `B12` |
| Ctrl+F / Ctrl+H | Find / hunt for the next one |
| Shift+arrows | Select cells |
| Ctrl+Space | Select the column |
| Alt+A | Select everything |
| Esc | Clear the selection |
| mouse | click, drag, double-click to edit, wheel scrolls, Ctrl+wheel zooms |

## Entering

| Keys | Action |
|------|--------|
| type | Replace what is in the cell |
| F2 | Edit what is in the cell |
| Enter / Tab | Finish and move down / right (with Shift: up / left); outside an entry they just move |
| Up / Down | Finish and move |
| Esc | Cancel the entry |
| Delete, Ctrl+E | Clear the selected cells |

## Copying, filling, undo

| Keys | Action |
|------|--------|
| Alt+C, Alt+X, Alt+V | Copy / cut / paste with the system clipboard (formulas copied inside TieSheet keep working, their references move) |
| Ctrl+Insert, Shift+Delete, Shift+Insert | The same three |
| Ctrl+D / Ctrl+R | Fill down / right from the first row / column of the selection (one cell: from the cell above / left) |
| Ctrl+Z / Ctrl+Shift+Z | Undo / redo |

## Layout, files

| Keys | Action |
|------|--------|
| Ctrl++ / Ctrl+- | Insert / delete the selected rows (after Ctrl+Space: the selected columns); formulas follow, and what pointed at a deleted row or column shows `#REF!` |
| F5 | Sort a block of rows by one column (asks which column, which way, and whether the first row is a heading); with one cell selected, the block around it |
| F3 | Column width |
| F4 | Format the selection: general, number, currency, percent, date (after Ctrl+Space, the whole column, also for numbers typed later) |
| Ctrl+L | Load a file (`.tsh` or `.csv`) |
| Ctrl+S / Ctrl+Shift+S | Save / save under another name |
| Ctrl+Shift+X | Quit |
| F1 | Help |

## Printing

| Keys | Action |
|------|--------|
| Ctrl+V | Print preview of the selected cells, or of the whole sheet (PgUp/PgDn page, arrows scroll, P switches Letter / A4, Esc closes) |
| Ctrl+O | Output: a PDF or a text file |

F9 (screen options) is kept as in TiePaper's F2 but is not built yet.
