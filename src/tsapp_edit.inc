{ tsapp_edit.inc - moving, entering, selecting, the clipboard and undo (included by tsapp.pas) }

{ ---- undo: the whole sheet as a TieSheet file, before each change ---- }

function TApp.Snapshot: UnicodeString;
begin
  Result := SheetToText(Sheet);
end;

procedure TApp.PushUndo(const before: UnicodeString);
var
  n, i: Integer;
begin
  n := Length(UndoStack);
  SetLength(UndoStack, n + 1);
  UndoStack[n].Text := before;
  UndoStack[n].C := CurC;
  UndoStack[n].R := CurR;
  Inc(UndoBytes, Int64(Length(before)) * 2);
  SetLength(RedoStack, 0);
  while (Length(UndoStack) > 1) and ((Length(UndoStack) > 300) or (UndoBytes > 64 * 1024 * 1024)) do
  begin
    Dec(UndoBytes, Int64(Length(UndoStack[0].Text)) * 2);
    for i := 1 to High(UndoStack) do UndoStack[i - 1] := UndoStack[i];
    SetLength(UndoStack, Length(UndoStack) - 1);
  end;
end;

{ after a change was made: remember how it was, unless nothing really changed }
procedure TApp.Changed(const before: UnicodeString);
begin
  if Snapshot = before then Exit;
  PushUndo(before);
  Dirty := True;
end;

procedure TApp.DoUndo;
var
  step: TUndoStep;
  n: Integer;
begin
  n := Length(UndoStack);
  if n = 0 then begin SetMsg('Nothing to undo'); Exit; end;
  SetLength(RedoStack, Length(RedoStack) + 1);
  RedoStack[High(RedoStack)].Text := Snapshot;
  RedoStack[High(RedoStack)].C := CurC;
  RedoStack[High(RedoStack)].R := CurR;
  step := UndoStack[n - 1];
  SetLength(UndoStack, n - 1);
  Dec(UndoBytes, Int64(Length(step.Text)) * 2);
  SheetFromText(Sheet, step.Text, nil);
  CurC := step.C;
  CurR := step.R;
  SelActive := False;
  Dirty := True;
  FollowCursor := True;
  SetMsg('Undone');
end;

procedure TApp.DoRedo;
var
  step: TUndoStep;
  n: Integer;
begin
  n := Length(RedoStack);
  if n = 0 then begin SetMsg('Nothing to redo'); Exit; end;
  SetLength(UndoStack, Length(UndoStack) + 1);
  UndoStack[High(UndoStack)].Text := Snapshot;
  UndoStack[High(UndoStack)].C := CurC;
  UndoStack[High(UndoStack)].R := CurR;
  Inc(UndoBytes, Int64(Length(UndoStack[High(UndoStack)].Text)) * 2);
  step := RedoStack[n - 1];
  SetLength(RedoStack, n - 1);
  SheetFromText(Sheet, step.Text, nil);
  CurC := step.C;
  CurR := step.R;
  SelActive := False;
  Dirty := True;
  FollowCursor := True;
  SetMsg('Redone');
end;

{ ---- moving ---- }

procedure TApp.MoveCursor(nc, nr: Integer; extend: Boolean);
begin
  if nc < 0 then nc := 0;
  if nc > MAX_COL then nc := MAX_COL;
  if nr < 0 then nr := 0;
  if nr > MAX_ROW then nr := MAX_ROW;
  if extend then
  begin
    if not SelActive then
    begin
      AnchorC := CurC;
      AnchorR := CurR;
      SelActive := True;
      SelCols := False;
    end;
  end
  else
  begin
    SelActive := False;
    SelCols := False;
  end;
  CurC := nc;
  CurR := nr;
  FollowCursor := True;
end;

{ Ctrl+arrow: along a run of filled cells to its end, or to the next filled cell }
procedure TApp.JumpCursor(dc, dr: Integer; extend: Boolean);
var
  lc, lr, p, step, limit: Integer;
  horizontal: Boolean;

  function Has(q: Integer): Boolean;
  begin
    if horizontal then Result := Sheet.Exists(q, CurR) else Result := Sheet.Exists(CurC, q);
  end;

begin
  if not LastUsed(lc, lr) then begin lc := 0; lr := 0; end;
  horizontal := dc <> 0;
  if horizontal then begin p := CurC; step := dc; if dc > 0 then limit := lc else limit := 0; end
  else begin p := CurR; step := dr; if dr > 0 then limit := lr else limit := 0; end;
  if ((step > 0) and (p >= limit)) or ((step < 0) and (p <= limit)) then
  begin
    { already at the edge of the data }
  end
  else if Has(p) and Has(p + step) then
  begin
    while ((step > 0) and (p < limit)) or ((step < 0) and (p > limit)) do
    begin
      if not Has(p + step) then Break;
      Inc(p, step);
    end;
  end
  else
  begin
    Inc(p, step);
    while (((step > 0) and (p < limit)) or ((step < 0) and (p > limit))) and (not Has(p)) do Inc(p, step);
  end;
  if horizontal then MoveCursor(p, CurR, extend) else MoveCursor(CurC, p, extend);
end;

procedure TApp.SelectAll;
var
  lc, lr: Integer;
begin
  if not LastUsed(lc, lr) then Exit;
  AnchorC := 0;
  AnchorR := 0;
  CurC := lc;
  CurR := lr;
  SelActive := True;
  SelCols := False;
  FollowCursor := True;
end;

procedure TApp.SelectColumn;
begin
  AnchorC := CurC;
  AnchorR := 0;
  SelActive := True;
  SelCols := True;
end;

function TApp.CellAt(x, y: Integer; out c, r: Integer): Boolean;
var
  gx, gy, cx, w: Integer;
begin
  Result := False;
  c := 0;
  r := 0;
  if (Gfx.CellW <= 0) or (Gfx.CellH <= 0) then Exit;
  gx := (x - Gfx.Border) div Gfx.CellW;
  gy := (y - Gfx.Border) div Gfx.CellH;
  if (gy < 3) or (gy >= 3 + VisRows) or (gx < GutterW) then Exit;
  r := TopRow + gy - 3;
  cx := GutterW;
  c := LeftCol;
  while c <= MAX_COL do
  begin
    w := Sheet.ColWidth(c);
    if gx < cx + w then Break;
    Inc(cx, w);
    Inc(c);
    if cx >= Gfx.Cols then Exit;
  end;
  Result := (c <= MAX_COL) and (r <= MAX_ROW);
end;

{ ---- entering ---- }

procedure TApp.BeginEdit(replace: Boolean; const initial: UnicodeString);
begin
  if replace then EditBuf := initial else EditBuf := Sheet.GetRaw(CurC, CurR);
  EditPos := Length(EditBuf);
  Editing := True;
  SelActive := False;
  SelCols := False;
  FollowCursor := True;
end;

procedure TApp.EditInsert(const s: UnicodeString);
var
  t: UnicodeString;
  i: Integer;
begin
  t := s;
  for i := 1 to Length(t) do
    if (t[i] = #10) or (t[i] = #13) or (t[i] = #9) then t[i] := ' ';
  Insert(t, EditBuf, EditPos + 1);
  Inc(EditPos, Length(t));
end;

procedure TApp.CancelEdit;
begin
  Editing := False;
end;

procedure TApp.CommitEdit(dc, dr: Integer);
var
  before: UnicodeString;
  err: string;
begin
  if EditBuf = Sheet.GetRaw(CurC, CurR) then
  begin
    Editing := False;
    MoveCursor(CurC + dc, CurR + dr, False);
    Exit;
  end;
  before := Snapshot;
  err := Sheet.SetEntry(CurC, CurR, EditBuf);
  if err <> '' then
  begin
    SetMsg(UnicodeString(err), True);     { the text stays, to be put right }
    Exit;
  end;
  Editing := False;
  Changed(before);
  MoveCursor(CurC + dc, CurR + dr, False);
end;

procedure TApp.EditKey(const ev: TKeyEv);
var
  pc: PAnsiChar;
  t: UnicodeString;
  p: Integer;
  dir: Integer;
begin
  if ev.Shift then dir := -1 else dir := 1;
  if ev.Alt and (LetterOf(ev.Sym) = 'v') or (ev.Shift and (ev.Sym = SDLK_INSERT)) then
  begin
    pc := SDL_GetClipboardText();
    if pc <> nil then
    begin
      t := NormalizeLineEnds(UTF8Decode(string(pc)));
      SDL_free(pc);
      p := Pos(#10, string(t));
      if p > 0 then t := Copy(t, 1, p - 1);
      EditInsert(t);
    end;
    Exit;
  end;
  case ev.Sym of
    SDLK_ESCAPE: CancelEdit;
    SDLK_RETURN, SDLK_KP_ENTER: CommitEdit(0, dir);
    SDLK_TAB: CommitEdit(dir, 0);
    SDLK_UP: CommitEdit(0, -1);
    SDLK_DOWN: CommitEdit(0, 1);
    SDLK_LEFT:
      if ev.Ctrl then
      begin
        while (EditPos > 0) and (EditBuf[EditPos] = ' ') do Dec(EditPos);
        while (EditPos > 0) and (EditBuf[EditPos] <> ' ') do Dec(EditPos);
      end
      else if EditPos > 0 then Dec(EditPos);
    SDLK_RIGHT:
      if ev.Ctrl then
      begin
        while (EditPos < Length(EditBuf)) and (EditBuf[EditPos + 1] <> ' ') do Inc(EditPos);
        while (EditPos < Length(EditBuf)) and (EditBuf[EditPos + 1] = ' ') do Inc(EditPos);
      end
      else if EditPos < Length(EditBuf) then Inc(EditPos);
    SDLK_HOME: EditPos := 0;
    SDLK_END: EditPos := Length(EditBuf);
    SDLK_BACKSPACE:
      if EditPos > 0 then
      begin
        Delete(EditBuf, EditPos, 1);
        Dec(EditPos);
      end;
    SDLK_DELETE:
      if EditPos < Length(EditBuf) then Delete(EditBuf, EditPos + 1, 1);
  end;
end;

{ ---- the commands that work on the selected cells ---- }

procedure TApp.ClearSelection;
var
  c1, r1, c2, r2, lc, lr, c, r: Integer;
  before: UnicodeString;
begin
  SelRect(c1, r1, c2, r2);
  if not LastUsed(lc, lr) then Exit;
  if c2 > lc then c2 := lc;
  if r2 > lr then r2 := lr;
  before := Snapshot;
  for r := r1 to r2 do
    for c := c1 to c2 do Sheet.ClearCell(c, r);
  Changed(before);
end;

procedure TApp.ClipCopy(cut: Boolean);
var
  c1, r1, c2, r2, lc, lr, c, r, n: Integer;
  txt: UnicodeString;
  u: UTF8String;
  before: UnicodeString;
begin
  SelRect(c1, r1, c2, r2);
  if not LastUsed(lc, lr) then begin SetMsg('Nothing to copy'); Exit; end;
  if c2 > lc then c2 := lc;
  if r2 > lr then r2 := lr;
  if (c1 > c2) or (r1 > r2) then begin SetMsg('Nothing to copy'); Exit; end;
  ClipC := c1;
  ClipR := r1;
  ClipW := c2 - c1 + 1;
  ClipH := r2 - r1 + 1;
  SetLength(ClipCells, ClipW * ClipH);
  txt := '';
  n := 0;
  for r := r1 to r2 do
  begin
    for c := c1 to c2 do
    begin
      with ClipCells[(r - r1) * ClipW + (c - c1)] do
      begin
        Has := Sheet.Exists(c, r);
        if Has then
        begin
          Raw := Sheet.GetRaw(c, r);
          Fmt := Sheet.GetFormat(c, r);
          Inc(n);
        end
        else
        begin
          Raw := '';
          Fmt := GeneralFormat;
        end;
      end;
      if c > c1 then txt := txt + #9;
      txt := txt + CellPlainText(Sheet, c, r);
    end;
    txt := txt + #10;
  end;
  ClipText := txt;
  ClipValid := True;
  u := UTF8Encode(txt);
  SDL_SetClipboardText(PAnsiChar(u));
  if cut then
  begin
    before := Snapshot;
    for r := r1 to r2 do
      for c := c1 to c2 do Sheet.ClearCell(c, r);
    Changed(before);
    SetMsg(UnicodeString(Format('Cut %d cell(s)', [n])));
  end
  else
    SetMsg(UnicodeString(Format('Copied %d cell(s)', [n])));
end;

procedure TApp.ClipPaste;
var
  pc: PAnsiChar;
  txt: UnicodeString;
  before: UnicodeString;
  rows: TCsvRows;
  c1, r1, c2, r2, i, j, tc, tr, count: Integer;
  cell: TClipCell;
  raw, shifted: UnicodeString;
  err: string;
  fill: Boolean;
begin
  pc := SDL_GetClipboardText();
  if pc = nil then begin SetMsg('The clipboard is empty'); Exit; end;
  txt := NormalizeLineEnds(UTF8Decode(string(pc)));
  SDL_free(pc);
  if txt = '' then begin SetMsg('The clipboard is empty'); Exit; end;
  SelRect(c1, r1, c2, r2);
  before := Snapshot;
  count := 0;
  if ClipValid and (txt = ClipText) then
  begin
    { our own copy: formulas come with it, their references moved }
    fill := (ClipW = 1) and (ClipH = 1) and ((c2 > c1) or (r2 > r1));
    if not fill then begin c2 := c1 + ClipW - 1; r2 := r1 + ClipH - 1; end;
    for tr := r1 to r2 do
      for tc := c1 to c2 do
      begin
        if tc > MAX_COL then Continue;
        if tr > MAX_ROW then Continue;
        if fill then cell := ClipCells[0]
        else cell := ClipCells[(tr - r1) * ClipW + (tc - c1)];
        if not cell.Has then
        begin
          Sheet.ClearCell(tc, tr);
          Continue;
        end;
        raw := cell.Raw;
        if (Length(raw) > 1) and (raw[1] = '=') then
          if ShiftFormula(raw, c1 - ClipC + IfThenInt(fill, tc - c1, 0), r1 - ClipR + IfThenInt(fill, tr - r1, 0), shifted) then
            raw := shifted;
        err := Sheet.SetEntry(tc, tr, raw);
        if err = '' then
        begin
          Sheet.SetFormat(tc, tr, cell.Fmt);
          Inc(count);
        end;
      end;
  end
  else
  begin
    { text from elsewhere: tab-separated, typed in cell by cell }
    ParseCsv(txt, #9, rows);
    for j := 0 to High(rows) do
      for i := 0 to High(rows[j]) do
      begin
        tc := c1 + i;
        tr := r1 + j;
        if (tc > MAX_COL) or (tr > MAX_ROW) then Continue;
        err := Sheet.SetEntry(tc, tr, rows[j][i]);
        if err <> '' then err := Sheet.SetEntry(tc, tr, '''' + rows[j][i]);
        Inc(count);
      end;
    c2 := c1;
    r2 := r1;
    if Length(rows) > 0 then
    begin
      r2 := r1 + High(rows);
      for j := 0 to High(rows) do
        if c1 + High(rows[j]) > c2 then c2 := c1 + High(rows[j]);
    end;
  end;
  Changed(before);
  if (c2 > c1) or (r2 > r1) then
  begin
    AnchorC := c1;
    AnchorR := r1;
    CurC := c2;
    CurR := r2;
    SelActive := True;
    SelCols := False;
  end;
  FollowCursor := True;
  SetMsg(UnicodeString(Format('Pasted %d cell(s)', [count])));
end;

procedure TApp.FillDown;
var
  c1, r1, c2, r2, c, r, src: Integer;
  before, err: string;
  e: string;
begin
  SelRect(c1, r1, c2, r2);
  if r1 = r2 then
  begin
    if r1 = 0 then begin SetMsg('There is no row above to fill from'); Exit; end;
    src := r1 - 1;
  end
  else
  begin
    src := r1;
    Inc(r1);
  end;
  before := string(Snapshot);
  err := '';
  for c := c1 to c2 do
    for r := r1 to r2 do
    begin
      e := Sheet.CopyCell(c, src, c, r);
      if e <> '' then err := e;
    end;
  Changed(UnicodeString(before));
  if err <> '' then SetMsg(UnicodeString(err), True) else SetMsg('Filled down');
end;

procedure TApp.FillRight;
var
  c1, r1, c2, r2, c, r, src: Integer;
  before, err, e: string;
begin
  SelRect(c1, r1, c2, r2);
  if c1 = c2 then
  begin
    if c1 = 0 then begin SetMsg('There is no column to the left to fill from'); Exit; end;
    src := c1 - 1;
  end
  else
  begin
    src := c1;
    Inc(c1);
  end;
  before := string(Snapshot);
  err := '';
  for r := r1 to r2 do
    for c := c1 to c2 do
    begin
      e := Sheet.CopyCell(src, r, c, r);
      if e <> '' then err := e;
    end;
  Changed(UnicodeString(before));
  if err <> '' then SetMsg(UnicodeString(err), True) else SetMsg('Filled right');
end;

{ ---- one key or event ---- }

procedure TApp.HandleKey(const ev: TKeyEv);
var
  ch: Char;
  lc, lr, dir: Integer;
begin
  if Editing then begin EditKey(ev); Exit; end;
  ch := LetterOf(ev.Sym);
  if ev.Shift then dir := -1 else dir := 1;
  case ev.Sym of
    SDLK_F1: begin DoHelp; Exit; end;
    SDLK_F2: begin BeginEdit(False, ''); Exit; end;
    SDLK_F3: begin DoWidth; Exit; end;
    SDLK_F4: begin DoFormat; Exit; end;
    SDLK_F5: begin SetMsg('Sorting is not built yet'); Exit; end;
    SDLK_F9: begin SetMsg('Screen options are not built yet'); Exit; end;
  end;
  if ev.Alt then
  begin
    case ch of
      'c': ClipCopy(False);
      'x': ClipCopy(True);
      'v': ClipPaste;
      'a': SelectAll;
    end;
    Exit;
  end;
  if ev.Ctrl then
  begin
    case ev.Sym of
      SDLK_UP: begin JumpCursor(0, -1, ev.Shift); Exit; end;
      SDLK_DOWN: begin JumpCursor(0, 1, ev.Shift); Exit; end;
      SDLK_LEFT: begin JumpCursor(-1, 0, ev.Shift); Exit; end;
      SDLK_RIGHT: begin JumpCursor(1, 0, ev.Shift); Exit; end;
      SDLK_HOME: begin MoveCursor(0, 0, ev.Shift); Exit; end;
      SDLK_END:
        begin
          if LastUsed(lc, lr) then MoveCursor(lc, lr, ev.Shift);
          Exit;
        end;
      SDLK_INSERT: begin ClipCopy(False); Exit; end;
      SDLK_SPACE: begin SelectColumn; Exit; end;
      SDLK_KP_PLUS: begin SetMsg('Inserting rows and columns is not built yet'); Exit; end;
      SDLK_KP_MINUS: begin SetMsg('Deleting rows and columns is not built yet'); Exit; end;
      Ord('='), Ord('-'): begin SetMsg('Inserting and deleting rows and columns is not built yet'); Exit; end;
    end;
    case ch of
      's': DoSave(ev.Shift);
      'l': DoLoad;
      'z': if ev.Shift then DoRedo else DoUndo;
      'y': DoRedo;
      'f': DoFind(True);
      'h': DoFind(False);
      'e': ClearSelection;
      'd': FillDown;
      'r': FillRight;
      'g': DoGoto;
      'v': SetMsg('The print preview is not built yet');
      'o': SetMsg('Output (PDF and text) is not built yet');
      'x': if ev.Shift then TryQuit;
    end;
    Exit;
  end;
  case ev.Sym of
    SDLK_UP: MoveCursor(CurC, CurR - 1, ev.Shift);
    SDLK_DOWN: MoveCursor(CurC, CurR + 1, ev.Shift);
    SDLK_LEFT: MoveCursor(CurC - 1, CurR, ev.Shift);
    SDLK_RIGHT: MoveCursor(CurC + 1, CurR, ev.Shift);
    SDLK_PAGEUP: MoveCursor(CurC, CurR - VisRows, ev.Shift);
    SDLK_PAGEDOWN: MoveCursor(CurC, CurR + VisRows, ev.Shift);
    SDLK_HOME: MoveCursor(0, CurR, ev.Shift);
    SDLK_END:
      begin
        if LastUsed(lc, lr) then MoveCursor(lc, CurR, ev.Shift);
      end;
    SDLK_TAB: MoveCursor(CurC + dir, CurR, False);
    SDLK_RETURN, SDLK_KP_ENTER: MoveCursor(CurC, CurR + dir, False);
    SDLK_DELETE: if ev.Shift then ClipCopy(True) else ClearSelection;
    SDLK_BACKSPACE: ClearSelection;
    SDLK_INSERT: if ev.Shift then ClipPaste;
    SDLK_ESCAPE:
      begin
        SelActive := False;
        SelCols := False;
      end;
  end;
end;

procedure TApp.HandleEvent(var ev: TKeyEv);
var
  c, r: Integer;
begin
  case ev.Kind of
    ekKey:
      begin
        Msg := '';
        FollowCursor := True;
        if ev.Sym = SYM_CTRLTAP then
        begin
          CtrlMode := not CtrlMode;
          Exit;
        end;
        if CtrlMode then
        begin
          CtrlMode := False;
          if ev.Sym = SDLK_ESCAPE then Exit;
          ev.Ctrl := True;
          SwallowText := True;
          SwallowUntil := SDL_GetTicks() + 400;
        end;
        HandleKey(ev);
      end;
    ekText:
      begin
        Msg := '';
        FollowCursor := True;
        if CtrlMode then Exit;
        if Editing then EditInsert(ev.Text) else BeginEdit(True, ev.Text);
      end;
    ekWheel:
      begin
        if ev.Ctrl then
        begin
          Gfx.SetFontSize(Gfx.FontPx + ev.Wheel * 2);
          Cfg.FontSize := Gfx.FontPx;
        end
        else
        begin
          FollowCursor := False;
          TopRow := TopRow - ev.Wheel * 3;
          if TopRow < 0 then TopRow := 0;
        end;
      end;
    ekClick:
      if CellAt(ev.X, ev.Y, c, r) then
      begin
        if Editing then
        begin
          CommitEdit(0, 0);
          if Editing then Exit;
        end;
        FollowCursor := True;
        if ev.Shift then MoveCursor(c, r, True)
        else
        begin
          MoveCursor(c, r, False);
          if ev.Clicks >= 2 then BeginEdit(False, '');
        end;
      end;
    ekDrag:
      if (not Editing) and CellAt(ev.X, ev.Y, c, r) and ((c <> CurC) or (r <> CurR)) then
        MoveCursor(c, r, True);
  end;
end;
