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
    function Key(col, row: Integer): Int64;
    function Find(col, row: Integer): TCell;
    procedure Evaluate(root: TCell);
    function DepCells(c: TCell): Classes.TList;
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
    { copies a cell, shifting the relative references of a formula; '' or the reason }
    function CopyCell(sc, sr, dc, dr: Integer): string;

    function CellValue(col, row: Integer): TValue; override;
    procedure VisitStored(c1, r1, c2, r2: Integer; visit: TCellVisit); override;
  end;

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
  Today := TodaySerial;
end;

destructor TSheet.Destroy;
var
  c: TCell;
begin
  for c in FCells.Values do c.Free;
  FCells.Free;
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

end.
