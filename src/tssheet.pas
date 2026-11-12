{ tssheet - the grid: cells, what typing into a cell means, recalculation, copying.

  A cell remembers exactly what was typed (Raw).  Typing is read like this: =... is a formula,
  a leading ' forces text, TRUE/FALSE, 2026-11-10 is a date, $12.50 is money, 5% is a
  percentage, 1,234.5 is a number; anything else is text.  The way a number was typed picks its
  display format (so 12.50 stays 12.50), and the format can be changed afterwards.

  Recalculation evaluates every formula cell after the cells it reads, walking the
  dependencies with an explicit stack (a running balance of 20,000 rows must not overflow
  the real stack).  Cells in a loop show #CIRC!. }
unit tssheet;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Generics.Collections, tsdec, tsvalue, tsformula;

type
  TNumFmtKind = (nfGeneral, nfNumber, nfCurrency, nfPercent, nfDate);

  TFormat = record
    Kind: TNumFmtKind;
    Decimals: Integer;
    Thousands: Boolean;
  end;

  TCellKind = (ckNumber, ckText, ckBool, ckFormula);
  TIntArray = array of Integer;

  TCell = class
  public
    Col, Row: Integer;
    Raw: UnicodeString;
    Kind: TCellKind;
    Value: TValue;                 { a constant's value, or a formula's last result }
    Fmt: TFormat;
    Node: TNode;                   { the parsed formula }
    Deps: TRangeArray;
    Mark: Byte;                    { recalculation: 0 not yet, 1 in progress, 2 done }
    Circ: Boolean;
    destructor Destroy; override;
  end;

  TEntry = record
    Kind: TCellKind;
    Raw: UnicodeString;
    Value: TValue;
    Fmt: TFormat;
  end;

  TSheet = class(TEvalCtx)
  private
    FCells: specialize TDictionary<Int64, TCell>;
    FDirty: Boolean;
    FWidths: specialize TDictionary<Integer, Integer>;
    FColFmts: specialize TDictionary<Integer, TFormat>;
    function Key(col, row: Integer): Int64;
    function Find(col, row: Integer): TCell;
    procedure Evaluate(root: TCell);
    function DepCells(c: TCell): Classes.TList;
    procedure Restructure(isRow, remove: Boolean; at, count: Integer);
  public
    constructor Create;
    destructor Destroy; override;
    { what the typed text means; no cell is touched }
    class function ParseEntry(const text: UnicodeString; out ent: TEntry): Boolean;

    { Types into a cell.  '' on success; otherwise why a formula was refused (the cell is left alone).
      Empty text clears the cell. }
    function SetEntry(col, row: Integer; const text: UnicodeString): string;
    procedure ClearCell(col, row: Integer);
    function Exists(col, row: Integer): Boolean;
    function GetRaw(col, row: Integer): UnicodeString;
    function GetKind(col, row: Integer): TCellKind;
    function GetFormat(col, row: Integer): TFormat;
    procedure SetFormat(col, row: Integer; const fmt: TFormat);
    function Value(col, row: Integer): TValue;                         { recalculates when needed }
    function Display(col, row: Integer): UnicodeString;                { as the cell format shows it }
    function CellCount: Integer;
    function Extent(out lastCol, lastRow: Integer): Boolean;           { the used area }
    procedure Recalc;
    { everything is worked out again at the next read; for when something outside the cells changed, such as the date }
    procedure Invalidate;
    procedure Clear;                                                   { every cell and width }
    function ColWidth(col: Integer): Integer;                          { in characters }
    procedure SetColWidth(col, width: Integer);                        { the default width removes the entry }
    function CustomWidthCols: TIntArray;                               { columns with their own width, in order }
    { a column's own format: numbers and formulas typed into it get it, unless typing gave them another }
    function ColFormat(col: Integer): TFormat;
    procedure SetColFormat(col: Integer; const fmt: TFormat);          { general removes it }
    function CustomFormatCols: TIntArray;
    { the format a cell has just from what was typed in it (and its column) }
    function ExpectedFormat(col, row: Integer): TFormat;
    { rows and columns: the cells below / to the right move, and every formula follows what it refers to;
      what refers to a deleted row or column becomes #REF! }
    procedure InsertRows(at, count: Integer);
    procedure DeleteRows(at, count: Integer);
    procedure InsertCols(at, count: Integer);
    procedure DeleteCols(at, count: Integer);
    { sorts the rows r1..r2 of the columns c1..c2 by the cells of keyCol; empty cells go last.
      Formulas move with their row, relative references following. '' or why not }
    function SortRows(c1, r1, c2, r2, keyCol: Integer; ascending: Boolean): string;
    { copies a cell, shifting the relative references of a formula; '' or the reason }
    function CopyCell(sc, sr, dc, dr: Integer): string;

    function CellValue(col, row: Integer): TValue; override;
    procedure VisitStored(c1, r1, c2, r2: Integer; visit: TCellVisit); override;
  end;

const
  DEFAULT_COL_WIDTH = 12;
  MIN_COL_WIDTH = 3;
  MAX_COL_WIDTH = 100;

function GeneralFormat: TFormat;
function FormatValue(const v: TValue; const fmt: TFormat): UnicodeString;

implementation

uses
  tsdate;

function GeneralFormat: TFormat;
begin
  Result.Kind := nfGeneral;
  Result.Decimals := 0;
  Result.Thousands := False;
end;

destructor TCell.Destroy;
begin
  Node.Free;
  inherited Destroy;
end;

{ ---- display ---- }

function FormatValue(const v: TValue; const fmt: TFormat): UnicodeString;
var
  i: Int64;
  p: TDec;
begin
  case v.Kind of
    vkEmpty: Exit('');
    vkErr: Exit(UnicodeString(ErrNames[v.Err]));
    vkBool: Exit(TextOf(v));
    vkText: Exit(v.Text);
  end;
  case fmt.Kind of
    nfNumber: Result := UnicodeString(DecToFixed(v.Num, fmt.Decimals, fmt.Thousands));
    nfCurrency:
      begin
        Result := UnicodeString(DecToFixed(DecAbs(v.Num), fmt.Decimals, fmt.Thousands));
        Result := '$' + Result;
        if (DecSign(v.Num) < 0) and (DecSign(DecRound(v.Num, fmt.Decimals, rmHalfAway)) <> 0) then
          Result := '-' + Result;
      end;
    nfPercent:
      begin
        p := DecMul(v.Num, DecFromInt(100));
        Result := UnicodeString(DecToFixed(p, fmt.Decimals, fmt.Thousands)) + '%';
      end;
    nfDate:
      if DecToInt64(DecRound(v.Num, 0, rmFloor), i) and SerialValid(i) then
        Result := UnicodeString(SerialToIso(i))
      else
        Result := UnicodeString(ErrNames[ecNum]);
  else
    if v.IsDate and DecToInt64(DecRound(v.Num, 0, rmFloor), i) and SerialValid(i) then
      Result := UnicodeString(SerialToIso(i))
    else
      Result := NumToText(v.Num);
  end;
end;

{ ---- what typing means ---- }

{ [-][$]1,234.50[%], or (1,234.50) for a negative; the way it was typed gives the format }
function ParseNumberEntry(const t: UnicodeString; out d: TDec; out fmt: TFormat): Boolean;
var
  s, ip, fp, clean: UnicodeString;
  neg, dollar, pct, commas, paren: Boolean;
  i, k, groups: Integer;
  dotAt: Integer;
begin
  Result := False;
  fmt := GeneralFormat;
  d := DecZero;
  s := t;
  neg := False; dollar := False; pct := False; commas := False; paren := False;
  if (Length(s) >= 3) and (s[1] = '(') and (s[Length(s)] = ')') then
  begin
    paren := True;
    s := Copy(s, 2, Length(s) - 2);
  end;
  if (s <> '') and ((s[1] = '-') or (s[1] = '+')) then
  begin
    neg := s[1] = '-';
    s := Copy(s, 2, MaxInt);
  end;
  if (s <> '') and (s[1] = '$') then
  begin
    dollar := True;
    s := Copy(s, 2, MaxInt);
    if (s <> '') and ((s[1] = '-') or (s[1] = '+')) then
    begin
      neg := neg or (s[1] = '-');
      s := Copy(s, 2, MaxInt);
    end;
  end;
  if (s <> '') and (s[Length(s)] = '%') then
  begin
    pct := True;
    s := Copy(s, 1, Length(s) - 1);
  end;
  if s = '' then Exit;
  dotAt := Pos('.', string(s));
  if dotAt > 0 then
  begin
    ip := Copy(s, 1, dotAt - 1);
    fp := Copy(s, dotAt + 1, MaxInt);
  end
  else
  begin
    ip := s;
    fp := '';
  end;
  for i := 1 to Length(fp) do
    if (fp[i] < '0') or (fp[i] > '9') then Exit;
  if Pos(',', string(ip)) > 0 then
  begin
    commas := True;
    { the groups must be 1-3 digits and then exact threes }
    groups := 0;
    k := 1;
    clean := '';
    while k <= Length(ip) do
    begin
      i := k;
      while (i <= Length(ip)) and (ip[i] <> ',') do Inc(i);
      if groups = 0 then
      begin
        if (i - k < 1) or (i - k > 3) then Exit;
      end
      else if i - k <> 3 then Exit;
      clean := clean + Copy(ip, k, i - k);
      Inc(groups);
      k := i + 1;
    end;
    if ip[Length(ip)] = ',' then Exit;
    ip := clean;
  end;
  for i := 1 to Length(ip) do
    if (ip[i] < '0') or (ip[i] > '9') then Exit;
  if (ip = '') and (fp = '') then Exit;
  if fp <> '' then clean := ip + '.' + fp else clean := ip;
  if clean = '' then Exit;
  if not DecFromStr(clean, d) then Exit;
  if pct then
    if not DecDiv(d, DecFromInt(100), d) then Exit;
  if neg or paren then d := DecNeg(d);
  if dollar then
  begin
    fmt.Kind := nfCurrency;
    fmt.Decimals := Length(fp);
    if fmt.Decimals < 2 then fmt.Decimals := 2;
    fmt.Thousands := True;
  end
  else if pct then
  begin
    fmt.Kind := nfPercent;
    fmt.Decimals := Length(fp);
  end
  else if commas or (fp <> '') then
  begin
    fmt.Kind := nfNumber;
    fmt.Decimals := Length(fp);
    fmt.Thousands := commas;
  end;
  Result := True;
end;

class function TSheet.ParseEntry(const text: UnicodeString; out ent: TEntry): Boolean;
var
  t: UnicodeString;
  d: TDec;
  serial: Int64;
  fmt: TFormat;
begin
  ent.Raw := text;
  ent.Fmt := GeneralFormat;
  ent.Value := VEmpty;
  Result := text <> '';
  if not Result then Exit;
  if text[1] = '''' then
  begin
    ent.Kind := ckText;
    ent.Value := VText(Copy(text, 2, MaxInt));
    Exit;
  end;
  t := UnicodeString(Trim(string(text)));
  if (Length(t) > 1) and (t[1] = '=') then
  begin
    ent.Kind := ckFormula;
    ent.Raw := t;
    Exit;
  end;
  if UpperCase(string(t)) = 'TRUE' then
  begin
    ent.Kind := ckBool;
    ent.Value := VBool(True);
    Exit;
  end;
  if UpperCase(string(t)) = 'FALSE' then
  begin
    ent.Kind := ckBool;
    ent.Value := VBool(False);
    Exit;
  end;
  { a date typed month first (8/1/2026) is kept as the unambiguous 2026-08-01 }
  if ParseUsDate(t, serial) then
  begin
    ent.Raw := UnicodeString(SerialToIso(serial));
    ent.Kind := ckNumber;
    ent.Value := VNum(DecFromInt(serial));
    ent.Fmt.Kind := nfDate;
    Exit;
  end;
  if ParseIsoDate(t, serial) then
  begin
    ent.Kind := ckNumber;
    ent.Value := VNum(DecFromInt(serial));
    ent.Fmt.Kind := nfDate;
    Exit;
  end;
  if ParseNumberEntry(t, d, fmt) then
  begin
    ent.Kind := ckNumber;
    ent.Value := VNum(d);
    ent.Fmt := fmt;
    Exit;
  end;
  ent.Kind := ckText;
  ent.Value := VText(text);
end;

{ ---- the sheet ---- }

constructor TSheet.Create;
begin
  inherited Create;
  FCells := specialize TDictionary<Int64, TCell>.Create;
  FWidths := specialize TDictionary<Integer, Integer>.Create;
  FColFmts := specialize TDictionary<Integer, TFormat>.Create;
  Today := TodaySerial;
end;

destructor TSheet.Destroy;
var
  c: TCell;
begin
  for c in FCells.Values do c.Free;
  FCells.Free;
  FWidths.Free;
  FColFmts.Free;
  inherited Destroy;
end;

function TSheet.Key(col, row: Integer): Int64;
begin
  Result := Int64(row) * 16384 + col;
end;

function TSheet.Find(col, row: Integer): TCell;
begin
  if (col < 0) or (col > MAX_COL) or (row < 0) or (row > MAX_ROW) then Exit(nil);
  if not FCells.TryGetValue(Key(col, row), Result) then Result := nil;
end;

function TSheet.SetEntry(col, row: Integer; const text: UnicodeString): string;
var
  ent: TEntry;
  c: TCell;
  node: TNode;
  err: string;
  deps: TRangeArray;
begin
  Result := '';
  if (col < 0) or (col > MAX_COL) or (row < 0) or (row > MAX_ROW) then Exit('That cell is outside the sheet');
  if not ParseEntry(text, ent) then
  begin
    ClearCell(col, row);
    Exit;
  end;
  node := nil;
  deps := nil;
  if ent.Kind = ckFormula then
  begin
    if not ParseFormula(ent.Raw, node, err) then Exit(err);
    CollectRanges(node, deps);
  end;
  c := Find(col, row);
  if c = nil then
  begin
    c := TCell.Create;
    c.Col := col;
    c.Row := row;
    FCells.Add(Key(col, row), c);
  end
  else
    FreeAndNil(c.Node);
  c.Raw := ent.Raw;
  c.Kind := ent.Kind;
  c.Value := ent.Value;
  c.Fmt := ent.Fmt;
  { a column's own format wins over the plain forms typing gives (12 or 12.50); $, % and dates stay as typed }
  if (ent.Fmt.Kind in [nfGeneral, nfNumber]) and (ent.Kind in [ckNumber, ckFormula]) and (ColFormat(col).Kind <> nfGeneral) then
    c.Fmt := ColFormat(col);
  c.Node := node;
  c.Deps := deps;
  FDirty := True;
end;

procedure TSheet.ClearCell(col, row: Integer);
var
  c: TCell;
begin
  c := Find(col, row);
  if c = nil then Exit;
  FCells.Remove(Key(col, row));
  c.Free;
  FDirty := True;
end;

function TSheet.Exists(col, row: Integer): Boolean;
begin
  Result := Find(col, row) <> nil;
end;

function TSheet.GetRaw(col, row: Integer): UnicodeString;
var
  c: TCell;
begin
  c := Find(col, row);
  if c = nil then Result := '' else Result := c.Raw;
end;

function TSheet.GetKind(col, row: Integer): TCellKind;
var
  c: TCell;
begin
  c := Find(col, row);
  if c = nil then Result := ckText else Result := c.Kind;
end;

function TSheet.GetFormat(col, row: Integer): TFormat;
var
  c: TCell;
begin
  c := Find(col, row);
  if c = nil then Result := GeneralFormat else Result := c.Fmt;
end;

procedure TSheet.SetFormat(col, row: Integer; const fmt: TFormat);
var
  c: TCell;
begin
  c := Find(col, row);
  if c <> nil then c.Fmt := fmt;
end;

function TSheet.CellCount: Integer;
begin
  Result := FCells.Count;
end;

function TSheet.Extent(out lastCol, lastRow: Integer): Boolean;
var
  c: TCell;
begin
  lastCol := -1;
  lastRow := -1;
  for c in FCells.Values do
  begin
    if c.Col > lastCol then lastCol := c.Col;
    if c.Row > lastRow then lastRow := c.Row;
  end;
  Result := lastRow >= 0;
end;

{ the formula cells a formula reads }
function TSheet.DepCells(c: TCell): Classes.TList;
var
  i, cc, rr: Integer;
  r: TRange;
  other: TCell;
  area: Int64;
begin
  Result := Classes.TList.Create;
  for i := 0 to High(c.Deps) do
  begin
    r := c.Deps[i];
    area := Int64(r.C2 - r.C1 + 1) * (r.R2 - r.R1 + 1);
    if area <= FCells.Count then
    begin
      for rr := r.R1 to r.R2 do
        for cc := r.C1 to r.C2 do
        begin
          other := Find(cc, rr);
          if (other <> nil) and (other.Kind = ckFormula) then Result.Add(other);
        end;
    end
    else
      for other in FCells.Values do
        if (other.Kind = ckFormula) and (other.Col >= r.C1) and (other.Col <= r.C2) and
           (other.Row >= r.R1) and (other.Row <= r.R2) then Result.Add(other);
  end;
end;

type
  TFrame = record
    Cell: TCell;
    Deps: Classes.TList;
    Idx: Integer;
  end;

{ evaluates root after everything it reads, without recursion }
procedure TSheet.Evaluate(root: TCell);
var
  stack: array of TFrame;
  top, k: Integer;
  d: TCell;
  f: TFrame;
begin
  SetLength(stack, 16);
  top := 0;
  stack[0].Cell := root;
  stack[0].Deps := DepCells(root);
  stack[0].Idx := 0;
  root.Mark := 1;
  try
    while top >= 0 do
    begin
      if stack[top].Idx < stack[top].Deps.Count then
      begin
        d := TCell(stack[top].Deps[stack[top].Idx]);
        Inc(stack[top].Idx);
        if d.Mark = 0 then
        begin
          Inc(top);
          if top >= Length(stack) then SetLength(stack, Length(stack) * 2);
          stack[top].Cell := d;
          stack[top].Deps := DepCells(d);
          stack[top].Idx := 0;
          d.Mark := 1;
        end
        else if d.Mark = 1 then
        begin
          { a loop: d is somewhere below on the stack, everything from there up is in it }
          k := top;
          while (k > 0) and (stack[k].Cell <> d) do Dec(k);
          while k <= top do
          begin
            stack[k].Cell.Circ := True;
            Inc(k);
          end;
        end;
      end
      else
      begin
        f := stack[top];
        if f.Cell.Circ then f.Cell.Value := VErr(ecCirc)
        else f.Cell.Value := EvalFormula(f.Cell.Node, Self);
        f.Cell.Mark := 2;
        f.Deps.Free;
        stack[top].Deps := nil;
        Dec(top);
      end;
    end;
  finally
    for k := 0 to top do stack[k].Deps.Free;
  end;
end;

procedure TSheet.Recalc;
var
  c: TCell;
  list: array of TCell;
  n, i, j: Integer;
  tmp: TCell;
begin
  if not FDirty then Exit;
  n := 0;
  SetLength(list, FCells.Count);
  for c in FCells.Values do
    if c.Kind = ckFormula then
    begin
      c.Mark := 0;
      c.Circ := False;
      list[n] := c;
      Inc(n);
    end;
  { row by row, left to right: most formulas then find what they read already done }
  for i := 1 to n - 1 do
  begin
    tmp := list[i];
    j := i - 1;
    while (j >= 0) and ((list[j].Row > tmp.Row) or ((list[j].Row = tmp.Row) and (list[j].Col > tmp.Col))) do
    begin
      list[j + 1] := list[j];
      Dec(j);
    end;
    list[j + 1] := tmp;
  end;
  for i := 0 to n - 1 do
    if list[i].Mark = 0 then Evaluate(list[i]);
  FDirty := False;
end;

function TSheet.Value(col, row: Integer): TValue;
var
  c: TCell;
begin
  Recalc;
  c := Find(col, row);
  if c = nil then Result := VEmpty else Result := c.Value;
end;

function TSheet.CellValue(col, row: Integer): TValue;
var
  c: TCell;
begin
  c := Find(col, row);
  if c = nil then Exit(VEmpty);
  if c.Kind = ckFormula then
  begin
    if c.Mark = 0 then Evaluate(c)                 { read before its turn, e.g. a SUMIF sum range }
    else if c.Mark = 1 then Exit(VErr(ecCirc));
  end;
  Result := c.Value;
  { a cell shown as a date is a date to the formulas that read it, so date - date is a number of days }
  if (c.Fmt.Kind = nfDate) and (Result.Kind = vkNum) then Result.IsDate := True;
end;

procedure TSheet.VisitStored(c1, r1, c2, r2: Integer; visit: TCellVisit);
var
  cc, rr: Integer;
  c: TCell;
  area: Int64;
  hits: array of TCell;
  n, i, j: Integer;
  tmp: TCell;
begin
  area := Int64(c2 - c1 + 1) * (r2 - r1 + 1);
  if area <= FCells.Count then
  begin
    for rr := r1 to r2 do
      for cc := c1 to c2 do
      begin
        c := Find(cc, rr);
        if c <> nil then visit(cc, rr, CellValue(cc, rr));
      end;
  end
  else
  begin
    { a big rectangle over a small sheet: go through the cells, in row order }
    n := 0;
    SetLength(hits, FCells.Count);
    for c in FCells.Values do
      if (c.Col >= c1) and (c.Col <= c2) and (c.Row >= r1) and (c.Row <= r2) then
      begin
        hits[n] := c;
        Inc(n);
      end;
    for i := 1 to n - 1 do
    begin
      tmp := hits[i];
      j := i - 1;
      while (j >= 0) and ((hits[j].Row > tmp.Row) or ((hits[j].Row = tmp.Row) and (hits[j].Col > tmp.Col))) do
      begin
        hits[j + 1] := hits[j];
        Dec(j);
      end;
      hits[j + 1] := tmp;
    end;
    for i := 0 to n - 1 do visit(hits[i].Col, hits[i].Row, CellValue(hits[i].Col, hits[i].Row));
  end;
end;

function TSheet.Display(col, row: Integer): UnicodeString;
var
  c: TCell;
  v: TValue;
begin
  c := Find(col, row);
  if c = nil then Exit('');
  v := Value(col, row);
  Result := FormatValue(v, c.Fmt);
end;

function TSheet.CopyCell(sc, sr, dc, dr: Integer): string;
var
  src: TCell;
  text: UnicodeString;
  fmt: TFormat;
begin
  Result := '';
  src := Find(sc, sr);
  if src = nil then
  begin
    ClearCell(dc, dr);
    Exit;
  end;
  text := src.Raw;
  fmt := src.Fmt;
  if src.Kind = ckFormula then
    if not ShiftFormula(src.Raw, dc - sc, dr - sr, text) then Exit('Cannot shift the formula');
  Result := SetEntry(dc, dr, text);
  if Result = '' then SetFormat(dc, dr, fmt);
end;

procedure TSheet.Clear;
var
  c: TCell;
begin
  for c in FCells.Values do c.Free;
  FCells.Clear;
  FWidths.Clear;
  FColFmts.Clear;
  FDirty := True;
end;

function TSheet.ColWidth(col: Integer): Integer;
begin
  if not FWidths.TryGetValue(col, Result) then Result := DEFAULT_COL_WIDTH;
end;

procedure TSheet.SetColWidth(col, width: Integer);
begin
  if (col < 0) or (col > MAX_COL) then Exit;
  if width < MIN_COL_WIDTH then width := MIN_COL_WIDTH;
  if width > MAX_COL_WIDTH then width := MAX_COL_WIDTH;
  if width = DEFAULT_COL_WIDTH then FWidths.Remove(col) else FWidths.AddOrSetValue(col, width);
end;

function TSheet.CustomWidthCols: TIntArray;
var
  k, n, i, j, tmp: Integer;
begin
  SetLength(Result, FWidths.Count);
  n := 0;
  for k in FWidths.Keys do
  begin
    Result[n] := k;
    Inc(n);
  end;
  for i := 1 to n - 1 do
  begin
    tmp := Result[i];
    j := i - 1;
    while (j >= 0) and (Result[j] > tmp) do
    begin
      Result[j + 1] := Result[j];
      Dec(j);
    end;
    Result[j + 1] := tmp;
  end;
end;

procedure TSheet.Invalidate;
begin
  FDirty := True;
end;

function TSheet.ColFormat(col: Integer): TFormat;
begin
  if not FColFmts.TryGetValue(col, Result) then Result := GeneralFormat;
end;

procedure TSheet.SetColFormat(col: Integer; const fmt: TFormat);
begin
  if (col < 0) or (col > MAX_COL) then Exit;
  if fmt.Kind = nfGeneral then FColFmts.Remove(col) else FColFmts.AddOrSetValue(col, fmt);
end;

function TSheet.CustomFormatCols: TIntArray;
var
  k, n, i, j, tmp: Integer;
begin
  SetLength(Result, FColFmts.Count);
  n := 0;
  for k in FColFmts.Keys do
  begin
    Result[n] := k;
    Inc(n);
  end;
  for i := 1 to n - 1 do
  begin
    tmp := Result[i];
    j := i - 1;
    while (j >= 0) and (Result[j] > tmp) do
    begin
      Result[j + 1] := Result[j];
      Dec(j);
    end;
    Result[j + 1] := tmp;
  end;
end;

function TSheet.ExpectedFormat(col, row: Integer): TFormat;
var
  c: TCell;
  ent: TEntry;
begin
  Result := GeneralFormat;
  c := Find(col, row);
  if c = nil then Exit;
  if c.Kind = ckFormula then Exit(ColFormat(col));
  if ParseEntry(c.Raw, ent) then
  begin
    Result := ent.Fmt;
    if (Result.Kind in [nfGeneral, nfNumber]) and (ent.Kind = ckNumber) and (ColFormat(col).Kind <> nfGeneral) then
      Result := ColFormat(col);
  end;
end;

{ ---- inserting and deleting rows and columns ---- }

type
  TStructMapper = class
    IsRow, Remove: Boolean;
    At, Count: Integer;
    function MapOne(v: Integer; out nv: Integer): Boolean;
    function MapAxis(var a, b: Integer): Boolean;
    function Map(var col, row: Integer; absCol, absRow: Boolean): Boolean;
    function MapRange(var c1, r1, c2, r2: Integer): Boolean;
  end;

function TStructMapper.MapOne(v: Integer; out nv: Integer): Boolean;
begin
  nv := v;
  if Remove then
  begin
    if (v >= At) and (v <= At + Count - 1) then Exit(False);
    if v > At + Count - 1 then nv := v - Count;
    Result := True;
  end
  else
  begin
    if v >= At then nv := v + Count;
    if IsRow then Result := nv <= MAX_ROW else Result := nv <= MAX_COL;
  end;
end;

{ one side of a block, which may be written the wrong way round }
function TStructMapper.MapAxis(var a, b: Integer): Boolean;
var
  lo, hi, nlo, nhi: Integer;
  swapped: Boolean;
begin
  swapped := a > b;
  if swapped then begin lo := b; hi := a; end else begin lo := a; hi := b; end;
  if Remove then
  begin
    if hi < At then begin nlo := lo; nhi := hi; end
    else if lo > At + Count - 1 then begin nlo := lo - Count; nhi := hi - Count; end
    else
    begin
      { it overlaps what is deleted: what is left of it closes up }
      if lo < At then nlo := lo else nlo := At;
      if hi > At + Count - 1 then nhi := hi - Count else nhi := At - 1;
      if nhi < nlo then Exit(False);
    end;
  end
  else
  begin
    if not MapOne(lo, nlo) then Exit(False);
    if not MapOne(hi, nhi) then Exit(False);
  end;
  if swapped then begin a := nhi; b := nlo; end else begin a := nlo; b := nhi; end;
  Result := True;
end;

function TStructMapper.Map(var col, row: Integer; absCol, absRow: Boolean): Boolean;
begin
  if IsRow then Result := MapOne(row, row) else Result := MapOne(col, col);
end;

function TStructMapper.MapRange(var c1, r1, c2, r2: Integer): Boolean;
begin
  if IsRow then Result := MapAxis(r1, r2) else Result := MapAxis(c1, c2);
end;

procedure TSheet.Restructure(isRow, remove: Boolean; at, count: Integer);
var
  all: array of TCell;
  n, i, pos, np, k, nk: Integer;
  c: TCell;
  mapper: TStructMapper;
  res: UnicodeString;
  node: TNode;
  err: string;
  keys, widths: TIntArray;
  fmts: array of TFormat;
begin
  if count < 1 then Exit;
  mapper := TStructMapper.Create;
  try
    mapper.IsRow := isRow;
    mapper.Remove := remove;
    mapper.At := at;
    mapper.Count := count;
    n := 0;
    SetLength(all, FCells.Count);
    for c in FCells.Values do
    begin
      all[n] := c;
      Inc(n);
    end;
    FCells.Clear;
    for i := 0 to n - 1 do
    begin
      c := all[i];
      if isRow then pos := c.Row else pos := c.Col;
      if not mapper.MapOne(pos, np) then
      begin
        c.Free;
        Continue;
      end;
      if isRow then c.Row := np else c.Col := np;
      if c.Kind = ckFormula then
        if RewriteRefs(c.Raw, @mapper.Map, res, @mapper.MapRange) then
        begin
          node := nil;
          if ParseFormula(res, node, err) then
          begin
            c.Node.Free;
            c.Node := node;
            c.Raw := res;
            c.Deps := nil;
            CollectRanges(node, c.Deps);
          end;
        end;
      FCells.Add(Key(c.Col, c.Row), c);
    end;
    if not isRow then
    begin
      { column widths and formats move with their columns: take them all out first, then put them back }
      keys := CustomWidthCols;
      SetLength(widths, Length(keys));
      for k := 0 to High(keys) do widths[k] := ColWidth(keys[k]);
      FWidths.Clear;
      for k := 0 to High(keys) do
        if mapper.MapOne(keys[k], nk) then FWidths.AddOrSetValue(nk, widths[k]);
      keys := CustomFormatCols;
      SetLength(fmts, Length(keys));
      for k := 0 to High(keys) do fmts[k] := ColFormat(keys[k]);
      FColFmts.Clear;
      for k := 0 to High(keys) do
        if mapper.MapOne(keys[k], nk) then FColFmts.AddOrSetValue(nk, fmts[k]);
    end;
  finally
    mapper.Free;
  end;
  FDirty := True;
end;

procedure TSheet.InsertRows(at, count: Integer);
begin
  Restructure(True, False, at, count);
end;

procedure TSheet.DeleteRows(at, count: Integer);
begin
  Restructure(True, True, at, count);
end;

procedure TSheet.InsertCols(at, count: Integer);
begin
  Restructure(False, False, at, count);
end;

procedure TSheet.DeleteCols(at, count: Integer);
begin
  Restructure(False, True, at, count);
end;

{ ---- sorting ---- }

function SortRank(const v: TValue): Integer;
begin
  case v.Kind of
    vkNum: Result := 0;
    vkText: Result := 1;
    vkBool: Result := 2;
    vkErr: Result := 3;
  else
    Result := 4;
  end;
end;

{ empty cells are not compared here: they always go last }
function SortCompare(const a, b: TValue): Integer;
var
  ra, rb: Integer;
  x, y: UnicodeString;
begin
  ra := SortRank(a);
  rb := SortRank(b);
  if ra <> rb then
  begin
    if ra < rb then Exit(-1) else Exit(1);
  end;
  case ra of
    0: Result := DecCmpSpread(a.Num, b.Num);
    1:
      begin
        x := UnicodeLowerCase(a.Text);
        y := UnicodeLowerCase(b.Text);
        if x < y then Result := -1 else if x > y then Result := 1 else Result := 0;
      end;
    2: Result := Ord(a.Bool) - Ord(b.Bool);
    3: Result := Ord(a.Err) - Ord(b.Err);
  else
    Result := 0;
  end;
end;

function TSheet.SortRows(c1, r1, c2, r2, keyCol: Integer; ascending: Boolean): string;
type
  TSnap = record
    Has: Boolean;
    Raw: UnicodeString;
    Fmt: TFormat;
  end;
var
  n, i, j, c, t, src, width, cmp, tmp: Integer;
  keys: array of TValue;
  order: array of Integer;
  snap: array of TSnap;
  raw, shifted: UnicodeString;
  err: string;

  function Less(x, y: Integer): Boolean;       { does row x come before row y }
  begin
    if keys[x].Kind = vkEmpty then Exit(False);
    if keys[y].Kind = vkEmpty then Exit(True);
    cmp := SortCompare(keys[x], keys[y]);
    if ascending then Result := cmp < 0 else Result := cmp > 0;
  end;

begin
  Result := '';
  if (r2 <= r1) or (c2 < c1) then Exit;
  if (keyCol < c1) or (keyCol > c2) then Exit('The sort column is not inside the selection');
  n := r2 - r1 + 1;
  width := c2 - c1 + 1;
  SetLength(keys, n);
  SetLength(order, n);
  for i := 0 to n - 1 do
  begin
    keys[i] := Value(keyCol, r1 + i);
    order[i] := i;
  end;
  { insertion sort: stable, and the sheets are small }
  for i := 1 to n - 1 do
  begin
    tmp := order[i];
    j := i - 1;
    while (j >= 0) and Less(tmp, order[j]) do
    begin
      order[j + 1] := order[j];
      Dec(j);
    end;
    order[j + 1] := tmp;
  end;
  SetLength(snap, n * width);
  for i := 0 to n - 1 do
    for c := 0 to width - 1 do
    begin
      snap[i * width + c].Has := Exists(c1 + c, r1 + i);
      if snap[i * width + c].Has then
      begin
        snap[i * width + c].Raw := GetRaw(c1 + c, r1 + i);
        snap[i * width + c].Fmt := GetFormat(c1 + c, r1 + i);
      end;
    end;
  for t := 0 to n - 1 do
  begin
    src := order[t];
    for c := 0 to width - 1 do
    begin
      if not snap[src * width + c].Has then
      begin
        ClearCell(c1 + c, r1 + t);
        Continue;
      end;
      raw := snap[src * width + c].Raw;
      if (Length(raw) > 1) and (raw[1] = '=') then
        if ShiftFormula(raw, 0, t - src, shifted) then raw := shifted;
      err := SetEntry(c1 + c, r1 + t, raw);
      if err = '' then SetFormat(c1 + c, r1 + t, snap[src * width + c].Fmt) else Result := err;
    end;
  end;
  FDirty := True;
end;

end.
