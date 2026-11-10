{ tscsv - CSV in and out, and reading and writing text files safely.

  The CSV that LibreOffice writes with "save cell contents as formulas" keeps formulas as text
  (=TODAY() - A2), dates as 2026-11-10 and quotes fields that need it.  Reading it back
  here gives the same sheet, and writing it again gives the same text.  A CSV written for
  sharing (valuesOnly) holds results instead of formulas. }
unit tscsv;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, tssheet;

type
  TCsvRows = array of array of UnicodeString;

function DecodeText(const raw: RawByteString): UnicodeString;      { UTF-8, or Latin-1 when it is not valid UTF-8 }
function EncodeText(const s: UnicodeString): RawByteString;        { UTF-8, no byte order mark }
function DetectDelimiter(const text: UnicodeString): WideChar;
procedure ParseCsv(const text: UnicodeString; delim: WideChar; out rows: TCsvRows);
function CsvField(const s: UnicodeString; delim: WideChar): UnicodeString;

{ Puts the rows into the sheet, which should be empty.  A field starting with = is a formula; one that
  cannot be read, or a whole number with leading zeros (007), stays text.  Returns the cells filled.
  native: the text is the body of a TieSheet file, which is always comma separated and whose cells are
  read exactly as they were typed (so 007 is the number 7, as it was when typed). }
function ImportCsv(sheet: TSheet; const text: UnicodeString; warnings: TStrings; native: Boolean = False): Integer;
function ExportCsv(sheet: TSheet; valuesOnly: Boolean): UnicodeString;
{ the result in a cell as plain text: numbers without formats, dates as 2026-11-10 }
function CellPlainText(sheet: TSheet; col, row: Integer): UnicodeString;

function ReadTextFile(const fn: string; out text: UnicodeString): string;      { '' or the reason }
{ writes to a temporary file, keeps the old file as fn.bak, then puts the new one in place }
function WriteTextFile(const fn: string; const text: UnicodeString): string;

implementation

uses
  tsvalue, tsformula, tsdate, tsdec;

function ValidUtf8(const s: RawByteString): Boolean;
var
  i, n, extra: Integer;
  b: Byte;
begin
  i := 1;
  n := Length(s);
  while i <= n do
  begin
    b := Ord(s[i]);
    if b < $80 then extra := 0
    else if (b >= $C2) and (b <= $DF) then extra := 1
    else if (b >= $E0) and (b <= $EF) then extra := 2
    else if (b >= $F0) and (b <= $F4) then extra := 3
    else Exit(False);
    if i + extra > n then Exit(False);
    while extra > 0 do
    begin
      Inc(i);
      if (Ord(s[i]) and $C0) <> $80 then Exit(False);
      Dec(extra);
    end;
    Inc(i);
  end;
  Result := True;
end;

function DecodeText(const raw: RawByteString): UnicodeString;
var
  s: RawByteString;
  i: Integer;
begin
  s := raw;
  if (Length(s) >= 3) and (s[1] = #$EF) and (s[2] = #$BB) and (s[3] = #$BF) then Delete(s, 1, 3);
  if ValidUtf8(s) then
    Result := UTF8Decode(s)
  else
  begin
    SetLength(Result, Length(s));
    for i := 1 to Length(s) do Result[i] := WideChar(Ord(s[i]));
  end;
end;

function EncodeText(const s: UnicodeString): RawByteString;
begin
  Result := UTF8Encode(s);
end;

function DetectDelimiter(const text: UnicodeString): WideChar;
var
  i: Integer;
  inQ: Boolean;
  cnt: array[0..3] of Integer;
  best: Integer;
const
  Cands: array[0..3] of WideChar = (',', ';', #9, '|');
begin
  for i := 0 to 3 do cnt[i] := 0;
  inQ := False;
  for i := 1 to Length(text) do
  begin
    if text[i] = '"' then inQ := not inQ
    else if not inQ then
    begin
      if (text[i] = #10) or (text[i] = #13) then Break;
      if text[i] = ',' then Inc(cnt[0])
      else if text[i] = ';' then Inc(cnt[1])
      else if text[i] = #9 then Inc(cnt[2])
      else if text[i] = '|' then Inc(cnt[3]);
    end;
  end;
  best := 0;
  for i := 1 to 3 do
    if cnt[i] > cnt[best] then best := i;
  if cnt[best] = 0 then best := 0;
  Result := Cands[best];
end;

procedure ParseCsv(const text: UnicodeString; delim: WideChar; out rows: TCsvRows);
var
  i, n, nr, nf: Integer;
  field: UnicodeString;
  cur: array of UnicodeString;
  inQ, pending: Boolean;
  c: WideChar;

  procedure EndField;
  begin
    if nf >= Length(cur) then SetLength(cur, Length(cur) * 2 + 8);
    cur[nf] := field;
    Inc(nf);
    field := '';
  end;

  procedure EndRow;
  begin
    EndField;
    if nr >= Length(rows) then SetLength(rows, Length(rows) * 2 + 16);
    rows[nr] := Copy(cur, 0, nf);
    Inc(nr);
    nf := 0;
    pending := False;
  end;

begin
  rows := nil;
  SetLength(rows, 16);
  SetLength(cur, 8);
  nr := 0; nf := 0;
  field := '';
  inQ := False;
  pending := False;
  n := Length(text);
  i := 1;
  while i <= n do
  begin
    c := text[i];
    if inQ then
    begin
      if c = '"' then
      begin
        if (i < n) and (text[i + 1] = '"') then
        begin
          field := field + '"';
          Inc(i);
        end
        else
          inQ := False;
      end
      else
        field := field + c;
    end
    else if (c = '"') and (field = '') then
    begin
      inQ := True;
      pending := True;
    end
    else if c = delim then
    begin
      EndField;
      pending := True;
    end
    else if c = #13 then
    begin
      EndRow;
      if (i < n) and (text[i + 1] = #10) then Inc(i);
    end
    else if c = #10 then
      EndRow
    else
    begin
      field := field + c;
      pending := True;
    end;
    Inc(i);
  end;
  if pending or (field <> '') or (nf > 0) then EndRow;
  SetLength(rows, nr);
end;

function CsvField(const s: UnicodeString; delim: WideChar): UnicodeString;
var
  needs: Boolean;
  i: Integer;
begin
  needs := False;
  for i := 1 to Length(s) do
    if (s[i] = delim) or (s[i] = '"') or (s[i] = #10) or (s[i] = #13) then
    begin
      needs := True;
      Break;
    end;
  if not needs then Exit(s);
  Result := '"' + UnicodeString(StringReplace(string(s), '"', '""', [rfReplaceAll])) + '"';
end;

{ 007, -012: whole numbers written with leading zeros are codes, not quantities }
function LeadingZeroCode(const f: UnicodeString): Boolean;
var
  i: Integer;
begin
  i := 1;
  if (Length(f) > 0) and ((f[1] = '-') or (f[1] = '+')) then Inc(i);
  if (i + 1 > Length(f)) or (f[i] <> '0') then Exit(False);
  Result := True;
  for i := i + 1 to Length(f) do
    if (f[i] < '0') or (f[i] > '9') then Exit(False);
end;

function ImportCsv(sheet: TSheet; const text: UnicodeString; warnings: TStrings; native: Boolean): Integer;
var
  rows: TCsvRows;
  r, c: Integer;
  f: UnicodeString;
  err: string;
begin
  Result := 0;
  if native then ParseCsv(text, ',', rows) else ParseCsv(text, DetectDelimiter(text), rows);
  for r := 0 to High(rows) do
    for c := 0 to High(rows[r]) do
    begin
      f := rows[r][c];
      if f = '' then Continue;
      if (c > MAX_COL) or (r > MAX_ROW) then
      begin
        if warnings <> nil then warnings.Add('Row ' + IntToStr(r + 1) + ', column ' + IntToStr(c + 1) + ' is outside the sheet');
        Continue;
      end;
      if (not native) and LeadingZeroCode(f) then f := '''' + f;
      err := sheet.SetEntry(c, r, f);
      if err <> '' then
      begin
        if warnings <> nil then warnings.Add(CellName(c, r) + ': ' + err + ' (kept as text)');
        sheet.SetEntry(c, r, '''' + f);
      end;
      Inc(Result);
    end;
end;

{ the result of a cell as plain text, for a CSV made for sharing }
function CellPlainText(sheet: TSheet; col, row: Integer): UnicodeString;
var
  v: TValue;
  fmt: TFormat;
  i: Int64;
begin
  v := sheet.Value(col, row);
  fmt := sheet.GetFormat(col, row);
  case v.Kind of
    vkNum:
      if (v.IsDate or (fmt.Kind = nfDate)) and DecToInt64(DecRound(v.Num, 0, rmFloor), i) and SerialValid(i) then
        Result := UnicodeString(SerialToIso(i))
      else
        Result := NumToText(v.Num);
  else
    Result := TextOf(v);
  end;
end;

function ExportCsv(sheet: TSheet; valuesOnly: Boolean): UnicodeString;
var
  lastCol, lastRow, r, c: Integer;
  line, f: UnicodeString;
begin
  Result := '';
  if not sheet.Extent(lastCol, lastRow) then Exit;
  for r := 0 to lastRow do
  begin
    line := '';
    for c := 0 to lastCol do
    begin
      if c > 0 then line := line + ',';
      if not sheet.Exists(c, r) then Continue;
      if valuesOnly then f := CellPlainText(sheet, c, r) else f := sheet.GetRaw(c, r);
      line := line + CsvField(f, ',');
    end;
    Result := Result + line + #10;
  end;
end;

function ReadTextFile(const fn: string; out text: UnicodeString): string;
var
  fs: TFileStream;
  raw: RawByteString;
begin
  text := '';
  Result := '';
  try
    fs := TFileStream.Create(fn, fmOpenRead or fmShareDenyWrite);
    try
      SetLength(raw, fs.Size);
      if fs.Size > 0 then fs.ReadBuffer(raw[1], fs.Size);
    finally
      fs.Free;
    end;
    text := DecodeText(raw);
  except
    on e: Exception do Result := 'Cannot read ' + fn + ': ' + e.Message;
  end;
end;

function WriteTextFile(const fn: string; const text: UnicodeString): string;
var
  fs: TFileStream;
  raw: RawByteString;
  tmp, bak: string;
begin
  Result := '';
  tmp := fn + '.tmp';
  bak := fn + '.bak';
  raw := EncodeText(text);
  try
    fs := TFileStream.Create(tmp, fmCreate);
    try
      if Length(raw) > 0 then fs.WriteBuffer(raw[1], Length(raw));
    finally
      fs.Free;
    end;
    if FileExists(fn) then
    begin
      if FileExists(bak) then DeleteFile(bak);
      if not RenameFile(fn, bak) then Exit('Cannot keep the old ' + fn + ' as ' + bak);
    end;
    if not RenameFile(tmp, fn) then Exit('Cannot put the new file in place as ' + fn);
  except
    on e: Exception do Result := 'Cannot write ' + fn + ': ' + e.Message;
  end;
end;

end.
