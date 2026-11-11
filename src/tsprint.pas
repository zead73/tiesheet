{ tsprint - a sheet on paper: pages of fixed-width lines, as a PDF or as text.

  The text is laid out in a monospace font so that the columns line up as they do on screen.  The
  layout is the first of these that fits the width of what is printed: portrait 10 point, landscape
  10 point, landscape 8 point; a sheet wider than that is cut into strips of columns, printed one
  after the other.  The PDF uses the standard Courier font, so it needs no font file. }
unit tsprint;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, tssheet;

type
  TPaperSize = (psLetter, psA4);

  TPrintPage = record
    Header, Footer: UnicodeString;
    Lines: array of UnicodeString;
  end;

  TPrintJob = record
    Paper: TPaperSize;
    Landscape: Boolean;
    PointSize: Integer;           { 10 or 8; Courier, so a character is 0.6 of that wide }
    CharsPerLine: Integer;        { how wide a page is }
    BodyLines: Integer;           { lines of the sheet on one page }
    Pages: array of TPrintPage;
  end;

{ the cells c1..c2 x r1..r2 of the sheet; title goes at the top of every page }
procedure BuildPrint(sheet: TSheet; c1, r1, c2, r2: Integer; const title: UnicodeString;
  paper: TPaperSize; out job: TPrintJob);
function JobToText(const job: TPrintJob): UnicodeString;
{ '' or why not }
function WritePdfFile(const job: TPrintJob; const fn: string): string;
function PaperName(p: TPaperSize): string;
function PdfBytes(const job: TPrintJob): RawByteString;

implementation

uses
  tsvalue, tsformula;

const
  MARGIN_PT = 54;                 { three quarters of an inch }

function PaperName(p: TPaperSize): string;
begin
  if p = psA4 then Result := 'A4' else Result := 'Letter';
end;

procedure PaperPoints(p: TPaperSize; landscape: Boolean; out w, h: Integer);
begin
  if p = psA4 then begin w := 595; h := 842; end else begin w := 612; h := 792; end;
  if landscape then begin h := h xor w; w := h xor w; h := h xor w; end;
end;

function LineHeight(pt: Integer): Integer;
begin
  { 10 point on 12, 8 point on 10: six and eight lines to the inch }
  Result := pt + 2;
end;

procedure PickLayout(totalWidth: Integer; paper: TPaperSize; var job: TPrintJob);
const
  Tries: array[0..2] of record Landscape: Boolean; Pt: Integer; end =
    ((Landscape: False; Pt: 10), (Landscape: True; Pt: 10), (Landscape: True; Pt: 8));
var
  i, w, h, chars: Integer;
begin
  job.Paper := paper;
  for i := 0 to 2 do
  begin
    PaperPoints(paper, Tries[i].Landscape, w, h);
    chars := ((w - 2 * MARGIN_PT) * 10) div (6 * Tries[i].Pt);
    job.Landscape := Tries[i].Landscape;
    job.PointSize := Tries[i].Pt;
    job.CharsPerLine := chars;
    job.BodyLines := (h - 2 * MARGIN_PT) div LineHeight(Tries[i].Pt) - 4;
    if totalWidth <= chars then Exit;
  end;
end;

{ one row of the sheet, columns cs..ce, as text }
{ extra: how many characters of the page are free to the right of the last column, for text that runs on }
function RowLine(sheet: TSheet; r, cs, ce, total, extra: Integer): UnicodeString;
var
  buf: UnicodeString;
  c, x, w, cw, avail, k, xx, i: Integer;
  s: UnicodeString;
  v: TValue;
  right: Boolean;
begin
  buf := UnicodeString(StringOfChar(' ', total + extra));
  x := 0;
  for c := cs to ce do
  begin
    w := sheet.ColWidth(c);
    if sheet.Exists(c, r) then
    begin
      v := sheet.Value(c, r);
      s := sheet.Display(c, r);
      right := v.Kind in [vkNum, vkBool, vkErr];
      cw := w - 1;
      if s <> '' then
      begin
        if right then
        begin
          if Length(s) > cw then s := UnicodeString(StringOfChar('#', cw));
          for i := 1 to Length(s) do buf[x + cw - Length(s) + i] := s[i];
        end
        else
        begin
          avail := cw;
          k := c + 1;
          xx := x + w;
          while (Length(s) > avail) and (k <= ce) and (not sheet.Exists(k, r)) do
          begin
            Inc(avail, sheet.ColWidth(k));
            Inc(xx, sheet.ColWidth(k));
            Inc(k);
          end;
          if (Length(s) > avail) and (k > ce) then Inc(avail, extra);
          if Length(s) > avail then s := Copy(s, 1, avail);
          for i := 1 to Length(s) do buf[x + i] := s[i];
        end;
      end;
    end;
    Inc(x, w);
  end;
  i := Length(buf);
  while (i > 0) and (buf[i] = ' ') do Dec(i);
  Result := Copy(buf, 1, i);
end;

procedure BuildPrint(sheet: TSheet; c1, r1, c2, r2: Integer; const title: UnicodeString;
  paper: TPaperSize; out job: TPrintJob);
var
  total, c, w, cs, strips, s, r, rowPages, p, perStrip, n, base, i, sw, extra: Integer;
  stripStart, stripEnd: array of Integer;
  stripText: UnicodeString;
  pg: TPrintPage;
begin
  job := Default(TPrintJob);
  total := 0;
  for c := c1 to c2 do Inc(total, sheet.ColWidth(c));
  PickLayout(total, paper, job);
  { strips of columns that fit a page }
  SetLength(stripStart, 0);
  SetLength(stripEnd, 0);
  cs := c1;
  while cs <= c2 do
  begin
    w := 0;
    c := cs;
    while (c <= c2) and ((w + sheet.ColWidth(c) <= job.CharsPerLine) or (c = cs)) do
    begin
      Inc(w, sheet.ColWidth(c));
      Inc(c);
    end;
    SetLength(stripStart, Length(stripStart) + 1);
    SetLength(stripEnd, Length(stripEnd) + 1);
    stripStart[High(stripStart)] := cs;
    stripEnd[High(stripEnd)] := c - 1;
    cs := c;
  end;
  strips := Length(stripStart);
  rowPages := (r2 - r1 + 1 + job.BodyLines - 1) div job.BodyLines;
  if rowPages < 1 then rowPages := 1;
  perStrip := rowPages;
  n := 0;
  SetLength(job.Pages, strips * perStrip);
  for s := 0 to strips - 1 do
  begin
    sw := 0;
    for c := stripStart[s] to stripEnd[s] do Inc(sw, sheet.ColWidth(c));
    if sw > job.CharsPerLine then sw := job.CharsPerLine;
    if s = strips - 1 then extra := job.CharsPerLine - sw else extra := 0;
    stripText := '';
    if strips > 1 then
      stripText := UnicodeString(' (columns ' + ColName(stripStart[s]) + ' to ' + ColName(stripEnd[s]) + ')');
    for p := 0 to perStrip - 1 do
    begin
      pg := Default(TPrintPage);
      base := r1 + p * job.BodyLines;
      SetLength(pg.Lines, 0);
      for r := base to base + job.BodyLines - 1 do
      begin
        if r > r2 then Break;
        SetLength(pg.Lines, Length(pg.Lines) + 1);
        pg.Lines[High(pg.Lines)] := RowLine(sheet, r, stripStart[s], stripEnd[s], sw, extra);
        if Length(pg.Lines[High(pg.Lines)]) > job.CharsPerLine then
          pg.Lines[High(pg.Lines)] := Copy(pg.Lines[High(pg.Lines)], 1, job.CharsPerLine);
      end;
      pg.Header := title + stripText;
      job.Pages[n] := pg;
      Inc(n);
    end;
  end;
  for i := 0 to High(job.Pages) do
    job.Pages[i].Footer := UnicodeString(Format('Page %d of %d', [i + 1, Length(job.Pages)]));
end;

function JobToText(const job: TPrintJob): UnicodeString;
var
  p, i: Integer;
begin
  Result := '';
  for p := 0 to High(job.Pages) do
  begin
    if p > 0 then Result := Result + #12;
    Result := Result + job.Pages[p].Header + #10#10;
    for i := 0 to High(job.Pages[p].Lines) do Result := Result + job.Pages[p].Lines[i] + #10;
    Result := Result + #10 + job.Pages[p].Footer + #10;
  end;
end;

{ ---- PDF ---- }

{ the byte for a character in the PDF's WinAnsi encoding; anything it cannot show becomes ? }
function WinAnsi(ch: WideChar): Byte;
begin
  case Ord(ch) of
    0..31: Result := 32;
    32..126: Result := Ord(ch);
    $A0..$FF: Result := Ord(ch);
    $20AC: Result := $80;
    $2026: Result := $85;
    $2018: Result := $91;
    $2019: Result := $92;
    $201C: Result := $93;
    $201D: Result := $94;
    $2022: Result := $95;
    $2013: Result := $96;
    $2014: Result := $97;
    $2122: Result := $99;
  else
    Result := Ord('?');
  end;
end;

function PdfString(const s: UnicodeString): string;
var
  i: Integer;
  b: Byte;
begin
  Result := '(';
  for i := 1 to Length(s) do
  begin
    b := WinAnsi(s[i]);
    if (b = Ord('(')) or (b = Ord(')')) or (b = Ord('\')) then Result := Result + '\' + Chr(b)
    else if b > 126 then Result := Result + '\' + Chr(48 + (b shr 6)) + Chr(48 + ((b shr 3) and 7)) + Chr(48 + (b and 7))
    else Result := Result + Chr(b);
  end;
  Result := Result + ')';
end;

function PdfBytes(const job: TPrintJob): RawByteString;
var
  out_: string;
  offsets: array of Integer;
  nObj, p, i, pw, ph, lh, y, x0, pageObj, contentObj: Integer;
  content: string;
  pageRefs: string;

  procedure Obj(const body: string);
  begin
    Inc(nObj);
    SetLength(offsets, nObj + 1);
    offsets[nObj] := Length(out_);
    out_ := out_ + IntToStr(nObj) + ' 0 obj' + #10 + body + #10 + 'endobj' + #10;
  end;

begin
  PaperPoints(job.Paper, job.Landscape, pw, ph);
  lh := LineHeight(job.PointSize);
  out_ := '%PDF-1.4' + #10;
  nObj := 0;
  SetLength(offsets, 1);
  { objects 1 = catalog, 2 = pages, 3 = font; then a page and its content for every page }
  Obj('<< /Type /Catalog /Pages 2 0 R >>');
  pageRefs := '';
  for p := 0 to High(job.Pages) do pageRefs := pageRefs + IntToStr(4 + 2 * p) + ' 0 R ';
  Obj('<< /Type /Pages /Kids [ ' + pageRefs + '] /Count ' + IntToStr(Length(job.Pages)) + ' >>');
  Obj('<< /Type /Font /Subtype /Type1 /BaseFont /Courier /Encoding /WinAnsiEncoding >>');
  for p := 0 to High(job.Pages) do
  begin
    pageObj := 4 + 2 * p;
    contentObj := pageObj + 1;
    Obj(Format('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %d %d] /Resources << /Font << /F1 3 0 R >> >> /Contents %d 0 R >>',
      [pw, ph, contentObj]));
    x0 := MARGIN_PT;
    y := ph - MARGIN_PT - job.PointSize;
    content := 'BT' + #10 + '/F1 ' + IntToStr(job.PointSize) + ' Tf' + #10 + IntToStr(lh) + ' TL' + #10 +
      IntToStr(x0) + ' ' + IntToStr(y) + ' Td' + #10;
    content := content + PdfString(job.Pages[p].Header) + ' Tj T*' + #10 + 'T*' + #10;
    for i := 0 to High(job.Pages[p].Lines) do
      content := content + PdfString(job.Pages[p].Lines[i]) + ' Tj T*' + #10;
    content := content + 'ET' + #10;
    { the footer sits on the last line of the page }
    content := content + 'BT' + #10 + '/F1 ' + IntToStr(job.PointSize) + ' Tf' + #10 + IntToStr(x0) + ' ' +
      IntToStr(MARGIN_PT) + ' Td' + #10 + PdfString(job.Pages[p].Footer) + ' Tj' + #10 + 'ET' + #10;
    Obj('<< /Length ' + IntToStr(Length(content)) + ' >>' + #10 + 'stream' + #10 + content + 'endstream');
  end;
  p := Length(out_);
  out_ := out_ + 'xref' + #10 + '0 ' + IntToStr(nObj + 1) + #10 + '0000000000 65535 f ' + #10;
  for i := 1 to nObj do out_ := out_ + Format('%.10d 00000 n ', [offsets[i]]) + #10;
  out_ := out_ + 'trailer' + #10 + '<< /Size ' + IntToStr(nObj + 1) + ' /Root 1 0 R >>' + #10 + 'startxref' + #10 +
    IntToStr(p) + #10 + '%%EOF' + #10;
  Result := out_;
end;

function WritePdfFile(const job: TPrintJob; const fn: string): string;
var
  fs: TFileStream;
  raw: RawByteString;
  tmp: string;
begin
  Result := '';
  raw := PdfBytes(job);
  tmp := fn + '.tmp';
  try
    fs := TFileStream.Create(tmp, fmCreate);
    try
      fs.WriteBuffer(raw[1], Length(raw));
    finally
      fs.Free;
    end;
    if FileExists(fn) then DeleteFile(fn);
    if not RenameFile(tmp, fn) then Exit('Cannot put the PDF in place as ' + fn);
  except
    on e: Exception do Result := 'Cannot write ' + fn + ': ' + e.Message;
  end;
end;

end.
