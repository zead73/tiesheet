{ Headless tests for the spreadsheet engine.  Run with tests/run-tests.sh.
  Where a result was settled against LibreOffice Calc 26.2 it is marked "LO". }
program test_engine;

{$mode objfpc}{$H+}
{$codepage utf8}
{$IFDEF UNIX}{$DEFINE USECW}{$ENDIF}

uses
  {$IFDEF USECW}cwstring,{$ENDIF}
  {$IFDEF WINDOWS}Windows,{$ENDIF}
  SysUtils, Classes, tsdec, tsvalue, tsdate, tsformula, tssheet, tscsv, tsfile;

var
  Fails, Passes: Integer;

procedure Check(ok: Boolean; const msg: string);
begin
  if ok then Inc(Passes)
  else begin Inc(Fails); WriteLn('FAIL: ', msg); end;
end;

procedure CheckInt(got, want: Integer; const msg: string);
begin
  if got = want then Inc(Passes)
  else begin Inc(Fails); WriteLn('FAIL: ', msg, ' got ', got, ' want ', want); end;
end;

procedure CheckEq(const got, want: string; const msg: string);
begin
  if got = want then Inc(Passes)
  else begin Inc(Fails); WriteLn('FAIL: ', msg, #10'   got : [', got, ']'#10'   want: [', want, ']'); end;
end;

function D(const s: string): TDec;
begin
  if not DecFromStr(UnicodeString(s), Result) then raise Exception.Create('bad test number ' + s);
end;

{ ---- decimals ---- }

procedure TestDecimals;
var
  r: TDec;
  i: Int64;
begin
  CheckEq(DecToStr(D('0.1')), '0.1', 'parse and print');
  CheckEq(DecToStr(D('007.500')), '7.5', 'leading and trailing zeros go');
  CheckEq(DecToStr(D('-0')), '0', 'negative zero is zero');
  CheckEq(DecToStr(D('.5')), '0.5', 'no integer part');
  CheckEq(DecToStr(D('5.')), '5', 'no fraction');
  CheckEq(DecToStr(D('1e3')), '1000', 'exponent');
  CheckEq(DecToStr(D('1.5E-3')), '0.0015', 'negative exponent');
  CheckEq(DecToStr(D('+12')), '12', 'plus sign');
  Check(not DecFromStr('', r), 'empty is not a number');
  Check(not DecFromStr('.', r), 'a point alone is not a number');
  Check(not DecFromStr('1.2.3', r), 'two points');
  Check(not DecFromStr('12abc', r), 'trailing junk');
  Check(not DecFromStr('1e', r), 'empty exponent');
  Check(not DecFromStr(' 1', r), 'spaces are the caller''s business');

  CheckEq(DecToStr(DecAdd(D('0.1'), D('0.2'))), '0.3', '0.1 + 0.2');
  CheckEq(DecToStr(DecAdd(D('999.99'), D('0.01'))), '1000', 'carry across the point');
  CheckEq(DecToStr(DecAdd(D('5'), D('-7.25'))), '-2.25', 'mixed signs');
  CheckEq(DecToStr(DecSub(D('1'), D('0.9'))), '0.1', 'subtract');
  CheckEq(DecToStr(DecSub(D('2.5'), D('2.5'))), '0', 'equal numbers cancel');
  CheckEq(DecToStr(DecMul(D('0.1'), D('3'))), '0.3', '0.1 * 3');
  CheckEq(DecToStr(DecMul(D('-1.5'), D('-2'))), '3', 'negative times negative');
  CheckEq(DecToStr(DecMul(D('12.5'), D('0'))), '0', 'times zero');
  CheckEq(DecToStr(DecMul(D('100'), D('1.1'))), '110', '100 * 1.1');
  Check(DecDiv(D('10'), D('4'), r), 'divide');
  CheckEq(DecToStr(r), '2.5', '10 / 4');
  Check(DecDiv(D('-7'), D('2'), r), 'divide');
  CheckEq(DecToStr(r), '-3.5', '-7 / 2');
  Check(DecDiv(D('1'), D('3'), r), 'divide');
  CheckEq(DecToStr(r), '0.3333333333333333333333333333333333', '1/3 keeps 34 digits');
  Check(DecDiv(D('2'), D('3'), r), 'divide');
  CheckEq(DecToStr(r), '0.6666666666666666666666666666666667', '2/3 rounds the last digit');
  Check(DecDiv(D('0'), D('7'), r), 'zero divided');
  CheckEq(DecToStr(r), '0', '0 / 7');
  Check(not DecDiv(D('1'), D('0'), r), 'division by zero is refused');
  Check(DecDiv(D('6'), D('0.003'), r), 'divide');
  CheckEq(DecToStr(r), '2000', '6 / 0.003');
  Check(DecDiv(D('1000000'), D('0.000001'), r), 'divide');
  CheckEq(DecToStr(r), '1000000000000', 'a very small divisor');

  Check(DecCmp(D('0.30'), D('0.3')) = 0, 'compare equal');
  Check(DecCmp(D('-1'), D('1')) < 0, 'compare signs');
  Check(DecCmp(D('-2'), D('-1')) < 0, 'compare negatives');
  Check(DecCmp(D('10'), D('9.99')) > 0, 'compare lengths');
  { 1/3*3 is 0.999...9 exactly; the spreadsheets say it equals 1 (LO) }
  DecDiv(D('1'), D('3'), r);
  r := DecMul(r, D('3'));
  Check(DecCmp(r, D('1')) <> 0, '1/3*3 is not exactly 1');
  Check(DecCmpSpread(r, D('1')) = 0, '1/3*3 equals 1 to 15 digits (LO)');
  Check(DecCmpSpread(D('0.1234567890123456'), D('0.1234567890123457')) = 0, 'beyond 15 digits is equal');
  Check(DecCmpSpread(D('0.123456789012345'), D('0.123456789012346')) < 0, 'inside 15 digits differs');

  { rounding: half away from zero, exactly (LO) }
  CheckEq(DecToStr(DecRound(D('2.5'), 0, rmHalfAway)), '3', 'ROUND(2.5)');
  CheckEq(DecToStr(DecRound(D('-2.5'), 0, rmHalfAway)), '-3', 'ROUND(-2.5)');
  CheckEq(DecToStr(DecRound(D('1.005'), 2, rmHalfAway)), '1.01', 'ROUND(1.005,2) is exact');
  CheckEq(DecToStr(DecRound(D('2.675'), 2, rmHalfAway)), '2.68', 'ROUND(2.675,2) is exact');
  CheckEq(DecToStr(DecRound(D('1234.567'), -2, rmHalfAway)), '1200', 'ROUND(1234.567,-2)');
  CheckEq(DecToStr(DecRound(D('0.5'), 0, rmHalfAway)), '1', 'ROUND(0.5)');
  CheckEq(DecToStr(DecRound(D('0.4'), 0, rmHalfAway)), '0', 'ROUND(0.4)');
  CheckEq(DecToStr(DecRound(D('0.04'), 1, rmHalfAway)), '0', 'ROUND(0.04,1)');
  CheckEq(DecToStr(DecRound(D('999.995'), 2, rmHalfAway)), '1000', 'rounding carries');
  CheckEq(DecToStr(DecRound(D('1.5'), 5, rmHalfAway)), '1.5', 'more places than there are');
  CheckEq(DecToStr(DecRound(D('-2.1'), 0, rmAway)), '-3', 'ROUNDUP(-2.1) (LO)');
  CheckEq(DecToStr(DecRound(D('-2.9'), 0, rmToward)), '-2', 'ROUNDDOWN(-2.9) (LO)');
  CheckEq(DecToStr(DecRound(D('-1.5'), 0, rmFloor)), '-2', 'INT(-1.5) (LO)');
  CheckEq(DecToStr(DecRound(D('1.5'), 0, rmFloor)), '1', 'INT(1.5)');
  CheckEq(DecToStr(DecRound(D('-1.5'), 0, rmCeil)), '-1', 'ceiling');
  CheckEq(DecToStr(DecRound(D('7'), 0, rmFloor)), '7', 'a whole number stays');

  Check(DecMod(D('-3'), D('2'), r), 'mod');
  CheckEq(DecToStr(r), '1', 'MOD(-3,2) (LO)');
  Check(DecMod(D('3'), D('-2'), r), 'mod');
  CheckEq(DecToStr(r), '-1', 'MOD(3,-2) (LO)');
  Check(DecMod(D('5.5'), D('2'), r), 'mod');
  CheckEq(DecToStr(r), '1.5', 'MOD(5.5,2) (LO)');
  Check(DecMod(D('10'), D('3'), r), 'mod');
  CheckEq(DecToStr(r), '1', 'MOD(10,3)');
  Check(not DecMod(D('1'), D('0'), r), 'MOD by zero');

  Check(DecPow(D('2'), D('10'), r), 'power');
  CheckEq(DecToStr(r), '1024', '2^10');
  Check(DecPow(D('2'), D('-1'), r), 'power');
  CheckEq(DecToStr(r), '0.5', '2^-1');
  Check(DecPow(D('-2'), D('-2'), r), 'power');
  CheckEq(DecToStr(r), '0.25', '(-2)^-2');
  Check(DecPow(D('-2'), D('3'), r), 'power');
  CheckEq(DecToStr(r), '-8', '(-2)^3');
  Check(DecPow(D('0'), D('0'), r), 'power');
  CheckEq(DecToStr(r), '1', '0^0 is 1 (LO)');
  Check(not DecPow(D('0'), D('-1'), r), '0^-1');
  Check(not DecPow(D('-4'), D('0.5'), r), 'root of a negative');
  Check(DecPow(D('4'), D('0.5'), r), 'fractional power');
  CheckEq(DecToStr(r), '2', '4^0.5');
  Check(DecPow(D('1.1'), D('2'), r), 'power');
  CheckEq(DecToStr(r), '1.21', '1.1^2 is exact');
  Check(DecSqrt(D('2'), r), 'sqrt');
  CheckEq(DecToStr(r), '1.4142135623731', 'SQRT(2) to 15 digits (LO)');
  Check(not DecSqrt(D('-1'), r), 'sqrt of a negative');

  { the number of digits is capped }
  r := DecMul(D('12345678901234567890123456789'), D('98765432109876543210987654321'));
  CheckEq(Copy(DecToStr(r), 35, MaxInt), StringOfChar('0', Length(DecToStr(r)) - 34), 'a long product keeps 34 digits and its size');
  CheckEq(DecToStr(DecAdd(D('1e30'), D('1'))), '1000000000000000000000000000001', 'sums keep what fits');

  CheckEq(DecToFixed(D('1234.5'), 2, True), '1,234.50', 'fixed with commas');
  CheckEq(DecToFixed(D('-1234567.891'), 2, True), '-1,234,567.89', 'negative with commas');
  CheckEq(DecToFixed(D('0.005'), 2, False), '0.01', 'fixed rounds half away');
  CheckEq(DecToFixed(D('0.004'), 2, False), '0.00', 'fixed pads');
  CheckEq(DecToFixed(D('12'), 0, True), '12', 'no decimals');
  CheckEq(DecToFixed(D('999.999'), 2, True), '1,000.00', 'fixed carries into the thousands');
  CheckEq(DecToFixed(D('0'), 2, False), '0.00', 'zero');
  CheckEq(DecToFixed(D('-0.001'), 2, False), '0.00', 'a tiny negative shows no sign');

  Check(DecToInt64(D('42'), i) and (i = 42), 'to int');
  Check(DecToInt64(D('-7'), i) and (i = -7), 'to int, negative');
  Check(not DecToInt64(D('1.5'), i), 'a fraction is not an int');
  Check(DecFromDouble(0.1 + 0.2, r) and (DecToStr(r) = '0.3'), 'doubles come in at 15 digits');
  Check(Abs(DecToDouble(D('1.25')) - 1.25) < 1e-15, 'to double');
end;

{$I tests_sheet.inc}
{$I tests_files.inc}
{$I tests_structure.inc}

begin
  {$IFDEF WINDOWS}
  SetMultiByteConversionCodePage(CP_UTF8);
  SetMultiByteRTLFileSystemCodePage(CP_UTF8);
  DefaultSystemCodePage := CP_UTF8;
  {$ENDIF}
  TestDecimals;
  TestDates;
  TestFormulaSemantics;
  TestFormulaRefusals;
  TestEntries;
  TestFormatting;
  TestRecalc;
  TestShifting;
  TestExtent;
  TestDatedifOracle;
  TestCsvParsing;
  TestCsvSheet;
  TestNativeFile;
  TestFiles;
  TestInsertDelete;
  TestSort;
  WriteLn(Passes, ' passed, ', Fails, ' failed');
  if Fails > 0 then Halt(1);
end.
