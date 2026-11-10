{ tests_files.inc - DATEDIF against LibreOffice, CSV, and the TieSheet file (included by test_engine.pas) }

procedure TestDatedifOracle;
var
  sl: TStringList;
  i, p, n: Integer;
  line: string;
begin
  { tests/oracle/datedif.expected holds what LibreOffice answered for 120 formulas }
  sl := TStringList.Create;
  TestSheet := MakeSheet;
  try
    if not FileExists('tests/oracle/datedif.expected') then
    begin
      Check(False, 'tests/oracle/datedif.expected is missing (run the tests from the project folder)');
      Exit;
    end;
    sl.LoadFromFile('tests/oracle/datedif.expected');
    n := 0;
    for i := 0 to sl.Count - 1 do
    begin
      line := sl[i];
      p := Pos(#9, line);
      if p = 0 then Continue;
      T(Copy(line, 1, p - 1), Copy(line, p + 1, MaxInt));
      Inc(n);
    end;
    CheckInt(n, 120, 'every DATEDIF case was run');
    T('=DATEDIF("2023-10-27",DATE(2026,11,10),"y")', '3');
    T('=DATEDIF(DATE(2026,1,1),DATE(2026,2,1),"X")', '#NUM!');
    Check(TestSheet.SetEntry(1, 0, '=DATEDIF(DATE(2026,1,1),DATE(2026,2,1))') <> '', 'two arguments are refused');
  finally
    TestSheet.Free;
    sl.Free;
  end;
end;

procedure TestCsvParsing;
var
  rows: TCsvRows;
begin
  ParseCsv('a,b,c'#10'1,2,3', ',', rows);
  CheckInt(Length(rows), 2, 'two rows');
  CheckInt(Length(rows[0]), 3, 'three fields');
  CheckEq(string(rows[1][2]), '3', 'last field without a final newline');
  ParseCsv('"a,b","say ""hi""",x'#10, ',', rows);
  CheckInt(Length(rows), 1, 'a trailing newline adds no row');
  CheckEq(string(rows[0][0]), 'a,b', 'a quoted comma');
  CheckEq(string(rows[0][1]), 'say "hi"', 'doubled quotes');
  ParseCsv('"line1'#10'line2",z', ',', rows);
  CheckInt(Length(rows), 1, 'a newline inside quotes');
  CheckEq(string(rows[0][0]), 'line1'#10'line2', 'is kept in the field');
  ParseCsv('a,b'#13#10'c,d'#13#10, ',', rows);
  CheckInt(Length(rows), 2, 'CRLF line ends');
  CheckEq(string(rows[1][1]), 'd', 'no stray carriage return');
  ParseCsv('a'#10#10'b', ',', rows);
  CheckInt(Length(rows), 3, 'a blank line is a row');
  CheckInt(Length(rows[1]), 1, 'with one empty field');
  ParseCsv('a,,c,', ',', rows);
  CheckInt(Length(rows[0]), 4, 'empty fields count');
  CheckEq(string(rows[0][3]), '', 'including the last');
  ParseCsv('', ',', rows);
  CheckInt(Length(rows), 0, 'nothing in, nothing out');
  ParseCsv('ab"c,d', ',', rows);
  CheckEq(string(rows[0][0]), 'ab"c', 'a quote in the middle of a field is just a character');
  Check(DetectDelimiter('a,b,c'#10) = ',', 'comma');
  Check(DetectDelimiter('a;b;c'#10) = ';', 'semicolon');
  Check(DetectDelimiter('a'#9'b'#9'c'#10) = #9, 'tab');
  Check(DetectDelimiter('"a,b,c";d'#10) = ';', 'commas inside quotes do not count');
  Check(DetectDelimiter('hello'#10) = ',', 'no delimiter at all');
  CheckEq(string(CsvField('plain', ',')), 'plain', 'a plain field is not quoted');
  CheckEq(string(CsvField('a,b', ',')), '"a,b"', 'a comma is quoted');
  CheckEq(string(CsvField('say "hi"', ',')), '"say ""hi"""', 'quotes are doubled');
  CheckEq(string(CsvField('a'#10'b', ',')), '"a'#10'b"', 'a newline is quoted');
  CheckEq(string(CsvField('=TODAY() - A2', ',')), '=TODAY() - A2', 'a formula without commas is not quoted');
  CheckEq(string(DecodeText(#$EF#$BB#$BF'abc')), 'abc', 'the byte order mark goes');
  CheckEq(string(DecodeText(#$C3#$A9)), UTF8Encode(UnicodeString(#$E9)), 'UTF-8 is read as UTF-8');
  CheckEq(string(UTF8Encode(DecodeText('caf'#$E9))), 'caf'#$C3#$A9, 'anything else is Latin-1');
end;

procedure TestCsvSheet;
var
  sh: TSheet;
  text, again: UnicodeString;
  warn: TStringList;
  n: Integer;
begin
  { the structure of the user's real file: formulas kept as text, ISO dates, DATEDIF }
  Check(ReadTextFile('tests/fixtures/schedule.csv', text) = '', 'read the fixture');
  sh := TSheet.Create;
  warn := TStringList.Create;
  try
    sh.Today := 46336;
    n := ImportCsv(sh, text, warn);
    CheckInt(n, 19, 'nineteen cells');
    CheckInt(warn.Count, 0, 'no warnings');
    CheckEq(string(sh.Display(0, 0)), 'Date', 'header');
    CheckEq(string(sh.Display(0, 1)), '2023-10-27', 'a date shows as typed');
    CheckEq(string(sh.Display(4, 1)), '1110', 'TODAY() - A2 is a number of days (LO says 1110)');
    CheckEq(string(sh.Display(5, 1)), '3 Years, 0 Months, 14 Days', 'the long form (LO says the same)');
    CheckEq(string(sh.GetRaw(4, 1)), '=TODAY() - A2', 'the formula text is kept exactly');
    sh.Today := 46336 + 20;
    sh.Invalidate;
    CheckEq(string(sh.Display(4, 1)), '1130', 'another day, another answer');
    { it writes out the same text it read }
    again := ExportCsv(sh, False);
    CheckEq(string(again), string(text), 'export gives back the file');
    { for sharing: results instead of formulas }
    sh.Today := 46336;
    sh.Invalidate;
    again := ExportCsv(sh, True);
    CheckEq(string(again), 'Date,Name,Out,In,Total Days,Long form'#10 +
      '2023-10-27,Alex,Start,Finish,1110,"3 Years, 0 Months, 14 Days"'#10 +
      '2026-11-10,Sam,Job,,,'#10 + '2026-11-11,Parade,All,None,,'#10, 'values only');
  finally
    warn.Free;
    sh.Free;
  end;

  { odds and ends of import }
  sh := TSheet.Create;
  warn := TStringList.Create;
  try
    ImportCsv(sh, '007,-012,0,0.5,"1,234.50",$12.50,5%,(5),=1+,=SUM(A1:A3),"=IF(1>0,""yes"",""no"")"'#10, warn);
    CheckEq(string(sh.Display(0, 0)), '007', 'leading zeros stay (a code)');
    Check(sh.GetKind(0, 0) = ckText, 'as text');
    CheckEq(string(sh.Display(1, 0)), '-012', 'also with a sign');
    Check(sh.GetKind(2, 0) = ckNumber, '0 is a number');
    Check(sh.GetKind(3, 0) = ckNumber, '0.5 is a number');
    CheckEq(string(sh.Display(4, 0)), '1,234.50', 'a quoted number with a comma');
    CheckEq(string(sh.Display(5, 0)), '$12.50', 'money');
    CheckEq(string(sh.Display(6, 0)), '5%', 'a percentage');
    CheckEq(string(sh.Display(7, 0)), '-5', 'a bracketed number');
    CheckEq(string(sh.Display(8, 0)), '=1+', 'a formula that cannot be read stays text');
    CheckInt(warn.Count, 1, 'and is reported');
    Check(Pos('I1', warn[0]) = 1, 'with its cell name');
    CheckEq(string(sh.Display(9, 0)), '0', 'a sum over text and numbers');
    CheckEq(string(sh.Display(10, 0)), 'yes', 'a formula with quoted commas');
    CheckEq(string(ExportCsv(sh, False)), '''007,''-012,0,0.5,"1,234.50",$12.50,5%,(5),''=1+,=SUM(A1:A3),"=IF(1>0,""yes"",""no"")"'#10,
      'the typed forms go back out (the apostrophe marks text that looks like something else)');
  finally
    warn.Free;
    sh.Free;
  end;
  sh := TSheet.Create;
  try
    CheckEq(string(ExportCsv(sh, False)), '', 'an empty sheet exports nothing');
    sh.SetEntry(2, 2, 'x');
    CheckEq(string(ExportCsv(sh, False)), ',,'#10',,'#10',,x'#10, 'blank rows and columns are kept');
  finally
    sh.Free;
  end;
end;

procedure TestNativeFile;
var
  sh, sh2: TSheet;
  text: UnicodeString;
  warn: TStringList;
  f: TFormat;
  want: string;
begin
  sh := TSheet.Create;
  sh2 := TSheet.Create;
  warn := TStringList.Create;
  try
    sh.SetEntry(0, 0, 'Item');
    sh.SetEntry(1, 0, 'Price');
    sh.SetEntry(0, 1, 'Rent');
    sh.SetEntry(1, 1, '1200');
    sh.SetEntry(0, 2, 'Food');
    sh.SetEntry(1, 2, '300');
    sh.SetEntry(1, 3, '=SUM(B2:B3)');
    f.Kind := nfCurrency; f.Decimals := 2; f.Thousands := True;
    sh.SetFormat(1, 1, f);
    sh.SetFormat(1, 2, f);
    sh.SetFormat(1, 3, f);
    sh.SetColWidth(0, 20);
    sh.SetColWidth(1, 14);
    sh.SetColWidth(2, DEFAULT_COL_WIDTH);
    text := SheetToText(sh);
    want := 'tiesheet 1'#10'width A 20'#10'width B 14'#10'format B2:B4 currency 2 1'#10'---'#10 +
      'Item,Price'#10'Rent,1200'#10'Food,300'#10',=SUM(B2:B3)'#10;
    CheckEq(string(text), want, 'the file text');
    CheckEq(SheetFromText(sh2, text, warn), '', 'read it back');
    CheckEq(string(sh2.Display(1, 3)), '$1,500.00', 'the formula and its format');
    CheckEq(string(sh2.Display(1, 1)), '$1,200.00', 'a format that typing would not give');
    CheckInt(sh2.ColWidth(0), 20, 'a width');
    CheckInt(sh2.ColWidth(1), 14, 'another');
    CheckInt(sh2.ColWidth(2), DEFAULT_COL_WIDTH, 'the default');
    CheckEq(string(SheetToText(sh2)), want, 'writing it again gives the same text');
    { a number typed as money needs no format line }
    sh.Clear;
    sh.SetEntry(0, 0, '$5.00');
    sh.SetEntry(0, 1, '2026-11-10');
    CheckEq(string(SheetToText(sh)), 'tiesheet 1'#10'---'#10'$5.00'#10'2026-11-10'#10, 'what typing gives is not repeated');
    { what typing gave must come back as it was, whatever it looks like to a CSV reader }
    sh.Clear;
    sh.SetEntry(0, 0, '007');
    sh.SetEntry(0, 1, '-012');
    sh.SetEntry(0, 2, 'Note; see below');
    sh.SetEntry(0, 3, 'a'#9'b');
    sh.SetEntry(0, 4, '''007');
    sh.SetEntry(0, 5, '=A1+1');
    text := SheetToText(sh);
    CheckEq(SheetFromText(sh2, text, warn), '', 'read back the awkward cells');
    CheckEq(string(sh2.Display(0, 0)), '7', '007 was typed as a number and stays one');
    Check(sh2.GetKind(0, 0) = ckNumber, 'still a number');
    CheckEq(string(sh2.Display(0, 1)), '-12', '-012 too');
    CheckEq(string(sh2.Display(0, 2)), 'Note; see below', 'a semicolon in the first cell does not change the delimiter');
    CheckEq(string(sh2.Display(0, 3)), 'a'#9'b', 'nor does a tab');
    CheckEq(string(sh2.Display(0, 4)), '007', 'text typed with an apostrophe stays text');
    CheckEq(string(sh2.Display(0, 5)), '8', 'and the formula reads the number');
    CheckEq(string(SheetToText(sh2)), string(text), 'and the file is stable');
    sh.Clear;
    sh.SetEntry(0, 0, 'Note; see below');
    CheckEq(SheetFromText(sh2, SheetToText(sh), warn), '', 'a one-column sheet');
    CheckEq(string(sh2.Display(0, 0)), 'Note; see below', 'is not split');
    { a column with its own format: typing into it gives the format, and the file says it once }
    sh.Clear;
    f.Kind := nfCurrency; f.Decimals := 2; f.Thousands := True;
    sh.SetColFormat(1, f);
    sh.SetEntry(0, 0, 'Price');
    sh.SetEntry(1, 0, 'Amount');
    sh.SetEntry(1, 1, '1200');
    sh.SetEntry(1, 2, '=B2*2');
    sh.SetEntry(1, 3, '5%');
    sh.SetEntry(1, 4, 'text');
    CheckEq(string(sh.Display(1, 1)), '$1,200.00', 'a number typed into a currency column');
    CheckEq(string(sh.Display(1, 2)), '$2,400.00', 'a formula too');
    CheckEq(string(sh.Display(1, 3)), '5%', 'a percentage keeps what typing gave it');
    text := SheetToText(sh);
    CheckEq(string(text), 'tiesheet 1'#10'colformat B currency 2 1'#10'---'#10'Price,Amount'#10',1200'#10',=B2*2'#10',5%'#10',text'#10 + '', 'one colformat line, no per-cell lines');
    CheckEq(SheetFromText(sh2, text, warn), '', 'read back');
    CheckEq(string(sh2.Display(1, 1)), '$1,200.00', 'the column format is back');
    CheckEq(string(sh2.Display(1, 3)), '5%', 'and the percentage');
    sh2.SetEntry(1, 5, '7');
    CheckEq(string(sh2.Display(1, 5)), '$7.00', 'and it still applies to what is typed next');
    { not ours, and newer }
    Check(SheetFromText(sh2, 'hello', nil) <> '', 'not a TieSheet file');
    Check(SheetFromText(sh2, 'tiesheet 1'#10'a,b'#10, nil) <> '', 'no --- line');
    Check(Pos('newer', SheetFromText(sh2, 'tiesheet 9'#10'---'#10, nil)) > 0, 'a newer version');
    warn.Clear;
    CheckEq(SheetFromText(sh2, 'tiesheet 1'#10'something new 1 2 3'#10'width A 30'#10'---'#10'x'#10, warn), '', 'unknown lines are skipped');
    CheckInt(warn.Count, 1, 'and noted');
    CheckInt(sh2.ColWidth(0), 30, 'known lines still count');
    CheckEq(SheetFromText(sh2, 'tiesheet 1'#13#10'---'#13#10'a,b'#13#10, nil), '', 'CRLF line ends');
    CheckEq(string(sh2.Display(1, 0)), 'b', 'and the body reads');
  finally
    warn.Free;
    sh2.Free;
    sh.Free;
  end;
end;

procedure TestFiles;
var
  sh, sh2: TSheet;
  text: UnicodeString;
  fn: string;
  sl: TStringList;
begin
  fn := 'build/test/native_test.tsh';
  if FileExists(fn) then DeleteFile(fn);
  if FileExists(fn + '.bak') then DeleteFile(fn + '.bak');
  sh := TSheet.Create;
  sh2 := TSheet.Create;
  sl := TStringList.Create;
  try
    sh.SetEntry(0, 0, 'first');
    CheckEq(SaveSheetFile(sh, fn), '', 'save');
    Check(not FileExists(fn + '.bak'), 'nothing to keep the first time');
    sh.SetEntry(0, 0, 'second');
    CheckEq(SaveSheetFile(sh, fn), '', 'save again');
    Check(FileExists(fn + '.bak'), 'the old file is kept as .bak');
    CheckEq(ReadTextFile(fn + '.bak', text), '', 'read the .bak');
    Check(Pos('first', string(text)) > 0, 'it holds the first version');
    CheckEq(LoadSheetFile(sh2, fn, nil), '', 'load');
    CheckEq(string(sh2.Display(0, 0)), 'second', 'the second version is in the file');
    Check(not FileExists(fn + '.tmp'), 'no temporary file is left');
    Check(LoadSheetFile(sh2, 'build/test/no_such_file.tsh', nil) <> '', 'a missing file is reported');
    { text with accents survives the round trip }
    sh.SetEntry(0, 1, 'café ☕');
    SaveSheetFile(sh, fn);
    LoadSheetFile(sh2, fn, nil);
    CheckEq(string(sh2.Display(0, 1)), 'café ☕', 'non-ASCII text');
  finally
    sl.Free;
    sh2.Free;
    sh.Free;
    if FileExists(fn) then DeleteFile(fn);
    if FileExists(fn + '.bak') then DeleteFile(fn + '.bak');
  end;
end;
