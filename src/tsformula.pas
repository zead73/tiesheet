{ tsformula - formula text to a tree, the tree to a value, and rewriting references.

  The syntax is the familiar one: =SUM(A1:A9)*1.07, =IF(B2>100,"big","small"), $A$1 for a fixed
  reference, & to join text, % after a number.  Arguments are separated by , or ;.
  Cells are (column, row) pairs counted from 0, so A1 is (0, 0).

  Operator order, from the loosest: comparisons, &, + -, * /, ^ (left to right: 2^3^2 is 64),
  then a minus sign (so -2^2 is 4), then %.  This is what LibreOffice Calc does. }
unit tsformula;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, tsdec, tsvalue;

const
  MAX_COL = 16383;         { XFD }
  MAX_ROW = 1048575;

type
  TRange = record
    C1, R1, C2, R2: Integer;
  end;
  TRangeArray = array of TRange;

  TNodeKind = (nkNum, nkStr, nkBool, nkErr, nkRef, nkRange, nkUnary, nkPercent, nkBinary, nkFunc);

  TNode = class
    Kind: TNodeKind;
    Num: TDec;
    Str: UnicodeString;
    Bool: Boolean;
    Err: TErrCode;
    Col, Row, Col2, Row2: Integer;
    Op: string;
    Fn: Integer;                 { index into the function table, -1 when the name is unknown }
    Name: string;
    Args: array of TNode;
    destructor Destroy; override;
  end;

  TCellVisit = procedure(col, row: Integer; const v: TValue) of object;

  { what a formula needs from the sheet it lives in }
  TEvalCtx = class
  public
    Today: Int64;                { serial day number, set by whoever creates it (a test can fix it) }
    function CellValue(col, row: Integer): TValue; virtual; abstract;
    { calls visit for every cell that holds something inside the rectangle }
    procedure VisitStored(c1, r1, c2, r2: Integer; visit: TCellVisit); virtual; abstract;
  end;

  { rewrites one reference; returns False when it no longer exists (it becomes #REF!) }
  TRefMap = function(var col, row: Integer; absCol, absRow: Boolean): Boolean of object;
  { the same for a block A1:B2 as a whole, for changes that can shrink or stretch it }
  TRangeMap = function(var c1, r1, c2, r2: Integer): Boolean of object;

function ParseFormula(const text: UnicodeString; out root: TNode; out err: string): Boolean;
function EvalFormula(root: TNode; ctx: TEvalCtx): TValue;
procedure CollectRanges(n: TNode; var list: TRangeArray);

function RewriteRefs(const f: UnicodeString; map: TRefMap; out res: UnicodeString; rmap: TRangeMap = nil): Boolean;
function ShiftFormula(const f: UnicodeString; dCol, dRow: Integer; out res: UnicodeString): Boolean;

function ColName(col: Integer): string;
function CellName(col, row: Integer): string;                           { A1 }
function ParseCellName(const s: UnicodeString; out col, row: Integer): Boolean;

implementation

uses
  Math, tsdate;

{ ---- names of cells ---- }

function ColName(col: Integer): string;
begin
  Result := '';
  Inc(col);
  while col > 0 do
  begin
    Result := Chr(65 + (col - 1) mod 26) + Result;
    col := (col - 1) div 26;
  end;
end;

function CellName(col, row: Integer): string;
begin
  Result := ColName(col) + IntToStr(row + 1);
end;

function RefText(col, row: Integer; absCol, absRow: Boolean): UnicodeString;
begin
  Result := '';
  if absCol then Result := '$';
  Result := Result + UnicodeString(ColName(col));
  if absRow then Result := Result + '$';
  Result := Result + UnicodeString(IntToStr(row + 1));
end;

function IsLetter(c: WideChar): Boolean;
begin
  Result := ((c >= 'A') and (c <= 'Z')) or ((c >= 'a') and (c <= 'z'));
end;

function IsDigit(c: WideChar): Boolean;
begin
  Result := (c >= '0') and (c <= '9');
end;

{ a cell reference starting at s[i]; on success j is the first position after it }
function MatchCell(const s: UnicodeString; i: Integer; out col, row: Integer;
  out absCol, absRow: Boolean; out j: Integer): Boolean;
var
  n, k, m, p, letters, v: Integer;
begin
  Result := False;
  n := Length(s);
  absCol := False;
  absRow := False;
  k := i;
  if (k <= n) and (s[k] = '$') then begin absCol := True; Inc(k); end;
  m := k;
  while (m <= n) and IsLetter(s[m]) do Inc(m);
  letters := m - k;
  if (letters < 1) or (letters > 3) then Exit;
  col := 0;
  for p := k to m - 1 do col := col * 26 + (Ord(UpCase(AnsiChar(s[p]))) - 64);
  Dec(col);
  if (m <= n) and (s[m] = '$') then begin absRow := True; Inc(m); end;
  p := m;
  v := 0;
  while (p <= n) and IsDigit(s[p]) do
  begin
    if v < 100000000 then v := v * 10 + (Ord(s[p]) - 48);
    Inc(p);
  end;
  if p = m then Exit;
  if (p <= n) and (IsLetter(s[p]) or IsDigit(s[p]) or (s[p] = '_') or (s[p] = '.') or (s[p] = '(')) then Exit;
  if (col > MAX_COL) or (v < 1) or (v - 1 > MAX_ROW) then Exit;
  row := v - 1;
  j := p;
  Result := True;
end;

function ParseCellName(const s: UnicodeString; out col, row: Integer): Boolean;
var
  ac, ar: Boolean;
  j: Integer;
begin
  Result := MatchCell(s, 1, col, row, ac, ar, j) and (j = Length(s) + 1);
end;

{ ---- the tree ---- }

destructor TNode.Destroy;
var
  i: Integer;
begin
  for i := 0 to High(Args) do Args[i].Free;
  inherited Destroy;
end;

{ ---- the function table ---- }

type
  TFn = (fnSum, fnAverage, fnMin, fnMax, fnCount, fnCounta, fnProduct, fnAbs, fnRound, fnRoundUp,
    fnRoundDown, fnInt, fnMod, fnPower, fnSqrt, fnIf, fnAnd, fnOr, fnNot, fnIfError, fnTrue, fnFalse,
    fnLen, fnLeft, fnRight, fnMid, fnUpper, fnLower, fnTrim, fnConcat, fnValue, fnSumIf, fnCountIf,
    fnAverageIf, fnDate, fnYear, fnMonth, fnDay, fnWeekday, fnToday, fnDays, fnEdate, fnDatedif, fnIsBlank,
    fnIsNumber, fnIsText, fnIsError);

  TFuncInfo = record
    Name: string;
    Id: TFn;
    MinArgs, MaxArgs: Integer;      { MaxArgs -1: any number }
  end;

const
  FuncTable: array[0..48] of TFuncInfo = (
    (Name: 'SUM'; Id: fnSum; MinArgs: 1; MaxArgs: -1),
    (Name: 'AVERAGE'; Id: fnAverage; MinArgs: 1; MaxArgs: -1),
    (Name: 'MIN'; Id: fnMin; MinArgs: 1; MaxArgs: -1),
    (Name: 'MAX'; Id: fnMax; MinArgs: 1; MaxArgs: -1),
    (Name: 'COUNT'; Id: fnCount; MinArgs: 1; MaxArgs: -1),
    (Name: 'COUNTA'; Id: fnCounta; MinArgs: 1; MaxArgs: -1),
    (Name: 'PRODUCT'; Id: fnProduct; MinArgs: 1; MaxArgs: -1),
    (Name: 'ABS'; Id: fnAbs; MinArgs: 1; MaxArgs: 1),
    (Name: 'ROUND'; Id: fnRound; MinArgs: 2; MaxArgs: 2),
    (Name: 'ROUNDUP'; Id: fnRoundUp; MinArgs: 2; MaxArgs: 2),
    (Name: 'ROUNDDOWN'; Id: fnRoundDown; MinArgs: 2; MaxArgs: 2),
    (Name: 'INT'; Id: fnInt; MinArgs: 1; MaxArgs: 1),
    (Name: 'MOD'; Id: fnMod; MinArgs: 2; MaxArgs: 2),
    (Name: 'POWER'; Id: fnPower; MinArgs: 2; MaxArgs: 2),
    (Name: 'SQRT'; Id: fnSqrt; MinArgs: 1; MaxArgs: 1),
    (Name: 'IF'; Id: fnIf; MinArgs: 2; MaxArgs: 3),
    (Name: 'AND'; Id: fnAnd; MinArgs: 1; MaxArgs: -1),
    (Name: 'OR'; Id: fnOr; MinArgs: 1; MaxArgs: -1),
    (Name: 'NOT'; Id: fnNot; MinArgs: 1; MaxArgs: 1),
    (Name: 'IFERROR'; Id: fnIfError; MinArgs: 2; MaxArgs: 2),
    (Name: 'TRUE'; Id: fnTrue; MinArgs: 0; MaxArgs: 0),
    (Name: 'FALSE'; Id: fnFalse; MinArgs: 0; MaxArgs: 0),
    (Name: 'LEN'; Id: fnLen; MinArgs: 1; MaxArgs: 1),
    (Name: 'LEFT'; Id: fnLeft; MinArgs: 1; MaxArgs: 2),
    (Name: 'RIGHT'; Id: fnRight; MinArgs: 1; MaxArgs: 2),
    (Name: 'MID'; Id: fnMid; MinArgs: 3; MaxArgs: 3),
    (Name: 'UPPER'; Id: fnUpper; MinArgs: 1; MaxArgs: 1),
    (Name: 'LOWER'; Id: fnLower; MinArgs: 1; MaxArgs: 1),
    (Name: 'TRIM'; Id: fnTrim; MinArgs: 1; MaxArgs: 1),
    (Name: 'CONCATENATE'; Id: fnConcat; MinArgs: 1; MaxArgs: -1),
    (Name: 'CONCAT'; Id: fnConcat; MinArgs: 1; MaxArgs: -1),
    (Name: 'VALUE'; Id: fnValue; MinArgs: 1; MaxArgs: 1),
    (Name: 'SUMIF'; Id: fnSumIf; MinArgs: 2; MaxArgs: 3),
    (Name: 'COUNTIF'; Id: fnCountIf; MinArgs: 2; MaxArgs: 2),
    (Name: 'AVERAGEIF'; Id: fnAverageIf; MinArgs: 2; MaxArgs: 3),
    (Name: 'DATE'; Id: fnDate; MinArgs: 3; MaxArgs: 3),
    (Name: 'YEAR'; Id: fnYear; MinArgs: 1; MaxArgs: 1),
    (Name: 'MONTH'; Id: fnMonth; MinArgs: 1; MaxArgs: 1),
    (Name: 'DAY'; Id: fnDay; MinArgs: 1; MaxArgs: 1),
    (Name: 'WEEKDAY'; Id: fnWeekday; MinArgs: 1; MaxArgs: 2),
    (Name: 'TODAY'; Id: fnToday; MinArgs: 0; MaxArgs: 0),
    (Name: 'DAYS'; Id: fnDays; MinArgs: 2; MaxArgs: 2),
    (Name: 'EDATE'; Id: fnEdate; MinArgs: 2; MaxArgs: 2),
    (Name: 'DATEDIF'; Id: fnDatedif; MinArgs: 3; MaxArgs: 3),
    (Name: 'ISBLANK'; Id: fnIsBlank; MinArgs: 1; MaxArgs: 1),
    (Name: 'ISNUMBER'; Id: fnIsNumber; MinArgs: 1; MaxArgs: 1),
    (Name: 'ISTEXT'; Id: fnIsText; MinArgs: 1; MaxArgs: 1),
    (Name: 'ISERROR'; Id: fnIsError; MinArgs: 1; MaxArgs: 1),
    (Name: 'ISERR'; Id: fnIsError; MinArgs: 1; MaxArgs: 1)
  );

function FindFunc(const name: string): Integer;
var
  i: Integer;
begin
  for i := 0 to High(FuncTable) do
    if FuncTable[i].Name = name then Exit(i);
  Result := -1;
end;

{ ---- the lexer ---- }

type
  TTokKind = (tkEnd, tkNum, tkStr, tkIdent, tkCell, tkErr, tkOp, tkLParen, tkRParen, tkComma);

  TToken = record
    Kind: TTokKind;
    Text: UnicodeString;
    Pos, Len: Integer;
    Num: TDec;
    Col, Row: Integer;
    AbsCol, AbsRow: Boolean;
    Err: TErrCode;
  end;
  TTokens = array of TToken;

function Tokenize(const f: UnicodeString; out toks: TTokens; out err: string): Boolean;
var
  i, j, n, cnt, code: Integer;
  c: WideChar;
  t: TToken;
  s, up: UnicodeString;
  ec: TErrCode;
  found: Boolean;

  procedure Add(const tk: TToken);
  begin
    if cnt >= Length(toks) then SetLength(toks, Length(toks) * 2 + 16);
    toks[cnt] := tk;
    Inc(cnt);
  end;

  function Fail(const msg: string): Boolean;
  begin
    err := msg;
    Result := False;
  end;

begin
  SetLength(toks, 16);
  cnt := 0;
  err := '';
  n := Length(f);
  if (n < 1) or (f[1] <> '=') then Exit(Fail('A formula starts with ='));
  i := 2;
  while i <= n do
  begin
    c := f[i];
    if (c = ' ') or (c = #9) then
    begin
      Inc(i);
      Continue;
    end;
    t := Default(TToken);
    t.Pos := i;
    if IsDigit(c) or ((c = '.') and (i < n) and IsDigit(f[i + 1])) then
    begin
      j := i;
      while (j <= n) and IsDigit(f[j]) do Inc(j);
      if (j <= n) and (f[j] = '.') then
      begin
        Inc(j);
        while (j <= n) and IsDigit(f[j]) do Inc(j);
      end;
      if (j <= n) and ((f[j] = 'e') or (f[j] = 'E')) then
      begin
        code := j + 1;
        if (code <= n) and ((f[code] = '+') or (f[code] = '-')) then Inc(code);
        if (code <= n) and IsDigit(f[code]) then
        begin
          while (code <= n) and IsDigit(f[code]) do Inc(code);
          j := code;
        end;
      end;
      t.Kind := tkNum;
      if not DecFromStr(Copy(f, i, j - i), t.Num) then Exit(Fail('Bad number ' + string(Copy(f, i, j - i))));
      t.Len := j - i;
      Add(t);
      i := j;
    end
    else if c = '"' then
    begin
      s := '';
      j := i + 1;
      found := False;
      while j <= n do
      begin
        if f[j] = '"' then
        begin
          if (j < n) and (f[j + 1] = '"') then
          begin
            s := s + '"';
            Inc(j, 2);
          end
          else
          begin
            found := True;
            Inc(j);
            Break;
          end;
        end
        else
        begin
          s := s + f[j];
          Inc(j);
        end;
      end;
      if not found then Exit(Fail('Missing closing "'));
      t.Kind := tkStr;
      t.Text := s;
      t.Len := j - i;
      Add(t);
      i := j;
    end
    else if c = '#' then
    begin
      found := False;
      for ec := Low(TErrCode) to High(TErrCode) do
      begin
        up := UnicodeString(ErrNames[ec]);
        if UpperCase(string(Copy(f, i, Length(up)))) = string(up) then
        begin
          t.Kind := tkErr;
          t.Err := ec;
          t.Len := Length(up);
          Add(t);
          Inc(i, Length(up));
          found := True;
          Break;
        end;
      end;
      if not found then Exit(Fail('Unexpected #'));
    end
    else if IsLetter(c) or (c = '$') or (c = '_') then
    begin
      if MatchCell(f, i, t.Col, t.Row, t.AbsCol, t.AbsRow, j) then
      begin
        t.Kind := tkCell;
        t.Len := j - i;
        Add(t);
        i := j;
      end
      else
      begin
        if c = '$' then Exit(Fail('Unexpected $'));
        j := i;
        while (j <= n) and (IsLetter(f[j]) or IsDigit(f[j]) or (f[j] = '_') or (f[j] = '.')) do Inc(j);
        t.Kind := tkIdent;
        t.Text := Copy(f, i, j - i);
        t.Len := j - i;
        Add(t);
        i := j;
      end;
    end
    else
    begin
      t.Len := 1;
      case c of
        '(': t.Kind := tkLParen;
        ')': t.Kind := tkRParen;
        ',', ';': t.Kind := tkComma;
        '+', '-', '*', '/', '^', '&', '=', '%', ':':
          begin
            t.Kind := tkOp;
            t.Text := c;
          end;
        '<':
          begin
            t.Kind := tkOp;
            t.Text := '<';
            if (i < n) and (f[i + 1] = '=') then begin t.Text := '<='; t.Len := 2; end
            else if (i < n) and (f[i + 1] = '>') then begin t.Text := '<>'; t.Len := 2; end;
          end;
        '>':
          begin
            t.Kind := tkOp;
            t.Text := '>';
            if (i < n) and (f[i + 1] = '=') then begin t.Text := '>='; t.Len := 2; end;
          end;
      else
        Exit(Fail('Unexpected ' + string(c)));
      end;
      Add(t);
      Inc(i, t.Len);
    end;
  end;
  t := Default(TToken);
  t.Kind := tkEnd;
  t.Pos := n + 1;
  Add(t);
  SetLength(toks, cnt);
  Result := True;
end;

{ ---- the parser ---- }

type
  TParser = class
    Toks: TTokens;
    P: Integer;
    Err: string;
    function Cur: TToken;
    function IsOp(const op: string): Boolean;
    function ParseCompare: TNode;
    function ParseConcat: TNode;
    function ParseAdd: TNode;
    function ParseMul: TNode;
    function ParsePow: TNode;
    function ParseUnary: TNode;
    function ParsePostfix: TNode;
    function ParsePrimary: TNode;
    function Bin(const op: string; l, r: TNode): TNode;
    procedure SetErr(const msg: string);
  end;

function TParser.Cur: TToken;
begin
  Result := Toks[P];
end;

function TParser.IsOp(const op: string): Boolean;
begin
  Result := (Toks[P].Kind = tkOp) and (string(Toks[P].Text) = op);
end;

procedure TParser.SetErr(const msg: string);
begin
  if Err = '' then Err := msg;
end;

function TParser.Bin(const op: string; l, r: TNode): TNode;
begin
  Result := TNode.Create;
  Result.Kind := nkBinary;
  Result.Op := op;
  SetLength(Result.Args, 2);
  Result.Args[0] := l;
  Result.Args[1] := r;
end;

function TParser.ParseCompare: TNode;
var
  op: string;
  r: TNode;
begin
  Result := ParseConcat;
  while (Err = '') and (Cur.Kind = tkOp) and
    ((string(Cur.Text) = '=') or (string(Cur.Text) = '<>') or (string(Cur.Text) = '<') or
     (string(Cur.Text) = '>') or (string(Cur.Text) = '<=') or (string(Cur.Text) = '>=')) do
  begin
    op := string(Cur.Text);
    Inc(P);
    r := ParseConcat;
    Result := Bin(op, Result, r);
  end;
end;

function TParser.ParseConcat: TNode;
var
  r: TNode;
begin
  Result := ParseAdd;
  while (Err = '') and IsOp('&') do
  begin
    Inc(P);
    r := ParseAdd;
    Result := Bin('&', Result, r);
  end;
end;

function TParser.ParseAdd: TNode;
var
  op: string;
  r: TNode;
begin
  Result := ParseMul;
  while (Err = '') and (IsOp('+') or IsOp('-')) do
  begin
    op := string(Cur.Text);
    Inc(P);
    r := ParseMul;
    Result := Bin(op, Result, r);
  end;
end;

function TParser.ParseMul: TNode;
var
  op: string;
  r: TNode;
begin
  Result := ParsePow;
  while (Err = '') and (IsOp('*') or IsOp('/')) do
  begin
    op := string(Cur.Text);
    Inc(P);
    r := ParsePow;
    Result := Bin(op, Result, r);
  end;
end;

function TParser.ParsePow: TNode;
var
  r: TNode;
begin
  Result := ParseUnary;
  while (Err = '') and IsOp('^') do
  begin
    Inc(P);
    r := ParseUnary;
    Result := Bin('^', Result, r);
  end;
end;

function TParser.ParseUnary: TNode;
var
  op: string;
  operand: TNode;
begin
  if (Err = '') and (IsOp('-') or IsOp('+')) then
  begin
    op := string(Cur.Text);
    Inc(P);
    operand := ParseUnary();
    Result := TNode.Create;
    Result.Kind := nkUnary;
    Result.Op := op;
    SetLength(Result.Args, 1);
    Result.Args[0] := operand;
  end
  else
    Result := ParsePostfix;
end;

function TParser.ParsePostfix: TNode;
var
  inner: TNode;
begin
  Result := ParsePrimary;
  while (Err = '') and IsOp('%') do
  begin
    Inc(P);
    inner := Result;
    Result := TNode.Create;
    Result.Kind := nkPercent;
    SetLength(Result.Args, 1);
    Result.Args[0] := inner;
  end;
end;

function TParser.ParsePrimary: TNode;
var
  t, t2: TToken;
  name: string;
  fi, cnt: Integer;
  arg: TNode;
begin
  Result := TNode.Create;
  t := Cur;
  case t.Kind of
    tkNum:
      begin
        Result.Kind := nkNum;
        Result.Num := t.Num;
        Inc(P);
      end;
    tkStr:
      begin
        Result.Kind := nkStr;
        Result.Str := t.Text;
        Inc(P);
      end;
    tkErr:
      begin
        Result.Kind := nkErr;
        Result.Err := t.Err;
        Inc(P);
      end;
    tkCell:
      begin
        Inc(P);
        if IsOp(':') and (Toks[P + 1].Kind = tkCell) then
        begin
          t2 := Toks[P + 1];
          Inc(P, 2);
          Result.Kind := nkRange;
          Result.Col := Min(t.Col, t2.Col);
          Result.Row := Min(t.Row, t2.Row);
          Result.Col2 := Max(t.Col, t2.Col);
          Result.Row2 := Max(t.Row, t2.Row);
        end
        else
        begin
          Result.Kind := nkRef;
          Result.Col := t.Col;
          Result.Row := t.Row;
          Result.Col2 := t.Col;
          Result.Row2 := t.Row;
        end;
      end;
    tkIdent:
      begin
        name := UpperCase(string(t.Text));
        Inc(P);
        if Cur.Kind = tkLParen then
        begin
          Inc(P);
          Result.Kind := nkFunc;
          Result.Name := name;
          Result.Fn := FindFunc(name);
          cnt := 0;
          if Cur.Kind = tkRParen then
            Inc(P)
          else
          begin
            while True do
            begin
              arg := ParseCompare;
              SetLength(Result.Args, cnt + 1);
              Result.Args[cnt] := arg;
              Inc(cnt);
              if Err <> '' then Break;
              if Cur.Kind = tkComma then
                Inc(P)
              else if Cur.Kind = tkRParen then
              begin
                Inc(P);
                Break;
              end
              else
              begin
                SetErr('Missing ) after the arguments of ' + name);
                Break;
              end;
            end;
          end;
          if Err = '' then
          begin
            fi := Result.Fn;
            if fi >= 0 then
            begin
              if cnt < FuncTable[fi].MinArgs then
                SetErr(name + ' needs at least ' + IntToStr(FuncTable[fi].MinArgs) + ' argument(s)')
              else if (FuncTable[fi].MaxArgs >= 0) and (cnt > FuncTable[fi].MaxArgs) then
                SetErr(name + ' takes at most ' + IntToStr(FuncTable[fi].MaxArgs) + ' argument(s)');
            end;
          end;
        end
        else if name = 'TRUE' then
        begin
          Result.Kind := nkBool;
          Result.Bool := True;
        end
        else if name = 'FALSE' then
        begin
          Result.Kind := nkBool;
          Result.Bool := False;
        end
        else
        begin
          Result.Kind := nkErr;           { an unknown name evaluates to #NAME? }
          Result.Err := ecName;
        end;
      end;
    tkLParen:
      begin
        Inc(P);
        Result.Free;
        Result := ParseCompare;
        if Err = '' then
        begin
          if Cur.Kind = tkRParen then Inc(P) else SetErr('Missing )');
        end;
      end;
  else
    begin
      if t.Kind = tkEnd then SetErr('The formula ends too soon')
      else SetErr('Unexpected ' + string(Copy(t.Text, 1, 20)));
      Result.Kind := nkErr;
      Result.Err := ecSyntax;
    end;
  end;
end;

function ParseFormula(const text: UnicodeString; out root: TNode; out err: string): Boolean;
var
  ps: TParser;
begin
  root := nil;
  ps := TParser.Create;
  try
    if not Tokenize(text, ps.Toks, err) then Exit(False);
    ps.P := 0;
    ps.Err := '';
    root := ps.ParseCompare;
    if (ps.Err = '') and (ps.Cur.Kind <> tkEnd) then
    begin
      case ps.Cur.Kind of
        tkRParen: ps.Err := 'Unexpected )';
        tkComma: ps.Err := 'Unexpected comma';
      else
        ps.Err := 'Unexpected ' + string(Copy(text, ps.Cur.Pos, ps.Cur.Len));
      end;
    end;
    if ps.Err <> '' then
    begin
      err := ps.Err;
      FreeAndNil(root);
      Exit(False);
    end;
    err := '';
    Result := True;
  finally
    ps.Free;
  end;
end;

procedure CollectRanges(n: TNode; var list: TRangeArray);
var
  i, k: Integer;
begin
  if n = nil then Exit;
  if n.Kind in [nkRef, nkRange] then
  begin
    k := Length(list);
    SetLength(list, k + 1);
    list[k].C1 := n.Col;
    list[k].R1 := n.Row;
    list[k].C2 := n.Col2;
    list[k].R2 := n.Row2;
  end;
  for i := 0 to High(n.Args) do CollectRanges(n.Args[i], list);
end;

{ ---- the evaluator ---- }

type
  TAccKind = (akSum, akCount, akCounta, akMin, akMax, akProduct, akLogicAnd, akLogicOr);

  TCmpOp = (coEq, coNe, coLt, coLe, coGt, coGe);

  TCriteria = record
    Op: TCmpOp;
    IsNum: Boolean;
    Num: TDec;
    Text: UnicodeString;       { lower case }
  end;

  TEvaluator = class
    Ctx: TEvalCtx;
    { aggregation state }
    AccKind: TAccKind;
    AccSum, AccExtra: TDec;
    AccCount: Integer;
    AccAny: Boolean;
    AccErr: TValue;
    AccHasErr: Boolean;
    AccLogic: Boolean;
    { conditional sums }
    Crit: TCriteria;
    CritC1, CritR1, SumC1, SumR1: Integer;
    HasSumRange: Boolean;
    CondSum: TDec;
    CondCount: Integer;
    CondErr: TValue;
    CondHasErr: Boolean;

    function Eval(n: TNode): TValue;
    function EvalBinary(n: TNode): TValue;
    function EvalFunc(n: TNode): TValue;
    function Compare(const a, b: TValue): Integer;
    procedure AccReset(kind: TAccKind);
    procedure AccNumber(const d: TDec);
    procedure VisitAcc(col, row: Integer; const v: TValue);
    procedure VisitCond(col, row: Integer; const v: TValue);
    procedure VisitCountOnly(col, row: Integer; const v: TValue);
    procedure AccDirect(const v: TValue);
    function Aggregate(n: TNode; kind: TAccKind): TValue;
    function Conditional(n: TNode; mode: Integer): TValue;
    function ArgInt(n: TNode; out i: Int64; out ev: TValue): Boolean;
    function ArgSerial(n: TNode; out serial: Int64; out ev: TValue): Boolean;
    function CondOf(const v: TValue; out b: Boolean): Boolean;
    function AggResult: TValue;
  end;

function WildMatch(const pat, txt: UnicodeString): Boolean;
var
  p, t, star, mark: Integer;
begin
  p := 1; t := 1; star := 0; mark := 0;
  while t <= Length(txt) do
  begin
    if (p <= Length(pat)) and ((pat[p] = '?') or (pat[p] = txt[t])) then
    begin
      Inc(p);
      Inc(t);
    end
    else if (p <= Length(pat)) and (pat[p] = '*') then
    begin
      star := p;
      mark := t;
      Inc(p);
    end
    else if star > 0 then
    begin
      p := star + 1;
      Inc(mark);
      t := mark;
    end
    else
      Exit(False);
  end;
  while (p <= Length(pat)) and (pat[p] = '*') do Inc(p);
  Result := p > Length(pat);
end;

function Lower(const s: UnicodeString): UnicodeString;
begin
  Result := UnicodeLowerCase(s);
end;

function ParseCriteria(const v: TValue): TCriteria;
var
  s, rest: UnicodeString;
  d: TDec;
begin
  Result.Op := coEq;
  Result.IsNum := False;
  Result.Num := DecZero;
  Result.Text := '';
  case v.Kind of
    vkNum: begin Result.IsNum := True; Result.Num := v.Num; end;
    vkBool: begin Result.IsNum := True; if v.Bool then Result.Num := DecFromInt(1); end;
    vkText:
      begin
        s := v.Text;
        rest := s;
        if Copy(s, 1, 2) = '<=' then begin Result.Op := coLe; rest := Copy(s, 3, MaxInt); end
        else if Copy(s, 1, 2) = '>=' then begin Result.Op := coGe; rest := Copy(s, 3, MaxInt); end
        else if Copy(s, 1, 2) = '<>' then begin Result.Op := coNe; rest := Copy(s, 3, MaxInt); end
        else if Copy(s, 1, 1) = '<' then begin Result.Op := coLt; rest := Copy(s, 2, MaxInt); end
        else if Copy(s, 1, 1) = '>' then begin Result.Op := coGt; rest := Copy(s, 2, MaxInt); end
        else if Copy(s, 1, 1) = '=' then begin Result.Op := coEq; rest := Copy(s, 2, MaxInt); end;
        if TextToNum(rest, d) and (Trim(string(rest)) <> '') then
        begin
          Result.IsNum := True;
          Result.Num := d;
        end
        else
          Result.Text := Lower(rest);
      end;
  end;
end;

function CritMatch(const cr: TCriteria; const v: TValue): Boolean;
var
  c: Integer;
  lt: UnicodeString;
begin
  if cr.IsNum then
  begin
    if not (v.Kind in [vkNum, vkBool]) then Exit(cr.Op = coNe);
    if v.Kind = vkBool then
    begin
      if v.Bool then c := DecCmpSpread(DecFromInt(1), cr.Num) else c := DecCmpSpread(DecZero, cr.Num);
    end
    else
      c := DecCmpSpread(v.Num, cr.Num);
  end
  else
  begin
    if v.Kind <> vkText then Exit(cr.Op = coNe);
    lt := Lower(v.Text);
    case cr.Op of
      coEq: Exit(WildMatch(cr.Text, lt));
      coNe: Exit(not WildMatch(cr.Text, lt));
    end;
    if lt < cr.Text then c := -1 else if lt > cr.Text then c := 1 else c := 0;
  end;
  case cr.Op of
    coEq: Result := c = 0;
    coNe: Result := c <> 0;
    coLt: Result := c < 0;
    coLe: Result := c <= 0;
    coGt: Result := c > 0;
    coGe: Result := c >= 0;
  else
    Result := False;
  end;
end;

procedure TEvaluator.AccReset(kind: TAccKind);
begin
  AccKind := kind;
  AccSum := DecZero;
  AccExtra := DecFromInt(1);
  AccCount := 0;
  AccAny := False;
  AccHasErr := False;
  AccErr := VEmpty;
  AccLogic := kind = akLogicAnd;
end;

procedure TEvaluator.AccNumber(const d: TDec);
begin
  Inc(AccCount);
  case AccKind of
    akSum: AccSum := DecAdd(AccSum, d);
    akProduct: AccSum := DecMul(AccExtra, d);
    akMin: if (not AccAny) or (DecCmp(d, AccSum) < 0) then AccSum := d;
    akMax: if (not AccAny) or (DecCmp(d, AccSum) > 0) then AccSum := d;
  end;
  if AccKind = akProduct then AccExtra := AccSum;
  AccAny := True;
end;

{ one value found inside a range or in a single-cell reference }
procedure TEvaluator.VisitAcc(col, row: Integer; const v: TValue);
begin
  case AccKind of
    akCounta:
      if v.Kind <> vkEmpty then Inc(AccCount);
    akCount:
      if v.Kind = vkNum then Inc(AccCount);
    akLogicAnd, akLogicOr:
      begin
        if v.Kind = vkErr then
        begin
          if not AccHasErr then begin AccHasErr := True; AccErr := v; end;
        end
        else if v.Kind in [vkNum, vkBool] then
        begin
          AccAny := True;
          if v.Kind = vkBool then
          begin
            if AccKind = akLogicAnd then AccLogic := AccLogic and v.Bool else AccLogic := AccLogic or v.Bool;
          end
          else
          begin
            if AccKind = akLogicAnd then AccLogic := AccLogic and (not DecIsZero(v.Num))
            else AccLogic := AccLogic or (not DecIsZero(v.Num));
          end;
        end;
      end;
  else
    if v.Kind = vkNum then AccNumber(v.Num)
    else if v.Kind = vkErr then
    begin
      if not AccHasErr then begin AccHasErr := True; AccErr := v; end;
    end;
  end;
end;

{ a value written straight into the argument list: text that reads as a number counts }
procedure TEvaluator.AccDirect(const v: TValue);
var
  d: TDec;
begin
  if v.Kind = vkErr then
  begin
    if not AccHasErr then begin AccHasErr := True; AccErr := v; end;
    Exit;
  end;
  case AccKind of
    akCounta: Inc(AccCount);
    akCount: if (v.Kind in [vkNum, vkBool]) or ((v.Kind = vkText) and TextToNum(v.Text, d)) then Inc(AccCount);
    akLogicAnd, akLogicOr:
      begin
        if v.Kind = vkText then
        begin
          if (UpperCase(string(Trim(string(v.Text)))) = 'TRUE') or (UpperCase(string(Trim(string(v.Text)))) = 'FALSE') then
            VisitAcc(0, 0, VBool(UpperCase(string(Trim(string(v.Text)))) = 'TRUE'))
          else if not AccHasErr then begin AccHasErr := True; AccErr := VErr(ecValue); end;
        end
        else
          VisitAcc(0, 0, v);
      end;
  else
    if ToNum(v, d) then AccNumber(d)
    else if not AccHasErr then begin AccHasErr := True; AccErr := VErr(ecValue); end;
  end;
end;

function TEvaluator.AggResult: TValue;
begin
  if AccHasErr and (AccKind <> akCount) and (AccKind <> akCounta) then Exit(AccErr);
  case AccKind of
    akSum, akMin, akMax:
      if AccAny then Result := VNum(AccSum) else Result := VNum(DecZero);
    akProduct:
      if AccAny then Result := VNum(AccSum) else Result := VNum(DecZero);
    akCount, akCounta: Result := VInt(AccCount);
    akLogicAnd, akLogicOr:
      if not AccAny then Result := VErr(ecValue) else Result := VBool(AccLogic);
  else
    Result := VErr(ecValue);
  end;
end;

function TEvaluator.Aggregate(n: TNode; kind: TAccKind): TValue;
var
  i: Integer;
  a: TNode;
begin
  AccReset(kind);
  for i := 0 to High(n.Args) do
  begin
    a := n.Args[i];
    if a.Kind = nkRange then
      Ctx.VisitStored(a.Col, a.Row, a.Col2, a.Row2, @VisitAcc)
    else if a.Kind = nkRef then
      VisitAcc(a.Col, a.Row, Ctx.CellValue(a.Col, a.Row))
    else
      AccDirect(Eval(a));
  end;
  Result := AggResult;
end;

procedure TEvaluator.VisitCond(col, row: Integer; const v: TValue);
var
  tv: TValue;
begin
  if not CritMatch(Crit, v) then Exit;
  if HasSumRange then tv := Ctx.CellValue(SumC1 + (col - CritC1), SumR1 + (row - CritR1))
  else tv := v;
  { text and empty cells in the range being summed add nothing }
  if tv.Kind = vkNum then
  begin
    CondSum := DecAdd(CondSum, tv.Num);
    Inc(CondCount);
  end
  else if (tv.Kind = vkErr) and (not CondHasErr) then
  begin
    CondHasErr := True;
    CondErr := tv;
  end;
end;

procedure TEvaluator.VisitCountOnly(col, row: Integer; const v: TValue);
begin
  if CritMatch(Crit, v) then Inc(CondCount);
end;

{ mode 0: SUMIF, 1: COUNTIF, 2: AVERAGEIF }
function TEvaluator.Conditional(n: TNode; mode: Integer): TValue;
var
  rng, sr: TNode;
  cv: TValue;
  r: TDec;
begin
  rng := n.Args[0];
  if not (rng.Kind in [nkRange, nkRef]) then Exit(VErr(ecValue));
  cv := Eval(n.Args[1]);
  if cv.Kind = vkErr then Exit(cv);
  Crit := ParseCriteria(cv);
  CritC1 := rng.Col;
  CritR1 := rng.Row;
  HasSumRange := False;
  if (mode <> 1) and (Length(n.Args) = 3) then
  begin
    sr := n.Args[2];
    if not (sr.Kind in [nkRange, nkRef]) then Exit(VErr(ecValue));
    HasSumRange := True;
    SumC1 := sr.Col;
    SumR1 := sr.Row;
  end;
  CondSum := DecZero;
  CondCount := 0;
  CondHasErr := False;
  if mode = 1 then
  begin
    { COUNTIF counts matching cells, whatever they hold }
    Ctx.VisitStored(rng.Col, rng.Row, rng.Col2, rng.Row2, @VisitCountOnly);
    Exit(VInt(CondCount));
  end;
  Ctx.VisitStored(rng.Col, rng.Row, rng.Col2, rng.Row2, @VisitCond);
  if CondHasErr then Exit(CondErr);
  if mode = 0 then Exit(VNum(CondSum));
  if CondCount = 0 then Exit(VErr(ecDiv0));
  if not DecDiv(CondSum, DecFromInt(CondCount), r) then Exit(VErr(ecDiv0));
  Result := VNum(r);
end;

function TEvaluator.Compare(const a, b: TValue): Integer;
var
  x, y: TDec;
  sa, sb: UnicodeString;
  na, nb: Boolean;
begin
  na := a.Kind in [vkNum, vkBool];
  nb := b.Kind in [vkNum, vkBool];
  if (a.Kind = vkEmpty) and (b.Kind = vkEmpty) then Exit(0);
  { an empty cell is 0 next to a number and "" next to text }
  if a.Kind = vkEmpty then na := b.Kind <> vkText;
  if b.Kind = vkEmpty then nb := a.Kind <> vkText;
  if na and nb then
  begin
    ToNum(a, x);
    ToNum(b, y);
    Exit(DecCmpSpread(x, y));
  end;
  if (not na) and (not nb) then
  begin
    sa := Lower(TextOf(a));
    sb := Lower(TextOf(b));
    if sa < sb then Exit(-1);
    if sa > sb then Exit(1);
    Exit(0);
  end;
  { numbers sort before text }
  if na then Result := -1 else Result := 1;
end;

function TEvaluator.EvalBinary(n: TNode): TValue;
var
  l, r: TValue;
  a, b, res: TDec;
  c: Integer;
  op: string;
begin
  op := n.Op;
  l := Eval(n.Args[0]);
  if l.Kind = vkErr then Exit(l);
  r := Eval(n.Args[1]);
  if r.Kind = vkErr then Exit(r);
  if op = '&' then Exit(VText(TextOf(l) + TextOf(r)));
  if (op = '=') or (op = '<>') or (op = '<') or (op = '>') or (op = '<=') or (op = '>=') then
  begin
    c := Compare(l, r);
    if op = '=' then Exit(VBool(c = 0));
    if op = '<>' then Exit(VBool(c <> 0));
    if op = '<' then Exit(VBool(c < 0));
    if op = '>' then Exit(VBool(c > 0));
    if op = '<=' then Exit(VBool(c <= 0));
    Exit(VBool(c >= 0));
  end;
  if (not ToNum(l, a)) or (not ToNum(r, b)) then Exit(VErr(ecValue));
  if op = '+' then
  begin
    res := DecAdd(a, b);
    if l.IsDate or r.IsDate then Exit(VDate(res));
    Exit(VNum(res));
  end;
  if op = '-' then
  begin
    res := DecSub(a, b);
    if l.IsDate and (not r.IsDate) then Exit(VDate(res));
    Exit(VNum(res));
  end;
  if op = '*' then Exit(VNum(DecMul(a, b)));
  if op = '/' then
  begin
    if not DecDiv(a, b, res) then Exit(VErr(ecDiv0));
    Exit(VNum(res));
  end;
  if op = '^' then
  begin
    if not DecPow(a, b, res) then
    begin
      if DecIsZero(a) and (DecSign(b) < 0) then Exit(VErr(ecDiv0));
      Exit(VErr(ecNum));
    end;
    Exit(VNum(res));
  end;
  Result := VErr(ecValue);
end;

function TEvaluator.CondOf(const v: TValue; out b: Boolean): Boolean;
var
  d: TDec;
  u: string;
begin
  b := False;
  case v.Kind of
    vkBool: begin b := v.Bool; Result := True; end;
    vkNum: begin b := not DecIsZero(v.Num); Result := True; end;
    vkEmpty: Result := True;
    vkText:
      begin
        u := UpperCase(string(Trim(string(v.Text))));
        if u = 'TRUE' then begin b := True; Result := True; end
        else if u = 'FALSE' then Result := True
        else if TextToNum(v.Text, d) then begin b := not DecIsZero(d); Result := True; end
        else Result := False;
      end;
  else
    Result := False;
  end;
end;

{ an argument that must be a whole number }
function TEvaluator.ArgInt(n: TNode; out i: Int64; out ev: TValue): Boolean;
var
  v: TValue;
  d: TDec;
begin
  i := 0;
  v := Eval(n);
  if v.Kind = vkErr then begin ev := v; Exit(False); end;
  if (not ToNum(v, d)) then begin ev := VErr(ecValue); Exit(False); end;
  d := DecRound(d, 0, rmToward);
  if not DecToInt64(d, i) then begin ev := VErr(ecNum); Exit(False); end;
  Result := True;
end;

{ a date argument: a serial number, or text like 2026-11-10 }
function TEvaluator.ArgSerial(n: TNode; out serial: Int64; out ev: TValue): Boolean;
var
  v: TValue;
  d: TDec;
begin
  serial := 0;
  v := Eval(n);
  if v.Kind = vkErr then begin ev := v; Exit(False); end;
  if v.Kind = vkText then
  begin
    if ParseIsoDate(UnicodeString(Trim(string(v.Text))), serial) then Exit(True);
    if ParseUsDate(UnicodeString(Trim(string(v.Text))), serial) then Exit(True);
  end;
  if not ToNum(v, d) then begin ev := VErr(ecValue); Exit(False); end;
  d := DecRound(d, 0, rmFloor);
  if (not DecToInt64(d, serial)) or (not SerialValid(serial)) then begin ev := VErr(ecNum); Exit(False); end;
  Result := True;
end;

function TEvaluator.EvalFunc(n: TNode): TValue;
var
  fn: TFn;
  a, b, r: TDec;
  v, v2: TValue;
  i, i2, i3: Int64;
  ev: TValue;
  ok: Boolean;
  s, part: UnicodeString;
  y, m, d: Integer;
  k: Integer;
  mode: TRoundMode;

  function NumArg(idx: Integer; out x: TDec; out e: TValue): Boolean;
  var
    t: TValue;
  begin
    t := Eval(n.Args[idx]);
    if t.Kind = vkErr then begin e := t; Exit(False); end;
    if not ToNum(t, x) then begin e := VErr(ecValue); Exit(False); end;
    Result := True;
  end;

  function TextArg(idx: Integer; out x: UnicodeString; out e: TValue): Boolean;
  var
    t: TValue;
  begin
    if n.Args[idx].Kind = nkRange then begin e := VErr(ecValue); Exit(False); end;
    t := Eval(n.Args[idx]);
    if t.Kind = vkErr then begin e := t; Exit(False); end;
    x := TextOf(t);
    Result := True;
  end;

begin
  if n.Fn < 0 then Exit(VErr(ecName));
  fn := FuncTable[n.Fn].Id;
  case fn of
    fnSum: Result := Aggregate(n, akSum);
    fnMin: Result := Aggregate(n, akMin);
    fnMax: Result := Aggregate(n, akMax);
    fnCount: Result := Aggregate(n, akCount);
    fnCounta: Result := Aggregate(n, akCounta);
    fnProduct: Result := Aggregate(n, akProduct);
    fnAnd: Result := Aggregate(n, akLogicAnd);
    fnOr: Result := Aggregate(n, akLogicOr);
    fnAverage:
      begin
        Result := Aggregate(n, akSum);
        if Result.Kind <> vkErr then
        begin
          if AccCount = 0 then Exit(VErr(ecDiv0));
          if not DecDiv(AccSum, DecFromInt(AccCount), r) then Exit(VErr(ecDiv0));
          Result := VNum(r);
        end;
      end;
    fnAbs:
      begin
        if not NumArg(0, a, ev) then Exit(ev);
        Result := VNum(DecAbs(a));
      end;
    fnRound, fnRoundUp, fnRoundDown:
      begin
        if not NumArg(0, a, ev) then Exit(ev);
        if not ArgInt(n.Args[1], i, ev) then Exit(ev);
        if (i > 400) or (i < -400) then Exit(VErr(ecNum));
        case fn of
          fnRound: mode := rmHalfAway;
          fnRoundUp: mode := rmAway;
        else
          mode := rmToward;
        end;
        Result := VNum(DecRound(a, Integer(i), mode));
      end;
    fnInt:
      begin
        if not NumArg(0, a, ev) then Exit(ev);
        Result := VNum(DecRound(a, 0, rmFloor));
      end;
    fnMod:
      begin
        if not NumArg(0, a, ev) then Exit(ev);
        if not NumArg(1, b, ev) then Exit(ev);
        if not DecMod(a, b, r) then Exit(VErr(ecDiv0));
        Result := VNum(r);
      end;
    fnPower:
      begin
        if not NumArg(0, a, ev) then Exit(ev);
        if not NumArg(1, b, ev) then Exit(ev);
        if not DecPow(a, b, r) then
        begin
          if DecIsZero(a) and (DecSign(b) < 0) then Exit(VErr(ecDiv0));
          Exit(VErr(ecNum));
        end;
        Result := VNum(r);
      end;
    fnSqrt:
      begin
        if not NumArg(0, a, ev) then Exit(ev);
        if not DecSqrt(a, r) then Exit(VErr(ecNum));
        Result := VNum(r);
      end;
    fnIf:
      begin
        v := Eval(n.Args[0]);
        if v.Kind = vkErr then Exit(v);
        if not CondOf(v, ok) then Exit(VErr(ecValue));
        if ok then Exit(Eval(n.Args[1]));
        if Length(n.Args) = 3 then Exit(Eval(n.Args[2]));
        Result := VBool(False);
      end;
    fnNot:
      begin
        v := Eval(n.Args[0]);
        if v.Kind = vkErr then Exit(v);
        if not CondOf(v, ok) then Exit(VErr(ecValue));
        Result := VBool(not ok);
      end;
    fnIfError:
      begin
        v := Eval(n.Args[0]);
        if v.Kind = vkErr then Result := Eval(n.Args[1]) else Result := v;
      end;
    fnTrue: Result := VBool(True);
    fnFalse: Result := VBool(False);
    fnLen:
      begin
        if not TextArg(0, s, ev) then Exit(ev);
        Result := VInt(Length(s));
      end;
    fnLeft, fnRight:
      begin
        if not TextArg(0, s, ev) then Exit(ev);
        i := 1;
        if Length(n.Args) = 2 then
          if not ArgInt(n.Args[1], i, ev) then Exit(ev);
        if i < 0 then Exit(VErr(ecValue));
        if i > Length(s) then i := Length(s);
        if fn = fnLeft then Result := VText(Copy(s, 1, Integer(i)))
        else Result := VText(Copy(s, Length(s) - Integer(i) + 1, Integer(i)));
      end;
    fnMid:
      begin
        if not TextArg(0, s, ev) then Exit(ev);
        if not ArgInt(n.Args[1], i, ev) then Exit(ev);
        if not ArgInt(n.Args[2], i2, ev) then Exit(ev);
        if (i < 1) or (i2 < 0) then Exit(VErr(ecValue));
        if i > Length(s) then Exit(VText(''));
        if i2 > Length(s) then i2 := Length(s);
        Result := VText(Copy(s, Integer(i), Integer(i2)));
      end;
    fnUpper:
      begin
        if not TextArg(0, s, ev) then Exit(ev);
        Result := VText(UnicodeUpperCase(s));
      end;
    fnLower:
      begin
        if not TextArg(0, s, ev) then Exit(ev);
        Result := VText(UnicodeLowerCase(s));
      end;
    fnTrim:
      begin
        if not TextArg(0, s, ev) then Exit(ev);
        { leading and trailing spaces go, runs of spaces inside become one }
        s := UnicodeString(Trim(string(s)));
        while Pos('  ', string(s)) > 0 do s := UnicodeString(StringReplace(string(s), '  ', ' ', [rfReplaceAll]));
        Result := VText(s);
      end;
    fnConcat:
      begin
        s := '';
        for k := 0 to High(n.Args) do
        begin
          if not TextArg(k, part, ev) then Exit(ev);
          s := s + part;
        end;
        Result := VText(s);
      end;
    fnValue:
      begin
        v := Eval(n.Args[0]);
        if v.Kind = vkErr then Exit(v);
        if v.Kind = vkNum then Exit(v);
        if v.Kind <> vkText then Exit(VErr(ecValue));
        if not TextToNum(v.Text, a) then Exit(VErr(ecValue));
        Result := VNum(a);
      end;
    fnSumIf: Result := Conditional(n, 0);
    fnCountIf: Result := Conditional(n, 1);
    fnAverageIf: Result := Conditional(n, 2);
    fnDate:
      begin
        if not ArgInt(n.Args[0], i, ev) then Exit(ev);
        if not ArgInt(n.Args[1], i2, ev) then Exit(ev);
        if not ArgInt(n.Args[2], i3, ev) then Exit(ev);
        if (i >= 0) and (i < 30) then Inc(i, 2000)
        else if (i >= 30) and (i < 100) then Inc(i, 1900);
        if not SerialFromYMD(i, i2, i3, i) then Exit(VErr(ecNum));
        Result := VDate(DecFromInt(i));
      end;
    fnYear, fnMonth, fnDay:
      begin
        if not ArgSerial(n.Args[0], i, ev) then Exit(ev);
        YMDFromSerial(i, y, m, d);
        case fn of
          fnYear: Result := VInt(y);
          fnMonth: Result := VInt(m);
        else
          Result := VInt(d);
        end;
      end;
    fnWeekday:
      begin
        if not ArgSerial(n.Args[0], i, ev) then Exit(ev);
        i2 := 1;
        if Length(n.Args) = 2 then
          if not ArgInt(n.Args[1], i2, ev) then Exit(ev);
        k := WeekdaySunday0(i);
        case i2 of
          1: Result := VInt(k + 1);
          2: Result := VInt((k + 6) mod 7 + 1);
          3: Result := VInt((k + 6) mod 7);
        else
          Result := VErr(ecNum);
        end;
      end;
    fnToday: Result := VDate(DecFromInt(Ctx.Today));
    fnDays:
      begin
        if not ArgSerial(n.Args[0], i, ev) then Exit(ev);
        if not ArgSerial(n.Args[1], i2, ev) then Exit(ev);
        Result := VInt(i - i2);
      end;
    fnEdate:
      begin
        if not ArgSerial(n.Args[0], i, ev) then Exit(ev);
        if not ArgInt(n.Args[1], i2, ev) then Exit(ev);
        if not AddMonths(i, i2, i3) then Exit(VErr(ecNum));
        Result := VDate(DecFromInt(i3));
      end;
    fnDatedif:
      begin
        if not ArgSerial(n.Args[0], i, ev) then Exit(ev);
        if not ArgSerial(n.Args[1], i2, ev) then Exit(ev);
        v := Eval(n.Args[2]);
        if v.Kind = vkErr then Exit(v);
        if not DateDif(i, i2, string(TextOf(v)), i3) then Exit(VErr(ecNum));
        Result := VInt(i3);
      end;
    fnIsBlank:
      begin
        if n.Args[0].Kind = nkRef then v := Ctx.CellValue(n.Args[0].Col, n.Args[0].Row)
        else v := Eval(n.Args[0]);
        Result := VBool(v.Kind = vkEmpty);
      end;
    fnIsNumber, fnIsText, fnIsError:
      begin
        v := Eval(n.Args[0]);
        case fn of
          fnIsNumber: Result := VBool(v.Kind = vkNum);
          fnIsText: Result := VBool(v.Kind = vkText);
        else
          Result := VBool(v.Kind = vkErr);
        end;
      end;
  else
    Result := VErr(ecName);
  end;
end;

function TEvaluator.Eval(n: TNode): TValue;
var
  v: TValue;
  a: TDec;
begin
  case n.Kind of
    nkNum: Result := VNum(n.Num);
    nkStr: Result := VText(n.Str);
    nkBool: Result := VBool(n.Bool);
    nkErr: Result := VErr(n.Err);
    nkRef: Result := Ctx.CellValue(n.Col, n.Row);
    nkRange: Result := VErr(ecValue);
    nkUnary:
      begin
        v := Eval(n.Args[0]);
        if v.Kind = vkErr then Exit(v);
        if n.Op = '+' then Exit(v);
        if not ToNum(v, a) then Exit(VErr(ecValue));
        Result := VNum(DecNeg(a));
      end;
    nkPercent:
      begin
        v := Eval(n.Args[0]);
        if v.Kind = vkErr then Exit(v);
        if not ToNum(v, a) then Exit(VErr(ecValue));
        DecDiv(a, DecFromInt(100), a);
        Result := VNum(a);
      end;
    nkBinary: Result := EvalBinary(n);
    nkFunc: Result := EvalFunc(n);
  else
    Result := VErr(ecValue);
  end;
end;

function EvalFormula(root: TNode; ctx: TEvalCtx): TValue;
var
  ev: TEvaluator;
begin
  ev := TEvaluator.Create;
  try
    ev.Ctx := ctx;
    Result := ev.Eval(root);
    if Result.Kind = vkEmpty then Result := VNum(DecZero);       { =A1 with A1 empty shows 0 }
  finally
    ev.Free;
  end;
end;

{ ---- rewriting references ---- }

function RewriteRefs(const f: UnicodeString; map: TRefMap; out res: UnicodeString; rmap: TRangeMap): Boolean;
var
  toks: TTokens;
  err: string;
  i, last: Integer;
  t, t2: TToken;
  c1, r1, c2, r2: Integer;
  ok1, ok2, isRange: Boolean;
begin
  res := f;
  if not Tokenize(f, toks, err) then Exit(False);
  res := '';
  last := 1;
  i := 0;
  while i < Length(toks) do
  begin
    t := toks[i];
    if t.Kind = tkCell then
    begin
      isRange := (toks[i + 1].Kind = tkOp) and (string(toks[i + 1].Text) = ':') and (toks[i + 2].Kind = tkCell);
      c1 := t.Col; r1 := t.Row;
      ok1 := map(c1, r1, t.AbsCol, t.AbsRow);
      res := res + Copy(f, last, t.Pos - last);
      if isRange then
      begin
        t2 := toks[i + 2];
        c2 := t2.Col; r2 := t2.Row;
        if Assigned(rmap) then
        begin
          c1 := t.Col; r1 := t.Row;
          ok1 := rmap(c1, r1, c2, r2);
          ok2 := ok1;
        end
        else
          ok2 := map(c2, r2, t2.AbsCol, t2.AbsRow);
        if ok1 and ok2 then
          res := res + RefText(c1, r1, t.AbsCol, t.AbsRow) + ':' + RefText(c2, r2, t2.AbsCol, t2.AbsRow)
        else
          res := res + '#REF!';
        last := t2.Pos + t2.Len;
        Inc(i, 3);
      end
      else
      begin
        if ok1 then res := res + RefText(c1, r1, t.AbsCol, t.AbsRow) else res := res + '#REF!';
        last := t.Pos + t.Len;
        Inc(i);
      end;
    end
    else
      Inc(i);
  end;
  res := res + Copy(f, last, MaxInt);
  Result := True;
end;

type
  TShifter = class
    DCol, DRow: Integer;
    function Map(var col, row: Integer; absCol, absRow: Boolean): Boolean;
  end;

function TShifter.Map(var col, row: Integer; absCol, absRow: Boolean): Boolean;
begin
  if not absCol then Inc(col, DCol);
  if not absRow then Inc(row, DRow);
  Result := (col >= 0) and (col <= MAX_COL) and (row >= 0) and (row <= MAX_ROW);
end;

function ShiftFormula(const f: UnicodeString; dCol, dRow: Integer; out res: UnicodeString): Boolean;
var
  sh: TShifter;
begin
  sh := TShifter.Create;
  try
    sh.DCol := dCol;
    sh.DRow := dRow;
    Result := RewriteRefs(f, @sh.Map, res);
  finally
    sh.Free;
  end;
end;

end.
