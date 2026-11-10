# TiePaper's sibling: TieSheet

A small, keyboard-first spreadsheet in the style of [TiePaper](https://github.com/zead73/tiepaper):
money, lists and schedules, no charts or pivot tables. For anything complicated, use LibreOffice.

**Status: it runs.** A character-cell screen like TiePaper's, driven from the keyboard (`docs/keys.md`, or F1).
Entering and editing cells, selecting, copy / cut / paste (with the system clipboard), fill down and right,
undo, column widths and formats, go to, find, loading and saving. Not built yet: sorting, inserting and
deleting rows and columns, printing (PDF), the icon and packaging.

The engine under it (767 checks, on Linux and under wine for Windows):

- exact decimal arithmetic (`0.1 + 0.2` is `0.3`, money adds up to the cent), 34 significant digits
- formulas in the usual syntax, with `$A$1`, ranges, `&`, `%`, error values and about 50 functions:
  SUM AVERAGE MIN MAX COUNT COUNTA PRODUCT, ABS ROUND ROUNDUP ROUNDDOWN INT MOD POWER SQRT,
  IF AND OR NOT IFERROR, SUMIF COUNTIF AVERAGEIF, LEN LEFT RIGHT MID UPPER LOWER TRIM CONCAT VALUE,
  DATE YEAR MONTH DAY WEEKDAY TODAY DAYS EDATE DATEDIF, ISBLANK ISNUMBER ISTEXT ISERROR
- dates as serial numbers, the same as LibreOffice (serial 0 is 1899-12-30), shown as `2026-11-10`
- what typing means: `12.50`, `$1,234.50`, `5%`, `2026-11-10`, `(5)`, `'text` ...
- recalculation without recursion (a 20,000-row running balance is fine), loops show `#CIRC!`
- copying a formula shifts its relative references
- CSV in and out. Reading handles quotes, line breaks inside quotes, CRLF, a BOM and Latin-1, and a
  `;` or tab delimiter. A field starting with `=` is a formula, so a CSV saved by LibreOffice with
  formulas comes back as it was. Writing gives either the formulas as typed, or only the results (for
  sharing, e.g. with Excel)
- the TieSheet file (`.tsh`): the cells as CSV plus a small header for column widths and cell formats
- saving keeps the old file as `.bak`

Where the behaviour was in doubt it was checked against LibreOffice Calc (`tests/oracle/run.sh`).

```
./build.sh                    # build/tiesheet (needs fpc 3.2.2 and SDL2, SDL2_ttf)
./build-windows.sh            # build/win/tiesheet.exe (then ./fetch-windows-dlls.sh)
tests/run-tests.sh [win]      # engine tests (the second: under wine)
tests/run-gui-tests.sh [win]  # the real program, driven by scripted keystrokes, headless
tiesheet --convert in.csv out.tsh [--values]   # convert without a window
```

Source: `src/tsdec.pas` (decimals), `tsvalue.pas`, `tsdate.pas`, `tsformula.pas` (parser and functions),
`tssheet.pas` (cells, recalculation), `tscsv.pas`, `tsfile.pas`, and the screen: `tsapp*.inc`, `tsgfx.pas`, `tssdl.pas`
(copied from TiePaper). MIT licence; the bundled font, Liberation Mono, keeps its own licence.
