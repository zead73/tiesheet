{ tests_sheet.inc - dates, formulas, typing, recalculation and shifting (included by test_engine.pas) }

{ ---- dates ---- }

procedure TestDates;
var
  s: Int64;
  y, m, d: Integer;
begin
  Check(SerialFromYMD(1899, 12, 30, s) and (s = 0), 'serial 0 is 1899-12-30 (LO)');
  Check(SerialFromYMD(2026, 11, 10, s) and (s = 46336), '2026-11-10 is 46336');
  YMDFromSerial(46336, y, m, d);
  Check((y = 2026) and (m = 11) and (d = 10), 'back to year, month, day');
  Check(SerialFromYMD(2026, 13, 1, s) and (s = 46388), 'DATE(2026,13,1) rolls into 2027 (LO)');
  Check(SerialFromYMD(2026, 2, 30, s) and (s = 46083), 'DATE(2026,2,30) is March 2 (LO)');
  Check(SerialFromYMD(2026, 0, 1, s) and (s = 45992), 'DATE(2026,0,1) is December 2025 (LO)');
  Check(SerialFromYMD(2026, 3, 0, s) and (SerialToIso(s) = '2026-02-28'), 'day 0 is the end of the month before');
  Check(not SerialFromYMD(0, 1, 1, s), 'year 0 is refused');
  Check(not SerialFromYMD(10000, 1, 1, s), 'year 10000 is refused');
  CheckEq(SerialToIso(0), '1899-12-30', 'iso of 0');
  CheckEq(SerialToIso(46336), '2026-11-10', 'iso of 46336');
  Check(ParseIsoDate('2026-11-10', s) and (s = 46336), 'parse iso');
  Check(not ParseIsoDate('2026-02-30', s), 'February 30 is not a date');
  Check(not ParseIsoDate('2026-1-1', s), 'iso needs two digits');
  Check(not ParseIsoDate('2026/11/10', s), 'iso needs dashes');
  Check(ParseIsoDate('2024-02-29', s), '2024 is a leap year');
  Check(not ParseIsoDate('2026-02-29', s), '2026 is not');
  Check(not ParseIsoDate('2100-02-29', s), '2100 is not');
  Check(ParseIsoDate('2000-02-29', s), '2000 is');
  CheckEq(IntToStr(WeekdaySunday0(46336)), '2', '2026-11-10 is a Tuesday');
  CheckEq(IntToStr(WeekdaySunday0(0)), '6', '1899-12-30 is a Saturday (LO)');
  CheckEq(IntToStr(WeekdaySunday0(1)), '0', 'serial 1 is a Sunday (LO)');
  SerialFromYMD(2026, 1, 1, s);
  Check(AddMonths(s, 1, s) and (SerialToIso(s) = '2026-02-01'), 'EDATE plain');
  SerialFromYMD(2026, 1, 31, s);
  Check(AddMonths(s, 1, s) and (SerialToIso(s) = '2026-02-28'), 'EDATE clamps the day (LO)');
  SerialFromYMD(2024, 2, 29, s);
  Check(AddMonths(s, 12, s) and (SerialToIso(s) = '2025-02-28'), 'a leap day a year on (LO)');
  SerialFromYMD(2026, 1, 31, s);
  Check(AddMonths(s, -2, s) and (SerialToIso(s) = '2025-11-30'), 'EDATE backwards (LO)');
end;

{ ---- formulas ---- }

var
  TestSheet: TSheet;

{ a sheet with the same little table the LibreOffice comparison used:
  F1:F5 = apple banana apple cherry 5, G1:G6 = 10 20 30 40 50 60 }
function MakeSheet: TSheet;
begin
  Result := TSheet.Create;
  Result.Today := 46336;
  Result.SetEntry(5, 0, 'apple');
  Result.SetEntry(5, 1, 'banana');
  Result.SetEntry(5, 2, 'apple');
  Result.SetEntry(5, 3, 'cherry');
  Result.SetEntry(5, 4, '5');
  Result.SetEntry(6, 0, '10');
  Result.SetEntry(6, 1, '20');
  Result.SetEntry(6, 2, '30');
  Result.SetEntry(6, 3, '40');
  Result.SetEntry(6, 4, '50');
  Result.SetEntry(6, 5, '60');
end;

procedure T(const formula, want: string);
var
  err: string;
begin
  err := TestSheet.SetEntry(0, 0, UnicodeString(formula));
  if err <> '' then
  begin
    Check(False, formula + ' was refused: ' + err);
    Exit;
  end;
  CheckEq(string(TestSheet.Display(0, 0)), want, formula);
end;

procedure TestFormulaSemantics;
begin
  TestSheet := MakeSheet;
  try
    { precedence and associativity; LO agrees on every line }
    T('=-2^2', '4');
    T('=2^-1', '0.5');
    T('=2^3^2', '64');
    T('=-2^-2', '0.25');
    T('=50%', '0.5');
    T('=5%*3', '0.15');
    T('=2*3%', '0.06');
    T('=10-2-3', '5');
    T('=2+3*4', '14');
    T('=(2+3)*4', '20');
    T('=1+2&3', '33');
    T('=2<3', 'TRUE');
    T('=1+1=2', 'TRUE');
    T('=7/2', '3.5');
    T('=-7/2', '-3.5');
    T('=10/4', '2.5');
    T('=1/3', '0.333333333333333');
    T('=2/3', '0.666666666666667');
    T('=1/3*3=1', 'TRUE');
    T('=0.1+0.2=0.3', 'TRUE');
    T('=0.1*3', '0.3');
    T('=100*1.1', '110');
    T('=1.5*2', '3');
    T('=1E3', '1000');
    T('=.5+.5', '1');
    T('=1/0', '#DIV/0!');
    T('=1/0+1', '#DIV/0!');
    T('=sum(1,2)', '3');
    T('=SUM(1;2)', '3');
    T('=  1  +  2  ', '3');

    { comparison: numbers sort before text; text ignores case; TRUE counts as 1 (LO) }
    T('=1="1"', 'FALSE');
    T('="a"="A"', 'TRUE');
    T('="a"<"B"', 'TRUE');
    T('="B">"a"', 'TRUE');
    T('=1<"a"', 'TRUE');
    T('="abc"<"abd"', 'TRUE');
    T('="10"<"9"', 'TRUE');
    T('=10<9', 'FALSE');
    T('=TRUE()=1', 'TRUE');
    T('=TRUE()>5', 'FALSE');
    T('=Z99=0', 'TRUE');
    T('=Z99=""', 'TRUE');
    T('=Z99+1', '1');
    T('=1=1', 'TRUE');
    T('=2<>2', 'FALSE');
    T('=3>=3', 'TRUE');
    T('=3<=2', 'FALSE');

    { text and numbers mixing }
    T('="5"+3', '8');
    T('=""+1', '#VALUE!');
    T('=-"3"', '-3');
    T('="a"+1', '#VALUE!');
    T('="a"&1&TRUE()', 'a1TRUE');
    T('=1&2', '12');
    T('="x"&1/3', 'x0.333333333333333');
    T('=CONCATENATE("a",1)', 'a1');
    T('=CONCAT("a","b","c")', 'abc');
    T('=LEFT("café",3)', 'caf');
    T('=LEN("café")', '4');
    T('=LEFT("hello")', 'h');
    T('=RIGHT("hello")', 'o');
    T('=RIGHT("hello",3)', 'llo');
    T('=LEFT("hi",10)', 'hi');
    T('=MID("hello",2,3)', 'ell');
    T('=MID("hello",0,3)', '#VALUE!');
    T('=MID("hello",9,3)', '');
    T('=UPPER("é")', 'É');
    T('=LOWER("ABC")', 'abc');
    T('=TRIM("  a   b  ")', 'a b');
    T('=VALUE("12")', '12');
    T('=VALUE("1x")', '#VALUE!');
    T('=LEN(12345)', '5');
    T('="He said ""hi"""', 'He said "hi"');

    { rounding }
    T('=ROUND(2.5,0)', '3');
    T('=ROUND(-2.5,0)', '-3');
    T('=ROUND(1.005,2)', '1.01');
    T('=ROUND(2.675,2)', '2.68');
    T('=ROUND(1234.567,-2)', '1200');
    T('=ROUND(0.5,0)', '1');
    T('=ROUNDUP(-2.1,0)', '-3');
    T('=ROUNDDOWN(-2.9,0)', '-2');
    T('=ROUND(1/3,2)', '0.33');
    T('=INT(-1.5)', '-2');
    T('=INT(7/2)', '3');
    T('=MOD(-3,2)', '1');
    T('=MOD(3,-2)', '-1');
    T('=MOD(10,3)', '1');
    T('=MOD(5.5,2)', '1.5');
    T('=MOD(1,0)', '#DIV/0!');
    T('=ABS(-3)', '3');
    T('=POWER(2,0.5)', '1.4142135623731');
    T('=POWER(0,0)', '1');
    T('=0^0', '1');
    T('=2^10', '1024');
    T('=SQRT(16)', '4');
    T('=SQRT(-1)', '#NUM!');
    T('=PRODUCT(2,3,4)', '24');

    { logic }
    T('=IF(0,1,2)', '2');
    T('=IF(1>2,"a")', 'FALSE');
    T('=IF(2>1,"yes","no")', 'yes');
    T('=IF(1,1,1/0)', '1');
    T('=IF(0,1/0,5)', '5');
    T('=IF("x",1,2)', '#VALUE!');
    T('=AND(1,0)', 'FALSE');
    T('=AND(1,1)', 'TRUE');
    T('=OR(0,0,1)', 'TRUE');
    T('=OR(0,0)', 'FALSE');
    T('=NOT(0)', 'TRUE');
    T('=IFERROR(1/0,"x")', 'x');
    T('=IFERROR(5,"x")', '5');
    T('=ISBLANK(Z99)', 'TRUE');
    T('=ISBLANK(G1)', 'FALSE');
    T('=ISNUMBER(G1)', 'TRUE');
    T('=ISNUMBER("5")', 'FALSE');
    T('=ISTEXT(F1)', 'TRUE');
    T('=ISERROR(1/0)', 'TRUE');
    T('=ISERROR(1)', 'FALSE');

    { aggregates over the table }
    T('=SUM(G1:G5)', '150');
    T('=SUM(F1:F5)', '5');
    T('=SUM(F1:F5,1)', '6');
    T('=SUM("5",3)', '8');
    T('=AVERAGE(G1:G5)', '30');
    T('=AVERAGE(F1:F4)', '#DIV/0!');
    T('=MIN(G1:G6)', '10');
    T('=MAX(G1:G6)', '60');
    T('=MIN(F1:F5)', '5');
    T('=MAX(H1:H3)', '0');
    T('=COUNT(F1:G5)', '6');
    T('=COUNTA(F1:G6)', '11');
    T('=SUM(G1:G6)/COUNT(G1:G6)', '35');
    T('=SUM(A1:A1)', '#CIRC!');
    T('=SUM(G6:G1)', '210');
    T('=SUM(G1:F1)', '10');

    { conditional }
    T('=SUMIF(F1:F5,"apple",G1:G5)', '40');
    T('=SUMIF(F1:F5,"=apple",G1:G5)', '40');
    T('=SUMIF(F1:F5,"APPLE",G1:G5)', '40');
    T('=SUMIF(G1:G5,">20")', '120');
    T('=SUMIF(F1:F5,"apple")', '0');
    T('=SUMIF(F1:F5,"a*",G1:G5)', '40');
    T('=COUNTIF(F1:F5,"a*")', '2');
    T('=COUNTIF(F1:F5,"apple")', '2');
    T('=COUNTIF(F1:F5,"<>apple")', '3');
    T('=COUNTIF(F1:F5,"?pple")', '2');
    T('=COUNTIF(G1:G5,40)', '1');
    T('=COUNTIF(G1:G5,">=40")', '2');
    T('=COUNTIF(G1:G5,"<>40")', '4');
    T('=COUNTIF(F1:F5,5)', '1');
    T('=AVERAGEIF(F1:F5,"apple",G1:G5)', '20');
    T('=AVERAGEIF(F1:F5,"zzz",G1:G5)', '#DIV/0!');

    { dates: a date function shows as a date until a number is made of it }
    T('=DATE(2026,11,10)', '2026-11-10');
    T('=DATE(2026,11,10)+30', '2026-12-10');
    T('=DATE(2026,11,10)-DATE(2026,1,1)', '313');
    T('=DATE(2026,11,10)-1', '2026-11-09');
    T('=DATE(2026,13,1)', '2027-01-01');
    T('=DATE(2026,2,30)', '2026-03-02');
    T('=DATE(26,1,1)', '2026-01-01');
    T('=DATE(99,1,1)', '1999-01-01');
    T('=YEAR(DATE(2026,11,10))', '2026');
    T('=MONTH(DATE(2026,11,10))', '11');
    T('=DAY(DATE(2026,11,10))', '10');
    T('=YEAR("2026-11-10")', '2026');
    T('=WEEKDAY(DATE(2026,11,10))', '3');
    T('=WEEKDAY(DATE(2026,11,10),2)', '2');
    T('=WEEKDAY(DATE(2026,11,15),2)', '7');
    T('=WEEKDAY(DATE(2026,11,15),3)', '6');
    T('=WEEKDAY(DATE(2026,11,10),9)', '#NUM!');
    T('=WEEKDAY(0)', '7');
    T('=WEEKDAY(1)', '1');
    T('=DAYS(DATE(2026,12,25),DATE(2026,11,10))', '45');
    T('=EDATE(DATE(2026,1,31),1)', '2026-02-28');
    T('=EDATE(DATE(2026,1,31),-2)', '2025-11-30');
    T('=EDATE(DATE(2024,2,29),12)', '2025-02-28');
    T('=TODAY()', '2026-11-10');
    T('=TODAY()+1', '2026-11-11');
    T('=TODAY()-DATE(2026,1,1)', '313');
    T('=DAY(TODAY())', '10');

    { names, errors }
    T('=nosuch(1)', '#NAME?');
    T('=foo', '#NAME?');
    T('=#REF!+1', '#REF!');
    T('=#DIV/0!', '#DIV/0!');
    T('=G1:G3', '#VALUE!');
    T('=TRUE', 'TRUE');
    T('=FALSE', 'FALSE');
    T('=true()', 'TRUE');
  finally
    TestSheet.Free;
  end;
end;

procedure TestFormulaRefusals;
var
  sh: TSheet;

  procedure Refused(const f: string);
  begin
    Check(sh.SetEntry(0, 0, UnicodeString(f)) <> '', f + ' should be refused');
    Check(not sh.Exists(0, 0), f + ' leaves the cell alone');
  end;

begin
  sh := TSheet.Create;
  try
    Refused('=1+');
    Refused('=(1');
    Refused('=1)');
    Refused('=SUM(');
    Refused('=SUM(1');
    Refused('=SUM(1,)');
    Refused('=SUM()');
    Refused('=IF(1)');
    Refused('=IF(1,2,3,4)');
    Refused('=NOT()');
    Refused('=1 2');
    Refused('=2x');
    Refused('="abc');
    Refused('=$');
    Refused('=@');
    Refused('=1,2');
    Refused('=*2');
    { a refusal keeps what was there }
    Check(sh.SetEntry(0, 0, '5') = '', 'put 5');
    Check(sh.SetEntry(0, 0, '=1+') <> '', 'bad formula over a good cell');
    CheckEq(string(sh.GetRaw(0, 0)), '5', 'the old cell survives a refused entry');
  finally
    sh.Free;
  end;
end;

{ ---- what typing means ---- }

procedure TestEntries;
var
  sh: TSheet;

  procedure E(const typed, shown: string; kind: TCellKind);
  begin
    Check(sh.SetEntry(0, 0, UnicodeString(typed)) = '', typed + ' accepted');
    CheckEq(string(sh.Display(0, 0)), shown, 'typing [' + typed + ']');
    Check(sh.GetKind(0, 0) = kind, 'kind of [' + typed + ']');
  end;

begin
  sh := TSheet.Create;
  try
    E('12', '12', ckNumber);
    E('12.50', '12.50', ckNumber);
    E('12.5', '12.5', ckNumber);
    E('007', '7', ckNumber);
    E('-5', '-5', ckNumber);
    E('+5', '5', ckNumber);
    E('0.05', '0.05', ckNumber);
    E('.5', '0.5', ckNumber);
    E('1,234.5', '1,234.5', ckNumber);
    E('1,234', '1,234', ckNumber);
    E('$12.50', '$12.50', ckNumber);
    E('$12', '$12.00', ckNumber);
    E('$1,234.5', '$1,234.50', ckNumber);
    E('-$5', '-$5.00', ckNumber);
    E('($1,234.50)', '-$1,234.50', ckNumber);
    E('(5)', '-5', ckNumber);
    E('5%', '5%', ckNumber);
    E('7.5%', '7.5%', ckNumber);
    E('100%', '100%', ckNumber);
    E('2026-11-10', '2026-11-10', ckNumber);
    E('TRUE', 'TRUE', ckBool);
    E('false', 'FALSE', ckBool);
    E('hello', 'hello', ckText);
    E('1,23', '1,23', ckText);
    E('12,34,567', '12,34,567', ckText);
    E('1.2.3', '1.2.3', ckText);
    E('12abc', '12abc', ckText);
    E('2026-13-45', '2026-13-45', ckText);
    E('$', '$', ckText);
    E('-', '-', ckText);
    E('%', '%', ckText);
    E('=', '=', ckText);
    E('''123', '123', ckText);
    E('''=1+1', '=1+1', ckText);
    E(' 12 ', '12', ckNumber);
    E('  x  ', '  x  ', ckText);
    E('=1+1', '2', ckFormula);
    CheckEq(string(sh.GetRaw(0, 0)), '=1+1', 'a formula is kept as typed');
    { values underneath }
    sh.SetEntry(0, 0, '5%');
    sh.SetEntry(1, 0, '=A1*200');
    CheckEq(string(sh.Display(1, 0)), '10', '5% is 0.05');
    sh.SetEntry(0, 0, '$1,234.50');
    sh.SetEntry(1, 0, '=A1+0.5');
    CheckEq(string(sh.Display(1, 0)), '1235', 'money is a plain number underneath');
    sh.SetEntry(0, 0, '=1/3');
    CheckEq(string(sh.Display(0, 0)), '0.333333333333333', 'a quotient shows 15 digits');
    Check(sh.GetFormat(0, 0).Kind = nfGeneral, 'a formula starts general');
    sh.SetEntry(0, 0, '');
    Check(not sh.Exists(0, 0), 'empty text clears the cell');
    CheckEq(string(sh.Display(0, 0)), '', 'a cleared cell shows nothing');
  finally
    sh.Free;
  end;
end;

procedure TestFormatting;
var
  fmt: TFormat;
begin
  fmt := GeneralFormat;
  CheckEq(string(FormatValue(VNum(D('1234.5')), fmt)), '1234.5', 'general');
  fmt.Kind := nfNumber; fmt.Decimals := 1; fmt.Thousands := True;
  CheckEq(string(FormatValue(VNum(D('1234567.25')), fmt)), '1,234,567.3', 'number with commas');
  fmt.Kind := nfCurrency; fmt.Decimals := 2; fmt.Thousands := True;
  CheckEq(string(FormatValue(VNum(D('-0.001')), fmt)), '$0.00', 'a tiny negative is not shown negative');
  CheckEq(string(FormatValue(VNum(D('-0.005')), fmt)), '-$0.01', 'half away from zero');
  CheckEq(string(FormatValue(VNum(D('1000')), fmt)), '$1,000.00', 'currency');
  fmt.Kind := nfPercent; fmt.Decimals := 1;
  CheckEq(string(FormatValue(VNum(D('0.075')), fmt)), '7.5%', 'percent');
  fmt.Kind := nfDate;
  CheckEq(string(FormatValue(VNum(D('46336')), fmt)), '2026-11-10', 'date');
  CheckEq(string(FormatValue(VNum(D('46336.9')), fmt)), '2026-11-10', 'a date drops the time');
  CheckEq(string(FormatValue(VErr(ecRef), fmt)), '#REF!', 'errors show as errors');
  CheckEq(string(FormatValue(VBool(True), fmt)), 'TRUE', 'booleans');
  CheckEq(string(FormatValue(VEmpty, fmt)), '', 'empty');
end;

{ ---- recalculation ---- }

procedure TestRecalc;
var
  sh: TSheet;
  i: Integer;
  t0: QWord;
begin
  sh := TSheet.Create;
  try
    sh.SetEntry(0, 0, '1');
    sh.SetEntry(1, 0, '=A1*2');
    sh.SetEntry(2, 0, '=B1+A1');
    CheckEq(string(sh.Display(2, 0)), '3', 'a chain');
    sh.SetEntry(0, 0, '10');
    CheckEq(string(sh.Display(1, 0)), '20', 'edit reaches B1');
    CheckEq(string(sh.Display(2, 0)), '30', 'edit reaches C1');
    { a formula above what it reads }
    sh.SetEntry(0, 5, '=A7+1');
    sh.SetEntry(0, 6, '=A8+1');
    sh.SetEntry(0, 7, '4');
    CheckEq(string(sh.Display(0, 5)), '6', 'reading downwards');
    { errors travel }
    sh.SetEntry(3, 0, '=1/0');
    sh.SetEntry(4, 0, '=D1+1');
    sh.SetEntry(5, 0, '=SUM(D1:E1)');
    CheckEq(string(sh.Display(4, 0)), '#DIV/0!', 'an error passes through +');
    CheckEq(string(sh.Display(5, 0)), '#DIV/0!', 'an error passes through SUM');
    sh.SetEntry(6, 0, '=IFERROR(D1,0)+1');
    CheckEq(string(sh.Display(6, 0)), '1', 'IFERROR catches it');
    sh.SetEntry(3, 0, '5');
    CheckEq(string(sh.Display(5, 0)), '11', 'and it clears when the cause is fixed');
    { a cell that is deleted }
    sh.ClearCell(0, 0);
    CheckEq(string(sh.Display(1, 0)), '0', 'a cleared cell reads as 0');
  finally
    sh.Free;
  end;

  { loops }
  sh := TSheet.Create;
  try
    sh.SetEntry(0, 0, '=B1');
    sh.SetEntry(1, 0, '=A1');
    CheckEq(string(sh.Display(0, 0)), '#CIRC!', 'a two-cell loop, first');
    CheckEq(string(sh.Display(1, 0)), '#CIRC!', 'a two-cell loop, second');
    sh.SetEntry(2, 0, '=A1+1');
    CheckEq(string(sh.Display(2, 0)), '#CIRC!', 'what reads a loop is an error too');
    sh.SetEntry(3, 0, '=D1');
    CheckEq(string(sh.Display(3, 0)), '#CIRC!', 'a cell that reads itself');
    sh.SetEntry(4, 0, '=SUM(E1:E3)');
    CheckEq(string(sh.Display(4, 0)), '#CIRC!', 'a sum that includes itself');
    sh.SetEntry(1, 0, '7');
    CheckEq(string(sh.Display(0, 0)), '7', 'breaking the loop clears it');
    CheckEq(string(sh.Display(2, 0)), '8', 'and what depended on it');
    sh.SetEntry(0, 3, '=B4');
    sh.SetEntry(1, 3, '=C4');
    sh.SetEntry(2, 3, '=A4');
    sh.SetEntry(3, 3, '=A4');
    CheckEq(string(sh.Display(3, 3)), '#CIRC!', 'a three-cell loop and a reader');
  finally
    sh.Free;
  end;

  { a long running balance: B2 = B1 + A2 for 20000 rows, no stack trouble in either direction }
  sh := TSheet.Create;
  try
    sh.SetEntry(1, 0, '100');
    for i := 2 to 20001 do
    begin
      sh.SetEntry(0, i - 1, '1');
      sh.SetEntry(1, i - 1, UnicodeString(Format('=B%d+A%d', [i - 1, i])));
    end;
    t0 := GetTickCount64;
    CheckEq(string(sh.Display(1, 20000)), '20100', 'a 20000-row running balance');
    Check(GetTickCount64 - t0 < 5000, 'and it is quick');
  finally
    sh.Free;
  end;
  sh := TSheet.Create;
  try
    { the chain points upwards: the first formula needs the last one }
    for i := 1 to 20000 do
      sh.SetEntry(0, i - 1, UnicodeString(Format('=A%d+1', [i + 1])));
    sh.SetEntry(0, 20000, '0');
    CheckEq(string(sh.Display(0, 0)), '20000', 'a 20000-row chain read from the top');
  finally
    sh.Free;
  end;
  { a column of sums over a big range }
  sh := TSheet.Create;
  try
    for i := 1 to 2000 do sh.SetEntry(0, i - 1, '2');
    for i := 1 to 200 do sh.SetEntry(1, i - 1, UnicodeString(Format('=SUM(A1:A%d)', [i * 10])));
    CheckEq(string(sh.Display(1, 199)), '4000', 'many sums over a column');
  finally
    sh.Free;
  end;
end;

{ ---- copying and shifting references ---- }

procedure TestShifting;
var
  res: UnicodeString;
  sh: TSheet;

  procedure S(const f: string; dc, dr: Integer; const want: string);
  begin
    Check(ShiftFormula(UnicodeString(f), dc, dr, res), f + ' shifts');
    CheckEq(string(res), want, f + ' by ' + IntToStr(dc) + ',' + IntToStr(dr));
  end;

begin
  S('=A1+B2', 1, 1, '=B2+C3');
  S('=$A$1+B2', 1, 1, '=$A$1+C3');
  S('=A$1+$B2', 1, 1, '=B$1+$B3');
  S('=SUM(A1:B2)', 0, 1, '=SUM(A2:B3)');
  S('=SUM($A1:B$2)', 2, 2, '=SUM($A3:D$2)');
  S('=SUM(A1:A9)/COUNT(A1:A9)', 1, 0, '=SUM(B1:B9)/COUNT(B1:B9)');
  S('=A1', -1, 0, '=#REF!');
  S('=A1', 0, -1, '=#REF!');
  S('=B2', -1, -1, '=A1');
  S('=SUM(A1:B2)', -1, 0, '=SUM(#REF!)');
  S('=IF(A1>0,"A1",B1)', 1, 0, '=IF(B1>0,"A1",C1)');
  S('=sum( a1 , b1 )', 1, 0, '=sum( B1 , C1 )');
  S('=1+2', 5, 5, '=1+2');
  S('=A1+#REF!', 1, 0, '=B1+#REF!');
  S('=XFD1', 1, 0, '=#REF!');
  S('=A1', 5, 0, '=F1');
  S('=A1+"B2"+B2', 0, 3, '=A4+"B2"+B5');
  S('=TODAY()', 3, 3, '=TODAY()');
  Check(not ShiftFormula('="abc', 1, 1, res), 'a formula that cannot be read is not shifted');
  CheckEq(ColName(0), 'A', 'column A');
  CheckEq(ColName(25), 'Z', 'column Z');
  CheckEq(ColName(26), 'AA', 'column AA');
  CheckEq(ColName(701), 'ZZ', 'column ZZ');
  CheckEq(ColName(702), 'AAA', 'column AAA');
  CheckEq(ColName(MAX_COL), 'XFD', 'last column');
  CheckEq(CellName(2, 9), 'C10', 'cell name');

  sh := TSheet.Create;
  try
    sh.SetEntry(0, 0, '=B1*2');
    sh.SetEntry(1, 0, '$5.00');
    CheckEq(sh.CopyCell(0, 0, 0, 1), '', 'copy a formula down');
    CheckEq(string(sh.GetRaw(0, 1)), '=B2*2', 'its references moved');
    CheckEq(sh.CopyCell(1, 0, 1, 1), '', 'copy a number');
    CheckEq(string(sh.Display(1, 1)), '$5.00', 'with its format');
    sh.SetEntry(1, 1, '3');
    CheckEq(string(sh.Display(0, 1)), '6', 'the copy works');
    CheckEq(sh.CopyCell(5, 5, 6, 6), '', 'copying an empty cell');
    Check(not sh.Exists(6, 6), 'clears the target');
    sh.SetEntry(3, 3, '=A1');
    sh.CopyCell(3, 3, 2, 3);
    CheckEq(string(sh.GetRaw(2, 3)), '=#REF!', 'a reference pushed off the sheet');
  finally
    sh.Free;
  end;
end;

{ ---- the cells that are in use ---- }

procedure TestExtent;
var
  sh: TSheet;
  c, r: Integer;
begin
  sh := TSheet.Create;
  try
    Check(not sh.Extent(c, r), 'an empty sheet has no extent');
    sh.SetEntry(3, 7, 'x');
    sh.SetEntry(1, 2, 'y');
    Check(sh.Extent(c, r) and (c = 3) and (r = 7), 'extent');
    CheckInt(sh.CellCount, 2, 'cell count');
    Check(sh.SetEntry(99999, 0, 'x') <> '', 'outside the sheet');
    Check(sh.SetEntry(0, 2000000, 'x') <> '', 'below the sheet');
  finally
    sh.Free;
  end;
end;

{ ---- dates typed month first ---- }

procedure TestUsDates;
var
  sh: TSheet;
  s: Int64;
  rows: TCsvRows;

  procedure U(const typed, shown: string);
  begin
    Check(sh.SetEntry(0, 0, UnicodeString(typed)) = '', typed + ' accepted');
    CheckEq(string(sh.Display(0, 0)), shown, 'typing [' + typed + ']');
    Check(sh.GetKind(0, 0) = ckNumber, typed + ' is a date, so a number');
    CheckEq(string(sh.GetRaw(0, 0)), shown, typed + ' is kept as ' + shown);
    Check(sh.GetFormat(0, 0).Kind = nfDate, typed + ' shows as a date');
  end;

  procedure Not_(const typed: string);
  begin
    Check(sh.SetEntry(0, 0, UnicodeString(typed)) = '', typed + ' accepted');
    Check(sh.GetKind(0, 0) = ckText, typed + ' is not a date');
    CheckEq(string(sh.GetRaw(0, 0)), typed, typed + ' stays as typed');
  end;

begin
  Check(ParseUsDate('8/1/2026', s) and (SerialToIso(s) = '2026-08-01'), 'month first: 8/1/2026 is August 1st');
  Check(not ParseUsDate('2026-08-01', s), 'ISO is not an American date');
  sh := TSheet.Create;
  try
    sh.Today := 46336;
    U('8/1/2026', '2026-08-01');
    U('08/01/2026', '2026-08-01');
    U('12/31/2026', '2026-12-31');
    U('1/1/2027', '2027-01-01');
    U('2/29/2024', '2024-02-29');
    U('8/1/26', '2026-08-01');
    U('8/1/29', '2029-08-01');
    U('8/1/30', '1930-08-01');
    U('8/1/99', '1999-08-01');
    U('8-1-2026', '2026-08-01');
    U(' 8/1/2026 ', '2026-08-01');
    Not_('2/29/2026');
    Not_('13/1/2026');
    Not_('0/1/2026');
    Not_('1/0/2026');
    Not_('1/32/2026');
    Not_('4/31/2026');
    Not_('1/2');
    Not_('1/2/3');
    Not_('1/2/20266');
    Not_('1/2/2026/4');
    Not_('1//2026');
    Not_('a/1/2026');
    Not_('8/1/2026x');
    Not_('555-12-34');
    { they are real dates: arithmetic, sorting, functions }
    sh.Clear;
    sh.SetEntry(0, 0, '8/1/2026');
    sh.SetEntry(0, 1, '9/1/2026');
    sh.SetEntry(1, 0, '=A2-A1');
    CheckEq(string(sh.Display(1, 0)), '31', 'two dates differ by a number of days');
    sh.SetEntry(1, 1, '=A1+30');
    CheckEq(string(sh.Display(1, 1)), '2026-08-31', 'and a date plus days is a date');
    sh.SetEntry(1, 2, '=MONTH(A2)');
    CheckEq(string(sh.Display(1, 2)), '9', 'the date functions read them');
    sh.SetEntry(1, 3, '=WEEKDAY(A1)');
    CheckEq(string(sh.Display(1, 3)), '7', 'August 1st 2026 is a Saturday');
    sh.SetEntry(1, 4, '=YEAR("12/25/2027")');
    CheckEq(string(sh.Display(1, 4)), '2027', 'also as text inside a function');
    sh.Clear;
    sh.SetEntry(0, 0, '1/1/2027');
    sh.SetEntry(0, 1, '8/1/2026');
    sh.SetEntry(0, 2, '11/1/2026');
    sh.SortRows(0, 0, 0, 2, 0, True);
    CheckEq(string(sh.Display(0, 0)) + ' ' + string(sh.Display(0, 1)) + ' ' + string(sh.Display(0, 2)), '2026-08-01 2026-11-01 2027-01-01',
      'sorting by date goes by the calendar (as text, 01/01/2027 would have come first)');
    { a file or a CSV with them in comes out with ISO dates }
    sh.Clear;
    ParseCsv('Date,Paid'#10'08/01/2026,1000'#10'9/1/26,500'#10, ',', rows);
    ImportCsv(sh, 'Date,Paid'#10'08/01/2026,1000'#10'9/1/26,500'#10, nil);
    CheckEq(string(sh.Display(0, 1)), '2026-08-01', 'a CSV date, month first');
    CheckEq(string(sh.Display(0, 2)), '2026-09-01', 'with a two-digit year');
    CheckEq(string(ExportCsv(sh, False)), 'Date,Paid'#10'2026-08-01,1000'#10'2026-09-01,500'#10, 'and it is written out as ISO');
    Check(SheetFromText(sh, 'tiesheet 1'#10'---'#10'Date,Paid'#10'08/01/2026,1000'#10, nil) = '', 'an older file with such dates in');
    CheckEq(string(sh.GetRaw(0, 1)), '2026-08-01', 'is read as dates and will be saved as ISO');
  finally
    sh.Free;
  end;
end;
