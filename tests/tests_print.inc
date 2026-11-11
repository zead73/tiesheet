{ tests_print.inc - pages, PDF and text output (included by test_engine.pas) }

procedure TestPrint;
var
  sh: TSheet;
  job: TPrintJob;
  pdf, txt: string;
  i, p, off: Integer;
  fn: string;
  sl: TStringList;
  lc, lr: Integer;
begin
  sh := TSheet.Create;
  try
    { a small sheet: portrait, one page }
    sh.SetEntry(0, 0, 'Rent');
    sh.SetEntry(1, 0, '1200');
    sh.SetEntry(0, 1, 'A long description that runs on');
    sh.SetEntry(0, 2, 'A long description that runs on over');
    sh.SetEntry(2, 2, 'x');
    sh.SetEntry(0, 3, 'Total');
    sh.SetEntry(1, 3, '=SUM(B1:B2)');
    sh.Extent(lc, lr);
    BuildPrint(sh, 0, 0, 2, lr, 'My sheet', psLetter, job);
    Check(not job.Landscape, 'three narrow columns go on a portrait page');
    CheckInt(job.PointSize, 10, 'at 10 point');
    CheckInt(job.CharsPerLine, 84, 'a Letter page holds 84 characters at 10 point');
    CheckInt(job.BodyLines, 53, 'and 53 lines of sheet');
    CheckInt(Length(job.Pages), 1, 'one page');
    CheckEq(string(job.Pages[0].Header), 'My sheet', 'the title');
    CheckEq(string(job.Pages[0].Footer), 'Page 1 of 1', 'the page number');
    CheckInt(Length(job.Pages[0].Lines), 4, 'one line for each row');
    CheckEq(string(job.Pages[0].Lines[0]), 'Rent' + StringOfChar(' ', 15) + '1200', 'text on the left, numbers on the right of their column');
    CheckEq(string(job.Pages[0].Lines[1]), 'A long description that runs on', 'long text runs on into empty cells');
    CheckEq(string(job.Pages[0].Lines[2]), 'A long description that x', 'until it meets a cell that is not empty');
    CheckEq(string(job.Pages[0].Lines[3]), 'Total' + StringOfChar(' ', 14) + '1200', 'a formula shows its result');
    { A4 is a little narrower and taller }
    BuildPrint(sh, 0, 0, 2, lr, 'x', psA4, job);
    CheckInt(job.CharsPerLine, 81, 'an A4 page holds 81');
    CheckInt(job.BodyLines, 57, 'and 57 lines');
    { too wide for portrait: landscape; wider still: smaller type }
    sh.Clear;
    for i := 0 to 7 do sh.SetColWidth(i, 12);
    for i := 0 to 7 do sh.SetEntry(i, 0, UnicodeString(IntToStr(i)));
    BuildPrint(sh, 0, 0, 7, 0, 't', psLetter, job);
    Check(job.Landscape and (job.PointSize = 10), 'eight columns of 12 (96) need landscape');
    for i := 0 to 11 do sh.SetColWidth(i, 12);
    for i := 0 to 11 do sh.SetEntry(i, 0, UnicodeString(IntToStr(i)));
    BuildPrint(sh, 0, 0, 11, 0, 't', psLetter, job);
    Check(job.Landscape and (job.PointSize = 8), 'twelve columns (144 > 114) need 8 point');
    CheckInt(job.CharsPerLine, 142, 'which holds 142');
    CheckInt(Length(job.Pages), 2, 'and 144 is still a little too wide: two strips');
    CheckEq(string(job.Pages[0].Header), 't (columns A to K)', 'the first strip says which columns');
    CheckEq(string(job.Pages[1].Header), 't (columns L to L)', 'and the second');
    CheckEq(string(job.Pages[1].Footer), 'Page 2 of 2', 'pages are numbered across strips');
    { many rows: more pages, in order }
    sh.Clear;
    for i := 0 to 119 do sh.SetEntry(0, i, UnicodeString('row ' + IntToStr(i + 1)));
    BuildPrint(sh, 0, 0, 0, 119, 'long', psLetter, job);
    CheckInt(Length(job.Pages), 3, '120 rows at 53 a page is three pages');
    CheckEq(string(job.Pages[0].Lines[0]), 'row 1', 'the first line of page 1');
    CheckEq(string(job.Pages[1].Lines[0]), 'row 54', 'the first line of page 2');
    CheckEq(string(job.Pages[2].Lines[High(job.Pages[2].Lines)]), 'row 120', 'the last line of the last page');
    CheckInt(Length(job.Pages[2].Lines), 14, 'which has the rest');
    { a part of the sheet }
    BuildPrint(sh, 0, 9, 0, 11, 'part', psLetter, job);
    CheckInt(Length(job.Pages), 1, 'a selection');
    CheckEq(string(job.Pages[0].Lines[0]), 'row 10', 'starts where it should');
    { text in the last column runs on into the free width of the page }
    sh.Clear;
    sh.SetEntry(0, 0, 'a');
    sh.SetEntry(1, 0, 'This goes on for far longer than its column but fits the page');
    BuildPrint(sh, 0, 0, 1, 0, 'r', psLetter, job);
    CheckEq(string(job.Pages[0].Lines[0]), 'a' + StringOfChar(' ', 11) + 'This goes on for far longer than its column but fits the page', 'the last column is not cut at its edge');
    sh.SetEntry(1, 0, UnicodeString(StringOfChar('z', 200)));
    BuildPrint(sh, 0, 0, 1, 0, 'r', psLetter, job);
    Check((Length(job.Pages[0].Lines[0]) <= job.CharsPerLine) and (Length(job.Pages[0].Lines[0]) >= job.CharsPerLine - 4), 'but only as far as the page goes');
    { a single column wider than the page is cut, not lost }
    sh.Clear;
    sh.SetColWidth(0, 100);
    sh.SetEntry(0, 0, UnicodeString(StringOfChar('w', 99)));
    BuildPrint(sh, 0, 0, 0, 0, 'w', psLetter, job);
    CheckInt(Length(job.Pages), 1, 'one wide column');
    Check(Length(job.Pages[0].Lines[0]) <= job.CharsPerLine, 'its line fits the page');

    { text output: pages are separated by form feeds }
    sh.Clear;
    for i := 0 to 59 do sh.SetEntry(0, i, UnicodeString('r' + IntToStr(i + 1)));
    BuildPrint(sh, 0, 0, 0, 59, 'T', psLetter, job);
    txt := string(JobToText(job));
    CheckInt(Length(job.Pages), 2, 'sixty rows are two pages');
    Check(Pos(#12, txt) > 0, 'a form feed between the pages');
    Check(Pos('Page 2 of 2', txt) > Pos(#12, txt), 'the second page ends with its number');
    Check(Copy(txt, 1, 3) = 'T'#10#10, 'the title, then a blank line');

    { the PDF }
    sh.Clear;
    sh.SetColWidth(0, 40);
    sh.SetEntry(0, 0, 'café (1) \ ok');
    sh.SetEntry(0, 1, '€ and “quotes” and ☕');
    BuildPrint(sh, 0, 0, 0, 1, 'Title (one)', psLetter, job);
    pdf := string(PdfBytes(job));
    CheckEq(Copy(pdf, 1, 8), '%PDF-1.4', 'a PDF header');
    Check(Pos('/Count 1', pdf) > 0, 'one page');
    Check(Pos('/BaseFont /Courier', pdf) > 0, 'the standard font, nothing to embed');
    Check(Pos('(caf\351 \(1\) \\ ok)', pdf) > 0, 'brackets and backslashes are escaped, é is the WinAnsi byte');
    Check(Pos('(\200 and \223quotes\224 and ?)', pdf) > 0, 'euro and curly quotes have WinAnsi bytes; what is not there becomes ?');
    Check(Pos('(Title \(one\))', pdf) > 0, 'the title');
    Check(Pos('%%EOF', pdf) > 0, 'an end');
    { every object is where the cross-reference table says }
    p := Pos('startxref', pdf);
    off := StrToInt(Copy(pdf, p + 10, Pos(#10, Copy(pdf, p + 10, 20)) - 1));
    CheckEq(Copy(pdf, off + 1, 4), 'xref', 'startxref points at the table');
    { and each entry of the table points at its object: 20 bytes an entry, the first is the free one }
    p := Pos('0000000000 65535 f', pdf);
    Check(p > 0, 'the table starts with the free entry');
    for i := 1 to 5 do
    begin
      off := StrToInt(Copy(pdf, p + 20 * i, 10));
      CheckEq(Copy(pdf, off + 1, Length(IntToStr(i)) + 6), IntToStr(i) + ' 0 obj', 'object ' + IntToStr(i) + ' is where the table says');
    end;
    { two pages: five objects plus two for every further page }
    sh.Clear;
    for i := 0 to 59 do sh.SetEntry(0, i, 'x');
    BuildPrint(sh, 0, 0, 0, 59, 'T', psLetter, job);
    pdf := string(PdfBytes(job));
    Check(Pos('/Count 2', pdf) > 0, 'two pages');
    Check(Pos('/Size 8', pdf) > 0, 'seven objects and the free entry');
    fn := 'build/test/print_test.pdf';
    if FileExists(fn) then DeleteFile(fn);
    CheckEq(WritePdfFile(job, fn), '', 'write the file');
    sl := TStringList.Create;
    try
      Check(FileExists(fn), 'it is there');
      Check(not FileExists(fn + '.tmp'), 'no temporary file left');
    finally
      sl.Free;
    end;
  finally
    sh.Free;
  end;
end;
