{ tsapp_screens.inc - help, column width, formats, go to and find (included by tsapp.pas) }

{ ---- help: lines are "#Heading", "keys|what they do" or plain text, wrapped to the window ---- }

const
  HelpKeyMax = 26;

function HelpBreak(var rest: string; w: Integer): string;
var
  k: Integer;
begin
  if Length(rest) <= w then
  begin
    Result := rest;
    rest := '';
    Exit;
  end;
  k := w;
  while (k > 0) and (rest[k + 1] <> ' ') do Dec(k);
  if k = 0 then k := w;
  Result := TrimRight(Copy(rest, 1, k));
  rest := TrimLeft(Copy(rest, k + 1, MaxInt));
end;

procedure TApp.WrapHelp(width: Integer);
var
  i, p, keyW, descCol, avail: Integer;
  s, key, rest: string;
begin
  HelpLines.Clear;
  HelpWrapW := width;
  keyW := 0;
  for i := 0 to HelpText.Count - 1 do
  begin
    p := Pos('|', HelpText[i]);
    if p > keyW + 1 then keyW := p - 1;
  end;
  if keyW > HelpKeyMax then keyW := HelpKeyMax;
  descCol := 2 + keyW + 2;
  avail := width - descCol;
  for i := 0 to HelpText.Count - 1 do
  begin
    s := HelpText[i];
    p := Pos('|', s);
    if s = '' then
      HelpLines.Add('T')
    else if s[1] = '#' then
      HelpLines.Add('H' + Copy(s, 2, MaxInt))
    else if p > 0 then
    begin
      key := Copy(s, 1, p - 1);
      rest := Copy(s, p + 1, MaxInt);
      if avail >= 24 then
      begin
        HelpLines.Add('K' + key + #1 + StringOfChar(' ', descCol - 2 - Length(key)) + HelpBreak(rest, avail));
        while rest <> '' do HelpLines.Add('D' + StringOfChar(' ', descCol) + HelpBreak(rest, avail));
      end
      else
      begin
        HelpLines.Add('K' + key + #1);
        while rest <> '' do HelpLines.Add('D' + StringOfChar(' ', 6) + HelpBreak(rest, width - 6));
      end;
    end
    else
    begin
      rest := s;
      while rest <> '' do HelpLines.Add('T  ' + HelpBreak(rest, width - 2));
    end;
  end;
end;

procedure TApp.DrawHelp;
var
  textC, backC, dimC, keyC, headC: LongWord;
  i, rows, k, p: Integer;
  s, key: string;
begin
  if (HelpLines.Count = 0) or (HelpWrapW <> Gfx.Cols - 2) then WrapHelp(Gfx.Cols - 2);
  textC := RGBOf(Cfg.ColText);
  backC := RGBOf(Cfg.ColBack);
  dimC := RGBOf(Cfg.ColHeader);
  keyC := RGBOf(Cfg.ColFormula);
  headC := 7;
  headC := RGBOf(7);
  Gfx.FillCells(0, 0, Gfx.Cols, 1, textC);
  Gfx.PutText(0, 0, ' TieSheet help', backC, ST_BOLD);
  Gfx.PutText(1, 1, 'Arrows/PgUp/PgDn scroll   Esc closes', dimC);
  rows := Gfx.Rows - 4;
  for i := 0 to rows - 1 do
  begin
    k := HelpTop + i;
    if k >= HelpLines.Count then Break;
    s := HelpLines[k];
    case s[1] of
      'H': Gfx.PutText(1, 3 + i, UTF8Decode(Copy(s, 2, MaxInt)), headC, ST_BOLD);
      'K':
        begin
          p := Pos(#1, s);
          key := Copy(s, 2, p - 2);
          Gfx.PutText(3, 3 + i, UTF8Decode(key), keyC, ST_BOLD);
          Gfx.PutText(3 + Length(key), 3 + i, UTF8Decode(Copy(s, p + 1, MaxInt)), textC);
        end;
    else
      Gfx.PutText(1, 3 + i, UTF8Decode(Copy(s, 2, MaxInt)), textC);
    end;
  end;
  Gfx.PutText(1, Gfx.Rows - 1, UnicodeString(Format('%d%%', [(HelpTop + rows) * 100 div (HelpLines.Count + 1)])), dimC);
end;

procedure BuildHelp(t: TStringList);
begin
  t.Clear;
  t.Add('#TieSheet');
  t.Add('A small spreadsheet for money, lists and schedules, in the style of TiePaper.  Everything is done from the keyboard.');
  t.Add('Control keys: hold Ctrl and press the key, or tap and release Ctrl and then press the key.  Capitals mean Ctrl+Shift.');
  t.Add('');
  t.Add('#Moving');
  t.Add('Arrows|Move one cell');
  t.Add('Ctrl+arrows|Jump to the edge of a block of cells');
  t.Add('Home / End|First column / last used column');
  t.Add('Ctrl+Home / Ctrl+End|Top left / the last used cell');
  t.Add('PgUp / PgDn|A screen up / down');
  t.Add('Ctrl+G|Go to a cell, e.g. B12');
  t.Add('Ctrl+F / Ctrl+H|Find / find the next one');
  t.Add('');
  t.Add('#Entering');
  t.Add('Just type|Replaces what is in the cell');
  t.Add('F2|Edit what is already in the cell');
  t.Add('Enter / Tab|Finish and go down / right (with Shift: up / left)');
  t.Add('Up / Down|Finish and go up / down');
  t.Add('Esc|Cancel the entry');
  t.Add('Delete, Ctrl+E|Clear the selected cells');
  t.Add('');
  t.Add('#Selecting');
  t.Add('Shift+arrows|Select cells');
  t.Add('Ctrl+Space|Select the column');
  t.Add('Alt+A|Select everything');
  t.Add('Esc|Clear the selection');
  t.Add('Mouse|Click, drag, double-click to edit, wheel to scroll, Ctrl+wheel to zoom');
  t.Add('');
  t.Add('#Copying and undo');
  t.Add('Alt+C / Alt+X / Alt+V|Copy / cut / paste with the system clipboard; formulas copied inside TieSheet keep working, their cell references move');
  t.Add('Ctrl+Insert, Shift+Delete, Shift+Insert|The same three');
  t.Add('Ctrl+D / Ctrl+R|Fill down / right from the first row / column of the selection (one cell: from the cell above / left)');
  t.Add('Ctrl+Z / Ctrl+Shift+Z|Undo / redo');
  t.Add('');
  t.Add('#Layout');
  t.Add('F3|Column width');
  t.Add('F4|Format the selected cells: general, number, currency, percent, date.  With Ctrl+Space first, the whole column gets the format, also for numbers typed later');
  t.Add('');
  t.Add('#Files');
  t.Add('Ctrl+L|Load a file: a TieSheet file or a CSV');
  t.Add('Ctrl+S / Ctrl+Shift+S|Save / save under another name');
  t.Add('Ctrl+Shift+X|Quit');
  t.Add('.tsh|The TieSheet file keeps formulas, column widths and formats.  It is plain text.');
  t.Add('.csv|A CSV keeps formulas as typed, or only their results for sharing (you are asked when you save).  Widths and formats are not kept in a CSV.');
  t.Add('');
  t.Add('#What typing means');
  t.Add('=SUM(B2:B9)|A formula; the cell shows its result');
  t.Add('12.50, $1,234.50, 5%|Numbers; they are shown the way they were typed');
  t.Add('(5)|Minus five');
  t.Add('2026-11-10|A date');
  t.Add('TRUE, FALSE|Yes / no');
  t.Add('''007|Text, even when it looks like something else');
  t.Add('Anything else|Text');
  t.Add('');
  t.Add('#Formulas');
  t.Add('Operators|+ - * / ^ & (join text) % and = <> < > <= >=');
  t.Add('Cells|A1, $A$1 (fixed), A1:B9 (a block)');
  t.Add('Sums|SUM AVERAGE MIN MAX COUNT COUNTA PRODUCT SUMIF COUNTIF AVERAGEIF');
  t.Add('Numbers|ABS ROUND ROUNDUP ROUNDDOWN INT MOD POWER SQRT');
  t.Add('Logic|IF AND OR NOT IFERROR ISBLANK ISNUMBER ISTEXT ISERROR');
  t.Add('Text|LEN LEFT RIGHT MID UPPER LOWER TRIM CONCAT VALUE');
  t.Add('Dates|DATE YEAR MONTH DAY WEEKDAY TODAY DAYS EDATE DATEDIF');
  t.Add('Numbers are exact: 0.1 + 0.2 is 0.3, and money adds up to the cent.');
  t.Add('');
  t.Add('#Not built yet');
  t.Add('Sorting, inserting and deleting rows and columns, the print preview (Ctrl+V) and output (Ctrl+O).');
end;

procedure TApp.DoHelp;
var
  ev: TKeyEv;
  rows: Integer;
begin
  if HelpText.Count = 0 then BuildHelp(HelpText);
  HelpTop := 0;
  FullScreen := @DrawHelp;
  try
    while WaitKey(ev) do
    begin
      rows := Gfx.Rows - 4;
      if (HelpLines.Count = 0) or (HelpWrapW <> Gfx.Cols - 2) then WrapHelp(Gfx.Cols - 2);
      if ev.Kind = ekWheel then HelpTop := HelpTop - ev.Wheel * 3
      else if ev.Kind = ekKey then
        case ev.Sym of
          SDLK_ESCAPE, SDLK_F1: Break;
          SDLK_UP: Dec(HelpTop);
          SDLK_DOWN: Inc(HelpTop);
          SDLK_PAGEUP: Dec(HelpTop, rows - 1);
          SDLK_PAGEDOWN, SDLK_SPACE: Inc(HelpTop, rows - 1);
          SDLK_HOME: HelpTop := 0;
          SDLK_END: HelpTop := HelpLines.Count;
        end;
      if HelpTop > HelpLines.Count - rows then HelpTop := HelpLines.Count - rows;
      if HelpTop < 0 then HelpTop := 0;
    end;
  finally
    FullScreen := nil;
  end;
end;

{ ---- column width, format, go to, find ---- }

procedure TApp.DoWidth;
var
  v: UnicodeString;
  w, c1, r1, c2, r2, c: Integer;
  before: UnicodeString;
begin
  SelRect(c1, r1, c2, r2);
  v := UnicodeString(IntToStr(Sheet.ColWidth(CurC)));
  if not Prompt('Column width in characters (3-100):', v) then Exit;
  w := StrToIntDef(Trim(string(v)), 0);
  if (w < MIN_COL_WIDTH) or (w > MAX_COL_WIDTH) then
  begin
    SetMsg('A width from 3 to 100, please', True);
    Exit;
  end;
  before := Snapshot;
  for c := c1 to c2 do Sheet.SetColWidth(c, w);
  Changed(before);
end;

procedure TApp.DoFormat;
var
  k, dec, c1, r1, c2, r2, c, r: Integer;
  v: UnicodeString;
  fmt: TFormat;
  before: UnicodeString;
begin
  k := AskChoice('Format:  (G)eneral  (N)umber  (C)urrency  (P)ercent  (D)ate', 'GNCPD');
  if k < 0 then Exit;
  fmt := GeneralFormat;
  case k of
    1, 2, 3:
      begin
        if k = 3 then v := '0' else v := '2';
        if not Prompt('Digits after the point:', v) then Exit;
        dec := StrToIntDef(Trim(string(v)), -1);
        if (dec < 0) or (dec > 15) then begin SetMsg('From 0 to 15 digits, please', True); Exit; end;
        fmt.Decimals := dec;
        if k = 1 then
        begin
          fmt.Kind := nfNumber;
          dec := AskChoice('Thousands separator?  (Y)es  (N)o', 'YN');
          if dec < 0 then Exit;
          fmt.Thousands := dec = 0;
        end
        else if k = 2 then
        begin
          fmt.Kind := nfCurrency;
          fmt.Thousands := True;
        end
        else
          fmt.Kind := nfPercent;
      end;
    4: fmt.Kind := nfDate;
  end;
  SelRect(c1, r1, c2, r2);
  before := Snapshot;
  for r := r1 to r2 do
    for c := c1 to c2 do
      if Sheet.Exists(c, r) and (Sheet.GetKind(c, r) in [ckNumber, ckFormula]) then Sheet.SetFormat(c, r, fmt);
  if SelCols and SelActive then
    for c := c1 to c2 do Sheet.SetColFormat(c, fmt);
  Changed(before);
end;

procedure TApp.DoGoto;
var
  v: UnicodeString;
  c, r: Integer;
begin
  v := '';
  if not Prompt('Go to cell:', v) then Exit;
  if ParseCellName(UnicodeString(UpperCase(Trim(string(v)))), c, r) then MoveCursor(c, r, False)
  else SetMsg('That is not a cell name (try B12)', True);
end;

procedure TApp.DoFind(askFirst: Boolean);
var
  v: UnicodeString;
  lc, lr, total, idx0, k, idx, c, r: Integer;
  needle: UnicodeString;
begin
  if askFirst or (FindText = '') then
  begin
    v := FindText;
    if not Prompt('Find:', v) then Exit;
    FindText := v;
    if v = '' then Exit;
  end;
  if not LastUsed(lc, lr) then begin SetMsg('Nothing to find'); Exit; end;
  needle := UnicodeLowerCase(FindText);
  total := (lr + 1) * (lc + 1);
  { where the search starts: after the cursor, in row order; a cursor past the used area is at the very end }
  if CurR > lr then idx0 := total - 1
  else if CurC > lc then idx0 := CurR * (lc + 1) + lc
  else idx0 := CurR * (lc + 1) + CurC;
  for k := 1 to total do
  begin
    idx := (idx0 + k) mod total;
    r := idx div (lc + 1);
    c := idx mod (lc + 1);
    if not Sheet.Exists(c, r) then Continue;
    if (Pos(needle, UnicodeLowerCase(Sheet.Display(c, r))) > 0) or
       (Pos(needle, UnicodeLowerCase(Sheet.GetRaw(c, r))) > 0) then
    begin
      MoveCursor(c, r, False);
      SetMsg(UnicodeString('Found in ' + CellName(c, r)));
      Exit;
    end;
  end;
  SetMsg('Not found');
end;
