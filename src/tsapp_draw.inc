{ tsapp_draw.inc - drawing the screen (included by tsapp.pas)

  Row 0 is the title bar, row 1 the input line (the cell being looked at or typed into), row 2 the
  column letters, then the grid, and the last row is the status line. }

function TApp.VisRows: Integer;
begin
  Result := Gfx.Rows - 4;
  if Result < 1 then Result := 1;
end;

function TApp.GutterW: Integer;
begin
  Result := Length(IntToStr(TopRow + VisRows)) + 1;
  if Result < 4 then Result := 4;
end;

{ the column after the last one that fits whole, when the first shown is left }
function TApp.VisColsEnd(left: Integer): Integer;
var
  x, c, w: Integer;
begin
  x := GutterW;
  c := left;
  while c <= MAX_COL do
  begin
    w := Sheet.ColWidth(c);
    if x + w > Gfx.Cols then Break;
    Inc(x, w);
    Inc(c);
  end;
  Result := c;
end;

procedure TApp.SelRect(out c1, r1, c2, r2: Integer);
var
  lc, lr: Integer;
begin
  if SelActive then
  begin
    if AnchorC < CurC then begin c1 := AnchorC; c2 := CurC; end else begin c1 := CurC; c2 := AnchorC; end;
    if AnchorR < CurR then begin r1 := AnchorR; r2 := CurR; end else begin r1 := CurR; r2 := AnchorR; end;
  end
  else
  begin
    c1 := CurC; c2 := CurC; r1 := CurR; r2 := CurR;
  end;
  if SelCols and SelActive then
  begin
    r1 := 0;
    r2 := CurR;
    if LastUsed(lc, lr) and (lr > r2) then r2 := lr;
  end;
end;

function TApp.LastUsed(out lc, lr: Integer): Boolean;
begin
  Result := Sheet.Extent(lc, lr);
end;

procedure TApp.EnsureVisible;
var
  sum, c: Integer;
begin
  if CurR < TopRow then TopRow := CurR;
  if CurR >= TopRow + VisRows then TopRow := CurR - VisRows + 1;
  if TopRow < 0 then TopRow := 0;
  if CurC < LeftCol then LeftCol := CurC;
  sum := 0;
  for c := LeftCol to CurC do Inc(sum, Sheet.ColWidth(c));
  while (GutterW + sum > Gfx.Cols) and (LeftCol < CurC) do
  begin
    Dec(sum, Sheet.ColWidth(LeftCol));
    Inc(LeftCol);
  end;
end;

procedure TApp.CellLook(c, r: Integer; out s: UnicodeString; out right: Boolean; out fg: LongWord);
var
  v: TValue;
begin
  s := '';
  right := False;
  fg := RGBOf(Cfg.ColText);
  if not Sheet.Exists(c, r) then Exit;
  v := Sheet.Value(c, r);
  s := Sheet.Display(c, r);
  right := v.Kind in [vkNum, vkBool, vkErr];
  if v.Kind = vkErr then fg := RGBOf(Cfg.ColError)
  else if Sheet.GetKind(c, r) = ckFormula then fg := RGBOf(Cfg.ColFormula);
end;

procedure TApp.DrawTitleBar;
var
  t: UnicodeString;
begin
  Gfx.FillCells(0, 0, Gfx.Cols, 1, RGBOf(Cfg.ColText));
  t := ' TieSheet';
  if FileName <> '' then t := t + ' - ' + UTF8Decode(ExtractFileName(FileName));
  if Dirty then t := t + ' *';
  Gfx.PutText(0, 0, t, RGBOf(Cfg.ColBack), ST_BOLD);
end;

procedure TApp.DrawInputLine;
var
  c1, r1, c2, r2, x, avail, scroll, i, curCol: Integer;
  ref: string;
  txt, shown: UnicodeString;
  textC, backC: LongWord;
begin
  textC := RGBOf(Cfg.ColText);
  backC := RGBOf(Cfg.ColBack);
  SelRect(c1, r1, c2, r2);
  if (c1 = c2) and (r1 = r2) then ref := CellName(CurC, CurR)
  else ref := CellName(c1, r1) + ':' + CellName(c2, r2);
  Gfx.PutText(0, 1, UnicodeString(ref), RGBOf(Cfg.ColHeader), ST_BOLD);
  x := Length(ref) + 2;
  avail := Gfx.Cols - x - 1;
  if avail < 1 then Exit;
  if Editing then
  begin
    txt := EditBuf;
    scroll := 0;
    if EditPos >= avail then scroll := EditPos - avail + 1;
    shown := Copy(txt, scroll + 1, avail);
    Gfx.FillCells(x, 1, Length(shown) + 1, 1, backC);
    Gfx.PutText(x, 1, shown, textC);
    curCol := x + EditPos - scroll;
    if BlinkOn and (curCol < Gfx.Cols) then
    begin
      Gfx.FillCells(curCol, 1, 1, 1, textC);
      if EditPos < Length(txt) then Gfx.PutChar(curCol, 1, txt[EditPos + 1], ST_REGULAR, backC);
    end;
  end
  else
  begin
    txt := Sheet.GetRaw(CurC, CurR);
    for i := 1 to Length(txt) do
      if (txt[i] = #10) or (txt[i] = #13) then txt[i] := ' ';
    Gfx.PutText(x, 1, Copy(txt, 1, avail), textC);
  end;
end;

procedure TApp.DrawHeaders;
var
  c, x, w, c1, r1, c2, r2, off: Integer;
  name: string;
  head, backC: LongWord;
  inSel: Boolean;
begin
  head := RGBOf(Cfg.ColHeader);
  backC := RGBOf(Cfg.ColBack);
  SelRect(c1, r1, c2, r2);
  Gfx.FillCells(0, 2, Gfx.Cols, 1, head);
  x := GutterW;
  c := LeftCol;
  while (x < Gfx.Cols) and (c <= MAX_COL) do
  begin
    w := Sheet.ColWidth(c);
    if x + w > Gfx.Cols then w := Gfx.Cols - x;
    name := ColName(c);
    inSel := (c >= c1) and (c <= c2);
    if inSel then Gfx.FillCells(x, 2, w, 1, RGBOf(Cfg.ColText));
    off := (w - Length(name)) div 2;
    if off < 0 then off := 0;
    if inSel then Gfx.PutText(x + off, 2, UnicodeString(name), backC, ST_BOLD)
    else Gfx.PutText(x + off, 2, UnicodeString(name), backC, ST_REGULAR);
    Inc(x, w);
    Inc(c);
  end;
end;

procedure TApp.DrawGrid;
var
  i, r, c, x, y, w, gw, avail, k, xx, c1, r1, c2, r2, cw, st: Integer;
  s: UnicodeString;
  right, inSel, isCur: Boolean;
  fg, head, textC, backC: LongWord;
  num: string;
begin
  head := RGBOf(Cfg.ColHeader);
  textC := RGBOf(Cfg.ColText);
  backC := RGBOf(Cfg.ColBack);
  SelRect(c1, r1, c2, r2);
  gw := GutterW;
  for i := 0 to VisRows - 1 do
  begin
    r := TopRow + i;
    y := 3 + i;
    if r > MAX_ROW then Break;
    num := IntToStr(r + 1);
    if (r >= r1) and (r <= r2) then
    begin
      Gfx.FillCells(0, y, gw, 1, textC);
      Gfx.PutText(gw - 1 - Length(num), y, UnicodeString(num), backC, ST_BOLD);
    end
    else
    begin
      Gfx.FillCells(0, y, gw, 1, head);
      Gfx.PutText(gw - 1 - Length(num), y, UnicodeString(num), backC, ST_REGULAR);
    end;
    x := gw;
    c := LeftCol;
    while (x < Gfx.Cols) and (c <= MAX_COL) do
    begin
      w := Sheet.ColWidth(c);
      if x + w > Gfx.Cols then w := Gfx.Cols - x;
      inSel := SelActive and (c >= c1) and (c <= c2) and (r >= r1) and (r <= r2);
      isCur := (c = CurC) and (r = CurR);
      if isCur then Gfx.FillCells(x, y, w, 1, textC)
      else if inSel then Gfx.FillCells(x, y, w, 1, RGBOf(Cfg.ColSelect));
      CellLook(c, r, s, right, fg);
      if isCur then fg := backC;
      st := ST_REGULAR;
      if isCur then st := ST_BOLD;
      if s <> '' then
      begin
        cw := Sheet.ColWidth(c) - 1;
        if right then
        begin
          if Length(s) > cw then s := UnicodeString(StringOfChar('#', cw));
          if x + cw - Length(s) >= 0 then Gfx.PutText(x + cw - Length(s), y, s, fg, st);
        end
        else
        begin
          { text runs on into the empty cells to its right }
          avail := cw;
          k := c + 1;
          xx := x + Sheet.ColWidth(c);
          while (Length(s) > avail) and (xx < Gfx.Cols) and (k <= MAX_COL) and (not Sheet.Exists(k, r)) do
          begin
            Inc(avail, Sheet.ColWidth(k));
            Inc(xx, Sheet.ColWidth(k));
            Inc(k);
          end;
          if Length(s) > avail then s := Copy(s, 1, avail);
          if x + Length(s) > Gfx.Cols then s := Copy(s, 1, Gfx.Cols - x);
          Gfx.PutText(x, y, s, fg, st);
        end;
      end;
      Inc(x, w);
      Inc(c);
    end;
  end;
end;

{ for a selection of several cells: what they add up to }
function TApp.SelSummary: UnicodeString;
var
  c1, r1, c2, r2, c, r, n: Integer;
  total: TDec;
  v: TValue;
begin
  Result := '';
  if not SelActive then Exit;
  SelRect(c1, r1, c2, r2);
  if (c1 = c2) and (r1 = r2) then Exit;
  if Int64(c2 - c1 + 1) * (r2 - r1 + 1) > 200000 then Exit;
  total := DecZero;
  n := 0;
  for r := r1 to r2 do
    for c := c1 to c2 do
    begin
      if not Sheet.Exists(c, r) then Continue;
      v := Sheet.Value(c, r);
      if v.Kind = vkNum then
      begin
        total := DecAdd(total, v.Num);
        Inc(n);
      end;
    end;
  if n > 0 then Result := 'Sum ' + NumToText(total) + '  N ' + UnicodeString(IntToStr(n));
end;

procedure TApp.DrawStatus;
var
  y, room: Integer;
  left, right: UnicodeString;
  fg: LongWord;
begin
  y := Gfx.Rows - 1;
  Gfx.FillCells(0, y, Gfx.Cols, 1, RGBOf(Cfg.ColText));
  right := '';
  if CtrlMode then right := right + ' CTRL';
  if Editing then right := right + ' EDIT';
  if SelActive then right := right + ' ' + SelSummary;
  if Msg <> '' then left := ' ' + Msg
  else if Gfx.Cols >= 90 then left := ' F1 Help   Ctrl+S Save   Ctrl+L Load   Ctrl+Shift+X Quit'
  else left := ' F1 Help  ^S Save  ^L Load  ^Shift+X Quit';
  room := Gfx.Cols - Length(right) - 2;
  if room < 1 then room := 1;
  if Length(left) > room then left := Copy(left, 1, room);
  if (Msg <> '') and MsgErr then fg := RGBOf(Cfg.ColError) else fg := RGBOf(Cfg.ColBack);
  if MsgErr and (Msg <> '') then Gfx.PutText(0, y, left, fg, ST_BOLD) else Gfx.PutText(0, y, left, fg, ST_REGULAR);
  if right <> '' then Gfx.PutText(Gfx.Cols - Length(right) - 1, y, right, RGBOf(Cfg.ColBack), ST_BOLD);
end;

procedure TApp.DrawScreen;
begin
  if FollowCursor then EnsureVisible;
  DrawTitleBar;
  DrawInputLine;
  DrawHeaders;
  DrawGrid;
  DrawStatus;
end;
