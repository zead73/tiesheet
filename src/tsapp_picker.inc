{ tsapp_picker.inc - the file picker (included by tsapp.pas)

  One pane in the Far style, like tiepick: the folder's files, an edit line at the bottom where typing
  goes, and the keys Enter, Backspace, Tab (filter), F2 (places), F7 (new folder), F10 (accept),
  Ctrl+H (hidden files) and Esc. }

procedure TApp.PkLoad(const dir, focus: string);
var
  entries: TDirEntries;
  i: Integer;
  pats: string;
begin
  pats := '*';
  if (PkFilter >= 0) and (PkFilter < PkFilterPats.Count) then pats := PkFilterPats[PkFilter];
  if not ListDir(dir, PkHidden, pats, entries) then
  begin
    SetMsg(UnicodeString('Cannot read ' + dir), True);
    Exit;
  end;
  PkEntries := entries;
  PkDir := ExcludeTrailingPathDelimiter(ExpandFileName(dir));
  if PkDir = '' then PkDir := PathDelim;
  PkSel := 0;
  PkTop := 0;
  if focus <> '' then
    for i := 0 to High(PkEntries) do
      if PkEntries[i].Name = focus then
      begin
        PkSel := i;
        Break;
      end;
  PkNavigated := False;
end;

procedure TApp.DrawPicker;
var
  textC, backC, dimC, dirC, fg, bg: LongWord;
  i, k, rows, nameW, sizeW, timeW, x, curCol, avail, scroll, w: Integer;
  e: TDirEntry;
  nm, sz, shown, label_, title: UnicodeString;
const
  Dim = 12;
begin
  textC := RGBOf(Cfg.ColText);
  backC := RGBOf(Cfg.ColBack);
  dimC := RGBOf(Cfg.ColHeader);
  dirC := RGBOf(Cfg.ColFormula);
  sizeW := 10;
  timeW := 16;
  nameW := Gfx.Cols - 2 - sizeW - timeW - 2;
  if nameW < 10 then nameW := 10;
  rows := Gfx.Rows - 5;
  if rows < 1 then rows := 1;
  if PkSel >= Length(PkEntries) then PkSel := Length(PkEntries) - 1;
  if PkSel < 0 then PkSel := 0;
  if PkSel < PkTop then PkTop := PkSel;
  if PkSel >= PkTop + rows then PkTop := PkSel - rows + 1;

  Gfx.FillCells(0, 0, Gfx.Cols, 1, textC);
  title := UnicodeString(' ' + PkTitle + ' - ') + UTF8Decode(PkDir);
  if Length(title) > Gfx.Cols - 24 then title := ' ...' + Copy(title, Length(title) - (Gfx.Cols - 30), MaxInt);
  Gfx.PutText(0, 0, title, backC, ST_BOLD);
  if (PkFilter >= 0) and (PkFilter < PkFilterNames.Count) then
  begin
    shown := UTF8Decode(PkFilterNames[PkFilter]);
    Gfx.PutText(Gfx.Cols - Length(shown) - 1, 0, shown, backC, ST_REGULAR);
  end;
  if Msg <> '' then
  begin
    Gfx.FillCells(0, 1, Gfx.Cols, 1, RGBOf(2));
    Gfx.PutText(1, 1, Msg, RGBOf(1), ST_BOLD);
  end
  else
    if Gfx.Cols >= 100 then
      Gfx.PutText(1, 1, 'Enter opens   Backspace up   Tab filter   F2 places   F7 new folder   Ctrl+H hidden   Esc cancels', dimC)
    else
      Gfx.PutText(1, 1, 'Enter open  Bksp up  Tab filter  F2 places  F7 folder  ^H hidden  Esc quit', dimC);

  Gfx.FillCells(0, 2, Gfx.Cols, 1, dimC);
  Gfx.PutText(1, 2, 'Name', backC, ST_BOLD);
  Gfx.PutText(1 + nameW + sizeW - 3, 2, 'Size', backC, ST_BOLD);
  Gfx.PutText(1 + nameW + sizeW + 2, 2, 'Modified', backC, ST_BOLD);
  for i := 0 to rows - 1 do
  begin
    k := PkTop + i;
    if k >= Length(PkEntries) then Break;
    e := PkEntries[k];
    fg := textC;
    if e.IsDir then fg := dirC;
    bg := backC;
    if k = PkSel then begin fg := backC; bg := textC; Gfx.FillCells(0, 3 + i, Gfx.Cols, 1, bg); end;
    nm := UTF8Decode(e.Name);
    if e.IsDir and (not e.IsUp) then nm := nm + '/';
    if Length(nm) > nameW then nm := Copy(nm, 1, nameW - 1) + '~';
    if e.IsDir then Gfx.PutText(1, 3 + i, nm, fg, ST_BOLD) else Gfx.PutText(1, 3 + i, nm, fg, ST_REGULAR);
    if e.IsUp then sz := '<UP--DIR>'
    else if e.IsDir then sz := '<DIR>'
    else sz := UnicodeString(FmtSize(e.Size));
    Gfx.PutText(1 + nameW + sizeW - Length(sz), 3 + i, sz, fg);
    if (not e.IsUp) and (e.MTime > 0) then
      Gfx.PutText(1 + nameW + sizeW + 2, 3 + i, UnicodeString(FormatDateTime('yyyy-mm-dd hh:nn', e.MTime)), fg);
  end;

  { the edit line: typing goes here }
  Gfx.FillCells(0, Gfx.Rows - 2, Gfx.Cols, 1, textC);
  if PkMode = pmSave then label_ := 'Name: ' else label_ := 'Go to / name: ';
  Gfx.PutText(0, Gfx.Rows - 2, label_, backC, ST_BOLD);
  x := Length(label_);
  avail := Gfx.Cols - x - 1;
  scroll := 0;
  if PkPos >= avail then scroll := PkPos - avail + 1;
  shown := Copy(PkEdit, scroll + 1, avail);
  if PkFresh and (shown <> '') then
  begin
    Gfx.FillCells(x, Gfx.Rows - 2, Length(shown), 1, backC);
    Gfx.PutText(x, Gfx.Rows - 2, shown, textC);
  end
  else
    Gfx.PutText(x, Gfx.Rows - 2, shown, backC);
  curCol := x + PkPos - scroll;
  if BlinkOn and (curCol < Gfx.Cols) then
  begin
    Gfx.FillCells(curCol, Gfx.Rows - 2, 1, 1, backC);
    if PkPos < Length(PkEdit) then Gfx.PutChar(curCol, Gfx.Rows - 2, PkEdit[PkPos + 1], ST_REGULAR, textC);
  end;
  w := Dim;
  Gfx.FillCells(0, Gfx.Rows - 1, Gfx.Cols, 1, dimC);
  if PkMode = pmSave then label_ := 'F10 Save here' else label_ := 'F10 Open';
  Gfx.PutText(1, Gfx.Rows - 1, UnicodeString(Format('%d item(s)', [Length(PkEntries)])) + '   ' + label_, backC, ST_BOLD);
  if PkHidden then Gfx.PutText(Gfx.Cols - 9, Gfx.Rows - 1, 'hidden on', backC, ST_REGULAR);
end;

procedure TApp.DrawPlaces;
var
  textC, backC, dimC, fg, bg: LongWord;
  i: Integer;
  s: UnicodeString;
begin
  textC := RGBOf(Cfg.ColText);
  backC := RGBOf(Cfg.ColBack);
  dimC := RGBOf(Cfg.ColHeader);
  Gfx.FillCells(0, 0, Gfx.Cols, 1, textC);
  Gfx.PutText(0, 0, ' Places', backC, ST_BOLD);
  Gfx.PutText(1, 1, 'Up/Down choose   Enter goes there   Esc returns', dimC);
  for i := 0 to High(PkPlaces) do
  begin
    if 3 + i >= Gfx.Rows - 1 then Break;
    fg := textC;
    bg := backC;
    if i = PkPlaceSel then begin fg := backC; bg := textC; Gfx.FillCells(0, 3 + i, Gfx.Cols, 1, bg); end;
    s := UTF8Decode(PkPlaces[i].Caption);
    Gfx.PutText(1, 3 + i, s, fg, ST_BOLD);
    Gfx.PutText(12, 3 + i, UTF8Decode(PkPlaces[i].Path), fg);
  end;
end;

{ F2: home, the top, mounted drives, bookmarks }
function TApp.PkPlacesScreen: Boolean;
var
  ev: TKeyEv;
  saved: TProc;
begin
  Result := False;
  PkPlaces := GetPlaces;
  if Length(PkPlaces) = 0 then Exit;
  PkPlaceSel := 0;
  saved := FullScreen;
  FullScreen := @DrawPlaces;
  try
    while WaitKey(ev) do
    begin
      if ev.Kind = ekKey then
        case ev.Sym of
          SDLK_ESCAPE: Exit(False);
          SDLK_UP: if PkPlaceSel > 0 then Dec(PkPlaceSel);
          SDLK_DOWN: if PkPlaceSel < High(PkPlaces) then Inc(PkPlaceSel);
          SDLK_HOME: PkPlaceSel := 0;
          SDLK_END: PkPlaceSel := High(PkPlaces);
          SDLK_RETURN, SDLK_KP_ENTER:
            begin
              PkLoad(PkPlaces[PkPlaceSel].Path, '');
              Exit(True);
            end;
        end;
    end;
  finally
    FullScreen := saved;
  end;
end;

procedure TApp.PkMakeDir;
var
  v: UnicodeString;
  name, full: string;
begin
  v := '';
  if not Prompt('New folder:', v) then Exit;
  name := Trim(UTF8Encode(v));
  if name = '' then Exit;
  full := IncludeTrailingPathDelimiter(PkDir) + name;
  if CreateDir(full) then
    PkLoad(PkDir, name)
  else
    SetMsg(UnicodeString('Cannot make the folder ' + name), True);
end;

{ Enter: what was typed if there is something, else the highlighted entry }
procedure TApp.PkEnter(var finished, ok: Boolean; out path: string);
var
  txt, p, parentName: string;
  e: TDirEntry;
begin
  path := '';
  txt := Trim(UTF8Encode(PkEdit));
  if (Length(PkEntries) > 0) and (PkSel < Length(PkEntries)) then e := PkEntries[PkSel] else e := Default(TDirEntry);
  { a name is waiting to be saved and the highlight is on a folder the user moved to: open it, keep the name }
  if (txt <> '') and (PkMode = pmSave) and PkNavigated and e.IsDir then
  begin
    if e.IsUp then begin parentName := ExtractFileName(PkDir); PkLoad(ParentDir(PkDir), parentName); end
    else PkLoad(IncludeTrailingPathDelimiter(PkDir) + e.Name, '');
    Exit;
  end;
  if txt <> '' then
  begin
    p := ResolvePath(PkDir, txt);
    if DirectoryExists(p) then
    begin
      PkLoad(p, '');
      PkEdit := '';
      PkPos := 0;
      Exit;
    end;
    if PkMode = pmOpen then
    begin
      if FileExists(p) then begin path := p; ok := True; finished := True; end
      else if (not e.IsUp) and (e.Name <> '') and (Copy(LowerCase(e.Name), 1, Length(txt)) = LowerCase(txt)) then
      begin
        { what was typed is the start of the highlighted name: that is the one meant }
        PkEdit := '';
        PkPos := 0;
        if e.IsDir then PkLoad(IncludeTrailingPathDelimiter(PkDir) + e.Name, '')
        else begin path := IncludeTrailingPathDelimiter(PkDir) + e.Name; ok := True; finished := True; end;
      end
      else SetMsg(UnicodeString('No such file: ' + txt), True);
    end
    else
    begin
      if DirectoryExists(ExtractFilePath(p)) or (ExtractFilePath(p) = '') then begin path := p; ok := True; finished := True; end
      else SetMsg(UnicodeString('There is no folder ' + ExtractFilePath(p)), True);
    end;
    Exit;
  end;
  if Length(PkEntries) = 0 then Exit;
  if e.IsUp then
  begin
    parentName := ExtractFileName(PkDir);
    PkLoad(ParentDir(PkDir), parentName);
  end
  else if e.IsDir then PkLoad(IncludeTrailingPathDelimiter(PkDir) + e.Name, '')
  else
  begin
    path := IncludeTrailingPathDelimiter(PkDir) + e.Name;
    ok := True;
    finished := True;
  end;
end;

{ filters: pairs "Name|*.a;*.b".  Returns the chosen path. }
function TApp.PickFile(mode: TPickMode; const title, startDir, startName: string; const filters: array of string;
  filterIndex: Integer; out path: string): Boolean;
var
  ev: TKeyEv;
  fin, ok, wasCtrl: Boolean;
  i, p, rows: Integer;
  dir, prefix, parentName: string;
  saved: TProc;
  savedFull: TProc;
  txt: UnicodeString;
begin
  Result := False;
  path := '';
  PkMode := mode;
  PkTitle := title;
  PkFilterNames.Clear;
  PkFilterPats.Clear;
  for i := 0 to High(filters) do
  begin
    p := Pos('|', filters[i]);
    PkFilterNames.Add(Copy(filters[i], 1, p - 1));
    PkFilterPats.Add(Copy(filters[i], p + 1, MaxInt));
  end;
  PkFilter := filterIndex;
  if (PkFilter < 0) or (PkFilter >= PkFilterPats.Count) then PkFilter := 0;
  PkHidden := False;
  PkEdit := UTF8Decode(startName);
  PkPos := Length(PkEdit);
  PkFresh := PkEdit <> '';
  dir := startDir;
  if (dir = '') or (not DirectoryExists(dir)) then dir := GetCurrentDir;
  if not DirectoryExists(dir) then dir := UserHome;
  PkLoad(dir, '');
  PkNavigated := False;
  savedFull := FullScreen;
  FullScreen := @DrawPicker;
  fin := False;
  ok := False;
  try
    while (not fin) and WaitKey(ev) do
    begin
      rows := Gfx.Rows - 5;
      Msg := '';
      case ev.Kind of
        ekKey:
          begin
            if ev.Sym = SYM_CTRLTAP then begin CtrlMode := not CtrlMode; Continue; end;
            wasCtrl := ev.Ctrl;
            if CtrlMode then
            begin
              CtrlMode := False;
              if ev.Sym = SDLK_ESCAPE then Continue;
              wasCtrl := True;
              SwallowText := True;
              SwallowUntil := SDL_GetTicks() + 400;
            end;
            if wasCtrl then
            begin
              if LetterOf(ev.Sym) = 'h' then
              begin
                PkHidden := not PkHidden;
                if (PkSel >= 0) and (PkSel < Length(PkEntries)) then parentName := PkEntries[PkSel].Name else parentName := '';
                PkLoad(PkDir, parentName);
              end;
            end
            else
              case ev.Sym of
                SDLK_ESCAPE:
                  if PkEdit <> '' then begin PkEdit := ''; PkPos := 0; PkFresh := False; end
                  else Break;
                SDLK_UP: begin if PkSel > 0 then Dec(PkSel); PkNavigated := True; end;
                SDLK_DOWN: begin if PkSel < High(PkEntries) then Inc(PkSel); PkNavigated := True; end;
                SDLK_PAGEUP: begin Dec(PkSel, rows - 1); if PkSel < 0 then PkSel := 0; PkNavigated := True; end;
                SDLK_PAGEDOWN:
                  begin
                    Inc(PkSel, rows - 1);
                    if PkSel > High(PkEntries) then PkSel := High(PkEntries);
                    if PkSel < 0 then PkSel := 0;
                    PkNavigated := True;
                  end;
                SDLK_HOME:
                  if PkEdit = '' then begin PkSel := 0; PkNavigated := True; end else begin PkPos := 0; PkFresh := False; end;
                SDLK_END:
                  if PkEdit = '' then begin PkSel := High(PkEntries); if PkSel < 0 then PkSel := 0; PkNavigated := True; end
                  else begin PkPos := Length(PkEdit); PkFresh := False; end;
                SDLK_LEFT:
                  if PkEdit = '' then begin PkSel := 0; PkNavigated := True; end
                  else begin if PkPos > 0 then Dec(PkPos); PkFresh := False; end;
                SDLK_RIGHT:
                  begin
                    if PkPos < Length(PkEdit) then Inc(PkPos);
                    PkFresh := False;
                  end;
                SDLK_BACKSPACE:
                  if PkFresh then begin PkEdit := ''; PkPos := 0; PkFresh := False; end
                  else if PkEdit = '' then
                  begin
                    parentName := ExtractFileName(PkDir);
                    PkLoad(ParentDir(PkDir), parentName);
                  end
                  else if PkPos > 0 then begin Delete(PkEdit, PkPos, 1); Dec(PkPos); end;
                SDLK_DELETE:
                  if PkFresh then begin PkEdit := ''; PkPos := 0; PkFresh := False; end
                  else if PkPos < Length(PkEdit) then Delete(PkEdit, PkPos + 1, 1);
                SDLK_TAB:
                  begin
                    if PkFilterPats.Count > 0 then PkFilter := (PkFilter + 1) mod PkFilterPats.Count;
                    if (PkSel >= 0) and (PkSel < Length(PkEntries)) then parentName := PkEntries[PkSel].Name else parentName := '';
                    PkLoad(PkDir, parentName);
                  end;
                SDLK_F2: PkPlacesScreen;
                SDLK_F7: PkMakeDir;
                SDLK_F10:
                  begin
                    if PkMode = pmSave then
                    begin
                      txt := PkEdit;
                      if Trim(string(txt)) = '' then SetMsg('Type a name to save under', True)
                      else
                      begin
                        path := ResolvePath(PkDir, Trim(UTF8Encode(txt)));
                        ok := True;
                        fin := True;
                      end;
                    end
                    else
                    begin
                      PkEnter(fin, ok, path);
                    end;
                  end;
                SDLK_RETURN, SDLK_KP_ENTER: PkEnter(fin, ok, path);
              end;
          end;
        ekText:
          begin
            if CtrlMode then Continue;
            if PkFresh then begin PkEdit := ''; PkPos := 0; PkFresh := False; end;
            txt := ev.Text;
            for i := 1 to Length(txt) do
              if (txt[i] = #10) or (txt[i] = #13) or (txt[i] = #9) then txt[i] := ' ';
            Insert(txt, PkEdit, PkPos + 1);
            Inc(PkPos, Length(txt));
            PkNavigated := False;
            { choosing a file: typing jumps to the first name that starts with it }
            if (PkMode = pmOpen) and (Pos('/', string(PkEdit)) = 0) and (Pos('\', string(PkEdit)) = 0) then
            begin
              prefix := LowerCase(UTF8Encode(PkEdit));
              for i := 0 to High(PkEntries) do
                if (not PkEntries[i].IsUp) and (Copy(LowerCase(PkEntries[i].Name), 1, Length(prefix)) = prefix) then
                begin
                  PkSel := i;
                  Break;
                end;
            end;
          end;
        ekWheel:
          begin
            Dec(PkSel, ev.Wheel * 3);
            if PkSel > High(PkEntries) then PkSel := High(PkEntries);
            if PkSel < 0 then PkSel := 0;
          end;
        ekClick:
          begin
            i := (ev.Y - Gfx.Border) div Gfx.CellH - 3 + PkTop;
            if (i >= 0) and (i < Length(PkEntries)) and ((ev.Y - Gfx.Border) div Gfx.CellH >= 3) then
            begin
              PkSel := i;
              PkNavigated := True;
              if ev.Clicks >= 2 then
              begin
                txt := PkEdit;
                PkEdit := '';
                PkEnter(fin, ok, path);
                if not fin then PkEdit := txt;
              end;
            end;
          end;
      end;
    end;
  finally
    FullScreen := savedFull;
  end;
  if ok then
  begin
    Cfg.LastDir := IncludeTrailingPathDelimiter(ExtractFilePath(path));
    if (PkMode = pmOpen) or (Cfg.LastDir = '') then Cfg.LastDir := IncludeTrailingPathDelimiter(PkDir);
  end;
  Result := ok;
end;
