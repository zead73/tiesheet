{ tsapp_files.inc - starting, loading, saving and quitting (included by tsapp.pas) }

function ExpandHome(const fn: string): string;
begin
  Result := fn;
  if (Length(fn) >= 2) and (fn[1] = '~') and ((fn[2] = '/') or (fn[2] = '\')) then
    Result := IncludeTrailingPathDelimiter(GetUserDir) + Copy(fn, 3, MaxInt);
end;

function TApp.Start(const initialFile: string): string;
begin
  ConfigPath := ConfigFile('tiesheet.ini');
  LoadSettings(Cfg, ConfigPath);
  Result := Gfx.Init('TieSheet', Cfg);
  if Result <> '' then Exit;
  Sheet.Today := TodaySerial;
  if initialFile <> '' then LoadPath(initialFile);
end;

procedure TApp.SaveConfig;
var
  w, h: LongInt;
begin
  SDL_GetWindowSize(Gfx.Window, w, h);
  if (w >= 400) and (h >= 300) then
  begin
    Cfg.WinW := w;
    Cfg.WinH := h;
  end;
  try
    SaveSettings(Cfg, ConfigPath);
  except
    { settings that cannot be saved are not worth stopping for }
  end;
end;

procedure TApp.Run;
var
  ev: TKeyEv;
begin
  while not Done do
  begin
    if WaitKey(ev) then HandleEvent(ev)
    else if QuitReq then
    begin
      QuitReq := False;
      TryQuit;
    end;
  end;
  SaveConfig;
end;

procedure TApp.ResetDocument;
begin
  Sheet.Clear;
  CurC := 0;
  CurR := 0;
  TopRow := 0;
  LeftCol := 0;
  SelActive := False;
  SelCols := False;
  Editing := False;
  SetLength(UndoStack, 0);
  SetLength(RedoStack, 0);
  UndoBytes := 0;
  Dirty := False;
end;

function TApp.LoadPath(const fn: string): Boolean;
var
  text: UnicodeString;
  err, path: string;
  warn: TStringList;
  n: Integer;
  old: UnicodeString;
begin
  Result := False;
  path := ExpandHome(fn);
  err := ReadTextFile(path, text);
  if err <> '' then
  begin
    SetMsg(UnicodeString(err), True);
    Exit;
  end;
  warn := TStringList.Create;
  try
    old := Snapshot;
    ResetDocument;
    if Copy(text, 1, 9) = 'tiesheet ' then
    begin
      err := SheetFromText(Sheet, text, warn);
      if err <> '' then
      begin
        SheetFromText(Sheet, old, nil);
        SetMsg(UnicodeString(err), True);
        Exit;
      end;
      FileKind := fkTsh;
      n := Sheet.CellCount;
    end
    else
    begin
      n := ImportCsv(Sheet, text, warn);
      FileKind := fkCsv;
      CsvValues := False;
    end;
    FileName := ExpandFileName(path);
    Cfg.LastDir := ExtractFilePath(FileName);
    if warn.Count > 0 then
      SetMsg(UnicodeString(Format('Loaded %s (%d cells); %s', [ExtractFileName(FileName), n, warn[0]])), True)
    else
      SetMsg(UnicodeString(Format('Loaded %s (%d cells)', [ExtractFileName(FileName), n])));
    Result := True;
  finally
    warn.Free;
  end;
end;

function TApp.ConfirmDiscard: Boolean;
var
  k: Integer;
begin
  Result := True;
  if not Dirty then Exit;
  k := AskChoice('Save the changes first?  (Y)es  (N)o  Esc cancels', 'YN');
  case k of
    0: Result := DoSave(False);
    1: Result := True;
  else
    Result := False;
  end;
end;

procedure TApp.DoLoad;
var
  v: UnicodeString;
begin
  if not ConfirmDiscard then Exit;
  if FileName <> '' then v := UTF8Decode(FileName) else v := UTF8Decode(Cfg.LastDir);
  if not Prompt('Load file:', v, True) then Exit;
  v := UnicodeString(Trim(string(v)));
  if v = '' then Exit;
  LoadPath(UTF8Encode(v));
end;

function TApp.DoSave(askName: Boolean): Boolean;
var
  v: UnicodeString;
  fn, err, note: string;
  kind: TFileKind;
  vals: Boolean;
  k: Integer;
begin
  Result := False;
  fn := FileName;
  kind := FileKind;
  vals := CsvValues;
  if (fn = '') or askName then
  begin
    if fn <> '' then v := UTF8Decode(fn) else v := UTF8Decode(Cfg.LastDir + 'sheet.tsh');
    if not Prompt('Save as:', v, True) then Exit;
    v := UnicodeString(Trim(string(v)));
    if v = '' then Exit;
    fn := ExpandHome(UTF8Encode(v));
    if ExtractFileExt(fn) = '' then fn := fn + '.tsh';
    if LowerCase(ExtractFileExt(fn)) = '.csv' then
    begin
      kind := fkCsv;
      k := AskChoice('A CSV for sharing:  (F)ormulas as typed  (V)alues only', 'FV');
      if k < 0 then Exit;
      vals := k = 1;
    end
    else
      kind := fkTsh;
  end;
  note := '';
  if kind = fkCsv then
    err := WriteTextFile(fn, ExportCsv(Sheet, vals))
  else
    err := SaveSheetFile(Sheet, fn);
  if err <> '' then
  begin
    SetMsg(UnicodeString(err), True);
    Exit;
  end;
  FileName := ExpandFileName(fn);
  FileKind := kind;
  CsvValues := vals;
  Cfg.LastDir := ExtractFilePath(FileName);
  Dirty := False;
  if kind = fkCsv then
    note := IfThenStr(vals, ' (values only; widths and formats are not kept)', ' (formulas as typed; widths and formats are not kept)');
  SetMsg(UnicodeString('Saved ' + ExtractFileName(FileName) + note));
  Result := True;
end;

procedure TApp.TryQuit;
begin
  if ConfirmDiscard then Done := True;
end;
