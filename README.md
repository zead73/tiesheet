# TiePaper's sibling: TieSheet

A small, keyboard-first spreadsheet in the style of [TiePaper](https://github.com/zead73/tiepaper):
money, lists and schedules, no charts or pivot tables. For anything complicated, use LibreOffice.

**Status: the calculation engine only.** There is no screen yet. What exists and is tested
(558 checks, on Linux and under wine for Windows):

- exact decimal arithmetic (`0.1 + 0.2` is `0.3`, money adds up to the cent), 34 significant digits
- formulas in the usual syntax, with `$A$1`, ranges, `&`, `%`, error values and 47 functions:
  SUM AVERAGE MIN MAX COUNT COUNTA PRODUCT, ABS ROUND ROUNDUP ROUNDDOWN INT MOD POWER SQRT,
  IF AND OR NOT IFERROR, SUMIF COUNTIF AVERAGEIF, LEN LEFT RIGHT MID UPPER LOWER TRIM CONCAT VALUE,
  DATE YEAR MONTH DAY WEEKDAY TODAY DAYS EDATE, ISBLANK ISNUMBER ISTEXT ISERROR
- dates as serial numbers, the same as LibreOffice (serial 0 is 1899-12-30), shown as `2026-11-10`
- what typing means: `12.50`, `$1,234.50`, `5%`, `2026-11-10`, `(5)`, `'text` ...
- recalculation without recursion (a 20,000-row running balance is fine), loops show `#CIRC!`
- copying a formula shifts its relative references

Where the behaviour was in doubt it was checked against LibreOffice Calc (`tests/oracle/run.sh`).

```
tests/run-tests.sh        # engine tests
tests/run-tests.sh win    # the same, cross-compiled and run under wine
```

Source: `src/tsdec.pas` (decimals), `tsvalue.pas`, `tsdate.pas`, `tsformula.pas` (parser and functions),
`tssheet.pas` (cells, recalculation). MIT licence.
