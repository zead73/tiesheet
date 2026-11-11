{ tsapp_print.inc - the print preview and output (included by tsapp.pas) }

{ the selected cells, or else everything that is in the sheet }
function TApp.BuildJob: Boolean;
var
  c1, r1, c2, r2, lc, lr: Integer;
  title: UnicodeString;
begin
  Result := False;
  if not LastUsed(lc, lr) then begin SetMsg('Nothing to print'); Exit; end;
  if SelActive and ((CurC <> AnchorC) or (CurR <> AnchorR) or SelCols) then
  begin
    SelRect(c1, r1, c2, r2);
    if c2 > lc then c2 := lc;
    if r2 > lr then r2 := lr;
    if (c1 > c2) or (r1 > r2) then begin SetMsg('Nothing to print'); Exit; end;
  end
  else
  begin
    c1 := 0; r1 := 0; c2 := lc; r2 := lr;
  end;
  if FileName <> '' then title := UTF8Decode(ExtractFileName(FileName)) else title := 'TieSheet';
  BuildPrint(Sheet, c1, r1, c2, r2, title, TPaperSize(Cfg.Paper), PrintJob);
  if PrevPage >= Length(PrintJob.Pages) then PrevPage := Length(PrintJob.Pages) - 1;
  if PrevPage < 0 then PrevPage := 0;
  Result := True;
end;

procedure TApp.DrawPreview;
var
  textC, backC, dimC, white, black, gray: LongWord;
  i, k, x0, rows, pageRows, w, topLine: Integer;
  pg: TPrintPage;
  desc: UnicodeString;

  procedure Line(row: Integer; const s: UnicodeString; fg: LongWord);
  var
    shown: UnicodeString;
    sy: Integer;
  begin
    sy := 3 + row - PrevTop;
    if (sy < 3) or (sy >= Gfx.Rows - 1) then Exit;
    shown := Copy(s, PrevLeft + 1, w);
    if shown <> '' then Gfx.PutText(x0, sy, shown, fg);
  end;

begin
  textC := RGBOf(Cfg.ColText);
  backC := RGBOf(Cfg.ColBack);
  dimC := RGBOf(Cfg.ColHeader);
  white := RGBOf(1);
  black := RGBOf(0);
  gray := RGBOf(12);
  pg := PrintJob.Pages[PrevPage];
  if PrintJob.Landscape then desc := 'landscape' else desc := 'portrait';
  Gfx.FillCells(0, 0, Gfx.Cols, 1, textC);
  Gfx.PutText(0, 0, UnicodeString(Format(' Preview - page %d of %d - %s %s, %d point', [PrevPage + 1,
    Length(PrintJob.Pages), PaperName(PrintJob.Paper), string(desc), PrintJob.PointSize])), backC, ST_BOLD);
  Gfx.PutText(1, 1, 'PgUp/PgDn page   arrows scroll   P paper   Ctrl+O output   Esc closes', dimC);
  x0 := 2;
  w := Gfx.Cols - 3;
  if w > PrintJob.CharsPerLine then w := PrintJob.CharsPerLine;
  rows := Gfx.Rows - 4;
  { the page is white, like paper }
  pageRows := PrintJob.BodyLines + 4;
  topLine := 3 - PrevTop;
  if topLine < 3 then topLine := 3;
  for i := 0 to rows - 1 do
  begin
    k := PrevTop + i;
    if k >= pageRows then Break;
    Gfx.FillCells(1, 3 + i, Gfx.Cols - 2, 1, white);
  end;
  Line(0, pg.Header, gray);
  for i := 0 to High(pg.Lines) do Line(2 + i, pg.Lines[i], black);
  Line(pageRows - 1, pg.Footer, gray);
  { the page goes on beyond the screen: arrows at the edges of the paper }
  if PrevLeft > 0 then Gfx.PutText(1, 3, '<', gray);
  if PrevLeft + w < PrintJob.CharsPerLine then Gfx.PutText(Gfx.Cols - 2, 3, '>', gray);
end;

procedure TApp.DoPreview;
var
  ev: TKeyEv;
  rows, maxTop, maxLeft: Integer;
begin
  if not BuildJob then Exit;
  PrevPage := 0;
  PrevLeft := 0;
  PrevTop := 0;
  FullScreen := @DrawPreview;
  try
    while WaitKey(ev) do
    begin
      rows := Gfx.Rows - 4;
      if ev.Kind = ekText then
      begin
        if UpperCase(ev.Text) = 'P' then
        begin
          Cfg.Paper := 1 - Cfg.Paper;
          BuildJob;
        end;
      end
      else if ev.Kind = ekWheel then PrevTop := PrevTop - ev.Wheel * 3
      else if ev.Kind = ekKey then
      begin
        if CtrlMode then
        begin
          CtrlMode := False;
          ev.Ctrl := True;
        end;
        if ev.Sym = SYM_CTRLTAP then CtrlMode := not CtrlMode
        else if ev.Ctrl and (LetterOf(ev.Sym) = 'o') then DoOutput
        else if ev.Ctrl and (LetterOf(ev.Sym) = 'v') then Break
        else
          case ev.Sym of
            SDLK_ESCAPE: Break;
            SDLK_PAGEUP: if PrevPage > 0 then begin Dec(PrevPage); PrevTop := 0; end;
            SDLK_PAGEDOWN: if PrevPage < High(PrintJob.Pages) then begin Inc(PrevPage); PrevTop := 0; end;
            SDLK_HOME: begin PrevPage := 0; PrevTop := 0; end;
            SDLK_END: begin PrevPage := High(PrintJob.Pages); PrevTop := 0; end;
            SDLK_UP: Dec(PrevTop);
            SDLK_DOWN: Inc(PrevTop);
            SDLK_LEFT: Dec(PrevLeft, 4);
            SDLK_RIGHT: Inc(PrevLeft, 4);
          end;
      end;
      maxTop := PrintJob.BodyLines + 4 - rows;
      if maxTop < 0 then maxTop := 0;
      if PrevTop > maxTop then PrevTop := maxTop;
      if PrevTop < 0 then PrevTop := 0;
      maxLeft := PrintJob.CharsPerLine - (Gfx.Cols - 3);
      if maxLeft < 0 then maxLeft := 0;
      if PrevLeft > maxLeft then PrevLeft := maxLeft;
      if PrevLeft < 0 then PrevLeft := 0;
    end;
  finally
    FullScreen := nil;
  end;
end;

procedure TApp.DoOutput;
var
  k, fi: Integer;
  fn, err, base, startDir: string;
begin
  if not BuildJob then Exit;
  k := AskChoice('Output:  (P)DF  (T)ext file', 'PT');
  if k < 0 then Exit;
  if FileName <> '' then base := ChangeFileExt(ExtractFileName(FileName), '') else base := 'sheet';
  startDir := Cfg.LastDir;
  if (startDir = '') and (FileName <> '') then startDir := ExtractFilePath(FileName);
  if k = 0 then
  begin
    fi := 0;
    if not PickFile(pmSave, 'Write the PDF', startDir, base + '.pdf', ['PDF files (*.pdf)|*.pdf', 'All files|*'], fi, fn) then Exit;
    if ExtractFileExt(fn) = '' then fn := fn + '.pdf';
  end
  else
  begin
    fi := 0;
    if not PickFile(pmSave, 'Write the text file', startDir, base + '.txt', ['Text files (*.txt)|*.txt', 'All files|*'], fi, fn) then Exit;
    if ExtractFileExt(fn) = '' then fn := fn + '.txt';
  end;
  if not OverwriteOk(Self, fn, '') then Exit;
  if k = 0 then err := WritePdfFile(PrintJob, fn) else err := WriteTextFile(fn, JobToText(PrintJob));
  if err <> '' then SetMsg(UnicodeString(err), True)
  else SetMsg(UnicodeString(Format('Wrote %s (%d page(s), %s)', [ExtractFileName(fn), Length(PrintJob.Pages),
    PaperName(PrintJob.Paper)])));
end;
