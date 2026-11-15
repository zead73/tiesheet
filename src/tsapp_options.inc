{ tsapp_options.inc - the screen options on F9: colours, font size and paper (included by tsapp.pas) }

const
  OptCount = 10;
  OptNames: array[0..OptCount - 1] of string = (
    'Text colour', 'Background colour', 'Border colour', 'Formula results', 'Error values',
    'Row numbers and column letters', 'Selected cells', 'Font size', 'Paper for printing', 'Back to the defaults');

{ the next palette colour in a direction, skipping the colours it must not match }
function NextColor(cur, dir, avoid1, avoid2: Integer): Integer;
var
  n: Integer;
begin
  Result := cur;
  for n := 1 to 16 do
  begin
    Result := (Result + dir + 16) mod 16;
    if (Result <> avoid1) and (Result <> avoid2) then Exit;
  end;
end;

function TApp.OptValue(i: Integer; out swatch: Integer): string;
begin
  swatch := -1;
  case i of
    0: swatch := Cfg.ColText;
    1: swatch := Cfg.ColBack;
    2: swatch := Cfg.ColBorder;
    3: swatch := Cfg.ColFormula;
    4: swatch := Cfg.ColError;
    5: swatch := Cfg.ColHeader;
    6: swatch := Cfg.ColSelect;
  end;
  if swatch >= 0 then Result := PaletteNames[swatch]
  else case i of
    7: Result := IntToStr(Cfg.FontSize) + ' px';
    8: if Cfg.Paper = 0 then Result := 'Letter' else Result := 'A4';
    9: Result := 'Enter to restore';
  end;
end;

procedure TApp.DrawOptions;
var
  textC, backC, fg, bg: LongWord;
  x, y, w, h, i, nameW, sw: Integer;
  line: UnicodeString;
  v: string;
begin
  textC := RGBOf(Cfg.ColText);
  backC := RGBOf(Cfg.ColBack);
  nameW := 34;
  w := 56;
  if w > Gfx.Cols - 2 then w := Gfx.Cols - 2;
  h := OptCount + 4;
  x := (Gfx.Cols - w) div 2;
  if x < 0 then x := 0;
  y := 2;
  Gfx.FillCells(x, y, w, h, backC);
  Gfx.BoxPx(Gfx.CellX(x), Gfx.CellY(y), w * Gfx.CellW, h * Gfx.CellH, textC);
  Gfx.BoxPx(Gfx.CellX(x) + 2, Gfx.CellY(y) + 2, w * Gfx.CellW - 4, h * Gfx.CellH - 4, textC);
  line := ' Screen Options ';
  Gfx.PutText(x + (w - Length(line)) div 2, y, line, textC, ST_BOLD);
  for i := 0 to OptCount - 1 do
  begin
    fg := textC;
    bg := backC;
    if i = OptSel then begin fg := backC; bg := textC; end;
    Gfx.FillCells(x + 1, y + 1 + i, w - 2, 1, bg);
    Gfx.PutText(x + 2, y + 1 + i, UnicodeString(OptNames[i]), fg, ST_REGULAR);
    v := OptValue(i, sw);
    if sw >= 0 then
    begin
      Gfx.FillCells(x + 2 + nameW, y + 1 + i, 2, 1, RGBOf(sw));
      Gfx.BoxPx(Gfx.CellX(x + 2 + nameW), Gfx.CellY(y + 1 + i) + 1, 2 * Gfx.CellW, Gfx.CellH - 2, fg);
      Gfx.PutText(x + 5 + nameW, y + 1 + i, UnicodeString(v), fg, ST_BOLD);
    end
    else Gfx.PutText(x + 2 + nameW, y + 1 + i, UnicodeString(v), fg, ST_BOLD);
  end;
  Gfx.PutText(x + 2, y + h - 2, 'Up/Down choose   Left/Right change   Esc close', RGBOf(Cfg.ColHeader), ST_REGULAR);
end;

procedure TApp.OptAdjust(dir: Integer);
begin
  case OptSel of
    0: Cfg.ColText := NextColor(Cfg.ColText, dir, Cfg.ColBack, Cfg.ColSelect);
    1: Cfg.ColBack := NextColor(Cfg.ColBack, dir, Cfg.ColText, Cfg.ColSelect);
    2: Cfg.ColBorder := NextColor(Cfg.ColBorder, dir, -1, -1);
    3: Cfg.ColFormula := NextColor(Cfg.ColFormula, dir, Cfg.ColBack, Cfg.ColSelect);
    4: Cfg.ColError := NextColor(Cfg.ColError, dir, Cfg.ColBack, Cfg.ColSelect);
    5: Cfg.ColHeader := NextColor(Cfg.ColHeader, dir, Cfg.ColBack, -1);
    6: Cfg.ColSelect := NextColor(Cfg.ColSelect, dir, Cfg.ColBack, Cfg.ColText);
    7:
      begin
        Gfx.SetFontSize(Cfg.FontSize + dir * 2);
        Cfg.FontSize := Gfx.FontPx;
      end;
    8: Cfg.Paper := 1 - Cfg.Paper;
  end;
end;

procedure TApp.DoOptions;
var
  ev: TKeyEv;
  saved: TProc;
  keepDir: string;
  w, h: Integer;
begin
  OptSel := 0;
  saved := Overlay;
  Overlay := @DrawOptions;
  try
    while WaitKey(ev) do
    begin
      if ev.Kind = ekText then
      begin
        case ev.Text[1] of
          '+', '=': OptAdjust(1);
          '-': OptAdjust(-1);
        end;
        Continue;
      end;
      if ev.Kind <> ekKey then Continue;
      case ev.Sym of
        SDLK_ESCAPE, SDLK_F9: Break;
        SDLK_UP: if OptSel > 0 then Dec(OptSel);
        SDLK_DOWN: if OptSel < OptCount - 1 then Inc(OptSel);
        SDLK_LEFT: OptAdjust(-1);
        SDLK_RIGHT: OptAdjust(1);
        SDLK_RETURN, SDLK_KP_ENTER:
          if OptSel = 9 then
          begin
            { the defaults, but the window and the last folder stay as they are }
            keepDir := Cfg.LastDir;
            w := Cfg.WinW;
            h := Cfg.WinH;
            DefaultSettings(Cfg);
            Cfg.LastDir := keepDir;
            Cfg.WinW := w;
            Cfg.WinH := h;
            Gfx.SetFontSize(Cfg.FontSize);
            SetMsg('Defaults restored');
          end
          else OptAdjust(1);
      end;
    end;
  finally
    Overlay := saved;
  end;
  FollowCursor := True;
  SaveConfig;
end;
