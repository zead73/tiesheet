{ tsapp_input.inc - events, the Ctrl tap, scripted input and prompts (included by tsapp.pas) }

function IsModifierSym(sym: LongInt): Boolean;
begin
  Result := ((sym >= 1073742048) and (sym <= 1073742055)) or (sym = 1073741881) or
            (sym = 1073741907) or (sym = 1073742081);
end;

function TApp.Translate(var e: TSDL_Event; var ev: TKeyEv): Boolean;
var
  sym, md: LongInt;
begin
  Result := False;
  ev := Default(TKeyEv);
  case e.typ of
    SDL_QUITEV:
      begin
        ev.Kind := ekQuit;
        Result := True;
      end;
    SDL_WINDOWEVENT:
      case EvWinEvent(e) of
        SDL_WINDOWEVENT_SIZE_CHANGED, SDL_WINDOWEVENT_RESIZED:
          begin
            Gfx.Resized;
            ev.Kind := ekResize;
            Result := True;
          end;
        SDL_WINDOWEVENT_EXPOSED:
          begin
            ev.Kind := ekResize;
            Result := True;
          end;
        SDL_WINDOWEVENT_CLOSE:
          begin
            ev.Kind := ekQuit;
            Result := True;
          end;
      end;
    SDL_KEYDOWN:
      begin
        sym := EvKeySym(e);
        md := EvKeyMod(e);
        if (sym = SDLK_LCTRL) or (sym = SDLK_RCTRL) then
        begin
          if not CtrlHeld then CtrlTapOK := True;
          CtrlHeld := True;
          Exit;
        end;
        if IsModifierSym(sym) then Exit;
        CtrlTapOK := False;
        ev.Kind := ekKey;
        ev.Sym := sym;
        ev.Ctrl := (md and KMOD_CTRL) <> 0;
        ev.Shift := (md and KMOD_SHIFT) <> 0;
        ev.Alt := (md and KMOD_ALT) <> 0;
        Result := True;
      end;
    SDL_KEYUP:
      begin
        sym := EvKeySym(e);
        if (sym = SDLK_LCTRL) or (sym = SDLK_RCTRL) then
        begin
          CtrlHeld := False;
          if CtrlTapOK then
          begin
            ev.Kind := ekKey;
            ev.Sym := SYM_CTRLTAP;
            Result := True;
          end;
          CtrlTapOK := False;
        end;
      end;
    SDL_TEXTINPUT:
      begin
        if SwallowText then
        begin
          SwallowText := False;
          if SDL_GetTicks() < SwallowUntil then Exit;
        end;
        ev.Kind := ekText;
        ev.Text := EvText(e);
        Result := Length(ev.Text) > 0;
      end;
    SDL_RENDER_TARGETS_RESET, SDL_RENDER_DEVICE_RESET:
      begin
        Gfx.ForgetGlyphs;
        ev.Kind := ekResize;
        Result := True;
      end;
    SDL_MOUSEWHEEL:
      begin
        CtrlTapOK := False;
        ev.Kind := ekWheel;
        ev.Wheel := EvWheelY(e);
        ev.Ctrl := (SDL_GetModState() and KMOD_CTRL) <> 0;
        Result := True;
      end;
    SDL_MOUSEBUTTONDOWN:
      begin
        CtrlTapOK := False;
        if EvButton(e) = 1 then
        begin
          ev.Kind := ekClick;
          ev.X := EvButtonX(e);
          ev.Y := EvButtonY(e);
          ev.Clicks := e.raw[18];
          ev.Shift := (SDL_GetModState() and KMOD_SHIFT) <> 0;
          Result := True;
        end;
      end;
    SDL_MOUSEBUTTONUP:
      if EvButton(e) = 1 then
      begin
        ev.Kind := ekRelease;
        Result := True;
      end;
    SDL_MOUSEMOTION:
      if (EvMotionState(e) and 1) <> 0 then
      begin
        ev.Kind := ekDrag;
        ev.X := EvMotionX(e);
        ev.Y := EvMotionY(e);
        Result := True;
      end;
  end;
end;

function TApp.NextEvent(var ev: TKeyEv; waitMs: Integer): Boolean;
var
  e: TSDL_Event;
begin
  ev := Default(TKeyEv);
  if ScriptRunning then Exit(ScriptNext(ev));
  Result := False;
  if SDL_WaitEventTimeout(e, waitMs) = 0 then Exit;
  repeat
    if Translate(e, ev) then Exit(True);
  until SDL_PollEvent(e) = 0;
end;

{ ---- scripted input, used by the tests ---- }

procedure TApp.SetScript(const fn: string);
begin
  Script.LoadFromFile(fn);
  ScriptPos := 0;
  ScriptRunning := True;
end;

function SymFromName(const nm: string; out sym: LongInt): Boolean;
var
  s: string;
begin
  Result := True;
  s := LowerCase(nm);
  if (s = 'return') or (s = 'enter') then sym := SDLK_RETURN
  else if (s = 'escape') or (s = 'esc') then sym := SDLK_ESCAPE
  else if s = 'tab' then sym := SDLK_TAB
  else if s = 'backspace' then sym := SDLK_BACKSPACE
  else if s = 'delete' then sym := SDLK_DELETE
  else if s = 'insert' then sym := SDLK_INSERT
  else if s = 'home' then sym := SDLK_HOME
  else if s = 'end' then sym := SDLK_END
  else if s = 'pageup' then sym := SDLK_PAGEUP
  else if s = 'pagedown' then sym := SDLK_PAGEDOWN
  else if s = 'up' then sym := SDLK_UP
  else if s = 'down' then sym := SDLK_DOWN
  else if s = 'left' then sym := SDLK_LEFT
  else if s = 'right' then sym := SDLK_RIGHT
  else if s = 'space' then sym := SDLK_SPACE
  else if (Length(s) >= 2) and (s[1] = 'f') and (StrToIntDef(Copy(s, 2, 3), 0) in [1..12]) then
    sym := SDLK_F1 + StrToInt(Copy(s, 2, 3)) - 1
  else if Length(s) = 1 then sym := Ord(s[1])
  else Result := False;
end;

function TApp.ScriptNext(var ev: TKeyEv): Boolean;
var
  raw, line, cmd, arg, tok: string;
  p, i: Integer;
  mods: TStringList;
  sym: LongInt;
  w, h: LongInt;
  f: TextFile;
  u8: UTF8String;
begin
  Result := False;
  while ScriptPos < Script.Count do
  begin
    raw := Script[ScriptPos];
    Inc(ScriptPos);
    line := Trim(raw);
    if (line = '') or (line[1] = '#') then Continue;
    p := Pos(' ', raw);
    if p = 0 then begin cmd := LowerCase(line); arg := ''; end
    else begin cmd := LowerCase(Trim(Copy(raw, 1, p - 1))); arg := Copy(raw, p + 1, MaxInt); end;
    if cmd = 'text' then
    begin
      if arg = '' then Continue;
      ev := Default(TKeyEv);
      ev.Kind := ekText;
      ev.Text := UTF8Decode(arg);
      Exit(True);
    end
    else if cmd = 'key' then
    begin
      ev := Default(TKeyEv);
      ev.Kind := ekKey;
      mods := TStringList.Create;
      try
        mods.Delimiter := '+';
        mods.StrictDelimiter := True;
        mods.DelimitedText := Trim(arg);
        if mods.Count = 0 then Continue;
        for i := 0 to mods.Count - 2 do
        begin
          tok := LowerCase(mods[i]);
          if tok = 'ctrl' then ev.Ctrl := True
          else if tok = 'shift' then ev.Shift := True
          else if tok = 'alt' then ev.Alt := True;
        end;
        tok := mods[mods.Count - 1];
        if (Trim(arg) <> '') and (Trim(arg)[Length(Trim(arg))] = '+') then tok := '+';
        if tok = '' then tok := '+';
        if SymFromName(tok, sym) then ev.Sym := sym else Continue;
      finally
        mods.Free;
      end;
      Exit(True);
    end
    else if cmd = 'ctap' then
    begin
      ev := Default(TKeyEv);
      ev.Kind := ekKey;
      ev.Sym := SYM_CTRLTAP;
      Exit(True);
    end
    else if cmd = 'shot' then
    begin
      Render;
      Gfx.Screenshot(Trim(arg));
    end
    else if cmd = 'dump' then
    begin
      AssignFile(f, Trim(arg));
      Rewrite(f);
      Write(f, UTF8Encode(Snapshot));
      CloseFile(f);
    end
    else if cmd = 'dumpvalues' then
    begin
      AssignFile(f, Trim(arg));
      Rewrite(f);
      Write(f, UTF8Encode(ExportCsv(Sheet, True)));
      CloseFile(f);
    end
    else if cmd = 'clipboard' then
    begin
      { text for the system clipboard, with \t and \n standing for a tab and a line end }
      u8 := UTF8Encode(UnicodeString(StringReplace(StringReplace(arg, '\t', #9, [rfReplaceAll]), '\n', #10, [rfReplaceAll])));
      SDL_SetClipboardText(PAnsiChar(u8));
      ClipValid := False;
    end
    else if cmd = 'pickdir' then
      Cfg.LastDir := IncludeTrailingPathDelimiter(ExpandFileName(Trim(arg)))
    else if cmd = 'today' then
    begin
      Sheet.Today := StrToIntDef(Trim(arg), Sheet.Today);
      Sheet.Invalidate;
    end
    else if cmd = 'size' then
    begin
      w := StrToIntDef(Trim(Copy(arg, 1, Pos(' ', arg + ' ') - 1)), 1000);
      h := StrToIntDef(Trim(Copy(arg, Pos(' ', arg + ' ') + 1, 10)), 700);
      SDL_SetWindowSize(Gfx.Window, w, h);
      Gfx.Resized;
    end
    else if cmd = 'font' then
      Gfx.SetFontSize(StrToIntDef(Trim(arg), 20))
    else if cmd = 'open' then
      LoadPath(Trim(arg))
    else if (cmd = 'click') or (cmd = 'drag') or (cmd = 'dclick') or (cmd = 'shiftclick') then
    begin
      ev := Default(TKeyEv);
      if cmd = 'drag' then ev.Kind := ekDrag else ev.Kind := ekClick;
      if cmd = 'dclick' then ev.Clicks := 2;
      ev.Shift := cmd = 'shiftclick';
      ev.X := StrToIntDef(Trim(Copy(arg, 1, Pos(' ', arg + ' ') - 1)), 0);
      ev.Y := StrToIntDef(Trim(Copy(arg, Pos(' ', arg + ' ') + 1, 10)), 0);
      Exit(True);
    end
    else if cmd = 'release' then
    begin
      ev := Default(TKeyEv);
      ev.Kind := ekRelease;
      Exit(True);
    end
    else if cmd = 'wheel' then
    begin
      ev := Default(TKeyEv);
      ev.Kind := ekWheel;
      ev.Wheel := StrToIntDef(Trim(arg), 1);
      Exit(True);
    end
    else if cmd = 'quit' then
    begin
      Done := True;
      ScriptRunning := False;
      Exit(False);
    end;
  end;
  ScriptRunning := False;
  Done := True;
end;

{ ---- the render/wait loop ---- }

procedure TApp.Render;
begin
  Gfx.ClearAll(RGBOf(Cfg.ColBorder), RGBOf(Cfg.ColBack));
  if Assigned(FullScreen) then FullScreen()
  else DrawScreen;
  if Assigned(Overlay) then Overlay();
  UpdateTitle;
  Gfx.Present;
end;

procedure TApp.UpdateTitle;
var
  t: string;
begin
  t := 'TieSheet';
  if FileName <> '' then t := t + ' - ' + ExtractFileName(FileName);
  if Dirty then t := t + ' *';
  if t <> ShownTitle then
  begin
    ShownTitle := t;
    Gfx.SetTitle(t);
  end;
end;

{ the day can change while the program is open: TODAY() must follow }
procedure TApp.CheckDate;
var
  d: Int64;
begin
  d := TodaySerial;
  if (not ScriptRunning) and (d <> Sheet.Today) then
  begin
    Sheet.Today := d;
    Sheet.Invalidate;
  end;
end;

function TApp.WaitKey(var ev: TKeyEv): Boolean;
begin
  Result := False;
  while not Done do
  begin
    Render;
    if NextEvent(ev, 450) then
    begin
      case ev.Kind of
        ekKey, ekText, ekWheel, ekClick, ekDrag, ekRelease:
          begin
            BlinkOn := True;
            Exit(True);
          end;
        ekQuit:
          begin
            QuitReq := True;
            Exit(False);
          end;
      end;
    end
    else
    begin
      BlinkOn := not BlinkOn;
      CheckDate;
    end;
  end;
end;

procedure TApp.SetMsg(const s: UnicodeString; err: Boolean);
begin
  Msg := s;
  MsgErr := err;
end;

{ ---- prompts ---- }

procedure TApp.DrawPromptOverlay;
var
  txt, shown: UnicodeString;
  fg, bg: LongWord;
  w, scrollStart, i, curCol, avail, k: Integer;
begin
  fg := RGBOf(Cfg.ColBack);
  bg := RGBOf(Cfg.ColText);
  Gfx.FillCells(0, 1, Gfx.Cols, 1, bg);
  txt := PromptText + ' ';
  w := Length(txt);
  if PromptYN then
  begin
    Gfx.PutText(0, 1, txt, fg, ST_BOLD);
    Exit;
  end;
  Gfx.PutText(0, 1, txt, fg, ST_BOLD);
  avail := Gfx.Cols - w - 1;
  if avail < 4 then avail := 4;
  scrollStart := 0;
  if PromptCur >= avail then scrollStart := PromptCur - avail + 1;
  shown := Copy(PromptInput, scrollStart + 1, avail);
  if PromptFresh and (Length(shown) > 0) then
  begin
    Gfx.FillCells(w, 1, Length(shown), 1, fg);
    for i := 1 to Length(shown) do Gfx.PutChar(w + i - 1, 1, shown[i], ST_REGULAR, bg);
  end
  else
    for i := 1 to Length(shown) do Gfx.PutChar(w + i - 1, 1, shown[i], ST_REGULAR, fg);
  curCol := w + (PromptCur - scrollStart);
  if BlinkOn and (curCol < Gfx.Cols) then
  begin
    Gfx.FillCells(curCol, 1, 1, 1, fg);
    k := PromptCur + 1;
    if k <= Length(PromptInput) then Gfx.PutChar(curCol, 1, PromptInput[k], ST_REGULAR, bg);
  end;
end;

{ Tab on a file name: finish it as far as the folder allows }
procedure TApp.CompleteName;
var
  dir, prefix, cand, common: string;
  sr: TSearchRec;
  n: Integer;
  isDir: Boolean;
  inp: string;
begin
  inp := UTF8Encode(PromptInput);
  dir := ExtractFilePath(inp);
  prefix := ExtractFileName(inp);
  n := 0;
  common := '';
  isDir := False;
  if FindFirst(IncludeTrailingPathDelimiter(IfThenStr(dir = '', '.', dir)) + prefix + '*', faAnyFile, sr) = 0 then
  begin
    repeat
      if (sr.Name = '.') or (sr.Name = '..') then Continue;
      Inc(n);
      if n = 1 then
      begin
        common := sr.Name;
        isDir := (sr.Attr and faDirectory) <> 0;
      end
      else
      begin
        while (common <> '') and (Copy(sr.Name, 1, Length(common)) <> common) do
          SetLength(common, Length(common) - 1);
        isDir := False;
      end;
    until FindNext(sr) <> 0;
    FindClose(sr);
  end;
  if n = 0 then begin SetMsg('Nothing starts with that'); Exit; end;
  cand := dir + common;
  if (n = 1) and isDir then cand := cand + PathDelim;
  PromptInput := UTF8Decode(cand);
  PromptCur := Length(PromptInput);
  PromptFresh := False;
  if n > 1 then SetMsg(UnicodeString(IntToStr(n)) + ' names start with that');
end;

function TApp.Prompt(const text: UnicodeString; var value: UnicodeString; files: Boolean): Boolean;
var
  ev: TKeyEv;
  savedOverlay: TProc;
begin
  Result := False;
  PromptText := text;
  PromptInput := value;
  PromptCur := Length(value);
  PromptYN := False;
  PromptFresh := value <> '';
  savedOverlay := Overlay;
  Overlay := @DrawPromptOverlay;
  try
    while WaitKey(ev) do
    begin
      if ev.Kind = ekKey then
      begin
        case ev.Sym of
          SDLK_RETURN, SDLK_KP_ENTER:
            begin
              value := PromptInput;
              Exit(True);
            end;
          SDLK_ESCAPE: Exit(False);
          SDLK_TAB: if files then CompleteName;
          SDLK_BACKSPACE:
            begin
              if PromptFresh then begin PromptInput := ''; PromptCur := 0; PromptFresh := False; end
              else if PromptCur > 0 then
              begin
                Delete(PromptInput, PromptCur, 1);
                Dec(PromptCur);
              end;
            end;
          SDLK_DELETE:
            begin
              if PromptFresh then begin PromptInput := ''; PromptCur := 0; PromptFresh := False; end
              else if PromptCur < Length(PromptInput) then Delete(PromptInput, PromptCur + 1, 1);
            end;
          SDLK_LEFT: begin PromptFresh := False; if PromptCur > 0 then Dec(PromptCur); end;
          SDLK_RIGHT: begin PromptFresh := False; if PromptCur < Length(PromptInput) then Inc(PromptCur); end;
          SDLK_HOME: begin PromptFresh := False; PromptCur := 0; end;
          SDLK_END: begin PromptFresh := False; PromptCur := Length(PromptInput); end;
        end;
      end
      else if ev.Kind = ekText then
      begin
        if PromptFresh then begin PromptInput := ''; PromptCur := 0; PromptFresh := False; end;
        Insert(ev.Text, PromptInput, PromptCur + 1);
        Inc(PromptCur, Length(ev.Text));
      end;
    end;
  finally
    Overlay := savedOverlay;
  end;
end;

{ one key out of keys (case does not matter); -1 for Esc }
function TApp.AskChoice(const text, keys: UnicodeString): Integer;
var
  ev: TKeyEv;
  savedOverlay: TProc;
  i: Integer;
  u: UnicodeString;
begin
  Result := -1;
  PromptText := text;
  PromptYN := True;
  savedOverlay := Overlay;
  Overlay := @DrawPromptOverlay;
  try
    while WaitKey(ev) do
    begin
      if (ev.Kind = ekKey) and (ev.Sym = SDLK_ESCAPE) then Exit(-1);
      if ev.Kind = ekText then
      begin
        u := UpperCase(ev.Text);
        for i := 1 to Length(keys) do
          if u = UpperCase(Copy(keys, i, 1)) then Exit(i - 1);
      end;
    end;
  finally
    Overlay := savedOverlay;
    PromptYN := False;
  end;
end;
