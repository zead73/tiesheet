{ tsfile - the TieSheet file: plain text, readable and diffable.

    tiesheet 1
    width A 14
    format B2:B9 currency 2 1
    ---
    Date,Name,Amount
    2026-11-10,Rent,$1,200.00        <- the cells, as a CSV, exactly as they were typed

  The part before the --- line holds what a CSV cannot: column widths and cell formats that differ from
  what typing the cell would give.  Unknown lines there are ignored, so a newer file still opens. }
unit tsfile;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, tssheet;

const
  FILE_VERSION = 1;

function SheetToText(sheet: TSheet): UnicodeString;
{ '' or why not; the sheet is emptied first }
function SheetFromText(sheet: TSheet; const text: UnicodeString; warnings: TStrings): string;
function SaveSheetFile(sheet: TSheet; const fn: string): string;
function LoadSheetFile(sheet: TSheet; const fn: string; warnings: TStrings): string;

implementation

uses
  tsformula, tscsv;

const
  KindNames: array[TNumFmtKind] of string = ('general', 'number', 'currency', 'percent', 'date');

function FormatsEqual(const a, b: TFormat): Boolean;
begin
  Result := (a.Kind = b.Kind) and (a.Decimals = b.Decimals) and (a.Thousands = b.Thousands);
end;

function BoolDigit(b: Boolean): string;
begin
  if b then Result := '1' else Result := '0';
end;

function SheetToText(sheet: TSheet): UnicodeString;
var
  lastCol, lastRow, c, r, runStart: Integer;
  cols: TIntArray;
  i: Integer;
  fmt, runFmt: TFormat;
  ent: TEntry;
  inRun: Boolean;
  lines: UnicodeString;

  { the format a cell has beyond what its text would give }
  function Extra(col, row: Integer; out f: TFormat): Boolean;
  begin
    f := sheet.GetFormat(col, row);
    if not sheet.Exists(col, row) then Exit(False);
    if sheet.GetKind(col, row) = ckFormula then
      Result := not FormatsEqual(f, GeneralFormat)
    else if TSheet.ParseEntry(sheet.GetRaw(col, row), ent) then
      Result := not FormatsEqual(f, ent.Fmt)
    else
      Result := False;
  end;

  procedure Emit(col, r1, r2: Integer; const f: TFormat);
  var
    ref: string;
  begin
    ref := CellName(col, r1);
    if r2 > r1 then ref := ref + ':' + CellName(col, r2);
    lines := lines + UnicodeString(Format('format %s %s %d %s', [ref, KindNames[f.Kind], f.Decimals,
      BoolDigit(f.Thousands)])) + #10;
  end;

begin
  lines := 'tiesheet ' + UnicodeString(IntToStr(FILE_VERSION)) + #10;
  cols := sheet.CustomWidthCols;
  for i := 0 to High(cols) do
    lines := lines + UnicodeString(Format('width %s %d', [ColName(cols[i]), sheet.ColWidth(cols[i])])) + #10;
  if sheet.Extent(lastCol, lastRow) then
    for c := 0 to lastCol do
    begin
      inRun := False;
      runStart := 0;
      runFmt := GeneralFormat;
      for r := 0 to lastRow + 1 do
      begin
        if (r <= lastRow) and Extra(c, r, fmt) then
        begin
          if inRun and FormatsEqual(fmt, runFmt) then Continue;
          if inRun then Emit(c, runStart, r - 1, runFmt);
          inRun := True;
          runStart := r;
          runFmt := fmt;
        end
        else if inRun then
        begin
          Emit(c, runStart, r - 1, runFmt);
          inRun := False;
        end;
      end;
    end;
  Result := lines + '---' + #10 + ExportCsv(sheet, False);
end;

function KindFromName(const s: string; out k: TNumFmtKind): Boolean;
var
  kk: TNumFmtKind;
begin
  for kk := Low(TNumFmtKind) to High(TNumFmtKind) do
    if KindNames[kk] = s then
    begin
      k := kk;
      Exit(True);
    end;
  Result := False;
end;

function ColFromName(const s: string; out col: Integer): Boolean;
var
  c, r: Integer;
begin
  Result := ParseCellName(UnicodeString(s + '1'), c, r);
  col := c;
end;

function SheetFromText(sheet: TSheet; const text: UnicodeString; warnings: TStrings): string;
var
  pos0, eol, ver: Integer;
  line, body: UnicodeString;
  parts: TStringList;
  first: Boolean;
  fmtLines: TStringList;
  i, c1, r1, c2, r2, col, w, dec: Integer;
  kind: TNumFmtKind;
  f: TFormat;
  a, b: string;
  p: Integer;

  procedure Warn(const msg: string);
  begin
    if warnings <> nil then warnings.Add(msg);
  end;

begin
  Result := '';
  sheet.Clear;
  pos0 := 1;
  first := True;
  body := '';
  parts := TStringList.Create;
  fmtLines := TStringList.Create;
  try
    parts.Delimiter := ' ';
    parts.StrictDelimiter := True;
    while True do
    begin
      if pos0 > Length(text) then Exit('This is not a TieSheet file (no --- line)');
      eol := pos0;
      while (eol <= Length(text)) and (text[eol] <> #10) do Inc(eol);
      line := Copy(text, pos0, eol - pos0);
      if (Length(line) > 0) and (line[Length(line)] = #13) then SetLength(line, Length(line) - 1);
      pos0 := eol + 1;
      if first then
      begin
        first := False;
        if (Copy(line, 1, 9) <> 'tiesheet ') then Exit('This is not a TieSheet file');
        ver := StrToIntDef(string(Trim(string(Copy(line, 10, MaxInt)))), 0);
        if ver < 1 then Exit('This is not a TieSheet file');
        if ver > FILE_VERSION then Exit('This file was made by a newer TieSheet (version ' + IntToStr(ver) + ')');
        Continue;
      end;
      if line = '---' then Break;
      parts.DelimitedText := string(line);
      if (parts.Count = 3) and (parts[0] = 'width') and ColFromName(UpperCase(parts[1]), col) and
         TryStrToInt(parts[2], w) then
        sheet.SetColWidth(col, w)
      else if (parts.Count = 5) and (parts[0] = 'format') then
        fmtLines.Add(string(line))
      else if line <> '' then
        Warn('Ignored the line: ' + string(line));
    end;
    body := Copy(text, pos0, MaxInt);
    ImportCsv(sheet, body, warnings, True);
    { formats go on after the cells exist }
    for i := 0 to fmtLines.Count - 1 do
    begin
      parts.DelimitedText := fmtLines[i];
      p := Pos(':', parts[1]);
      if p > 0 then begin a := Copy(parts[1], 1, p - 1); b := Copy(parts[1], p + 1, MaxInt); end
      else begin a := parts[1]; b := parts[1]; end;
      if (not ParseCellName(UnicodeString(UpperCase(a)), c1, r1)) or (not ParseCellName(UnicodeString(UpperCase(b)), c2, r2)) or
         (not KindFromName(parts[2], kind)) or (not TryStrToInt(parts[3], dec)) then
      begin
        Warn('Ignored the line: ' + fmtLines[i]);
        Continue;
      end;
      f.Kind := kind;
      f.Decimals := dec;
      f.Thousands := parts[4] = '1';
      for col := c1 to c2 do
        for w := r1 to r2 do
          if sheet.Exists(col, w) then sheet.SetFormat(col, w, f);
    end;
  finally
    fmtLines.Free;
    parts.Free;
  end;
end;

function SaveSheetFile(sheet: TSheet; const fn: string): string;
begin
  Result := WriteTextFile(fn, SheetToText(sheet));
end;

function LoadSheetFile(sheet: TSheet; const fn: string; warnings: TStrings): string;
var
  text: UnicodeString;
begin
  Result := ReadTextFile(fn, text);
  if Result <> '' then Exit;
  Result := SheetFromText(sheet, text, warnings);
end;

end.
