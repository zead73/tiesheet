{ tsdec - exact decimal numbers for the spreadsheet.

  A number is a sign, a string of decimal digits and a count of how many of those
  digits are to the right of the point, so 0.1 + 0.2 is exactly 0.3 and money adds up to
  the cent.  Results keep at most DEC_SIG significant digits (34), rounded half away from
  zero.  The form is always normalised: no leading zeros, no trailing zeros in the
  fraction, and zero is never negative, so two equal numbers have equal fields. }
unit tsdec;

{$mode objfpc}{$H+}

interface

const
  DEC_SIG = 34;          { significant digits kept after multiplying, dividing, adding }
  DEC_CMP_SIG = 15;      { comparisons look at this many significant digits, like the other spreadsheets }

type
  TDec = record
    Neg: Boolean;
    Digits: string;      { the digits with the point removed; '0' for zero }
    Scale: Integer;      { digits to the right of the point }
  end;

  TRoundMode = (rmHalfAway, rmAway, rmToward, rmFloor, rmCeil);

function DecZero: TDec;
function DecFromInt(i: Int64): TDec;
function DecFromStr(const s: UnicodeString; out d: TDec): Boolean;      { sign, digits, point, e-exponent }
function DecFromDouble(x: Double; out d: TDec): Boolean;                { 15 significant digits }
function DecToStr(const d: TDec): string;                               { plain notation, never an exponent }
function DecToDouble(const d: TDec): Double;
function DecToInt64(const d: TDec; out i: Int64): Boolean;              { only whole numbers that fit }

function DecIsZero(const d: TDec): Boolean;
function DecSign(const d: TDec): Integer;
function DecIsInt(const d: TDec): Boolean;
function DecNeg(const d: TDec): TDec;
function DecAbs(const d: TDec): TDec;
function DecCmp(const a, b: TDec): Integer;                             { exact }
function DecCmpSpread(const a, b: TDec): Integer;                       { after rounding both to DEC_CMP_SIG digits }
function DecAdd(const a, b: TDec): TDec;
function DecSub(const a, b: TDec): TDec;
function DecMul(const a, b: TDec): TDec;
function DecDiv(const a, b: TDec; var r: TDec): Boolean;                { False when b is zero }
function DecMod(const a, b: TDec; var r: TDec): Boolean;                { sign of the divisor, like the spreadsheets }
function DecPow(const a, e: TDec; var r: TDec): Boolean;                { False for a result that is not a number }
function DecSqrt(const a: TDec; var r: TDec): Boolean;                  { False for a negative number }
function DecRound(const d: TDec; places: Integer; mode: TRoundMode): TDec;   { places may be negative }
function DecRoundSig(const d: TDec; sig: Integer): TDec;

{ fixed notation with exactly `decimals` digits after the point, rounded half away from zero }
function DecToFixed(const d: TDec; decimals: Integer; thousands: Boolean): string;

implementation

uses
  SysUtils, Math;

{ ---- magnitudes: non-negative whole numbers as digit strings, no leading zeros ---- }

function MagStrip(const a: string): string;
var
  i: Integer;
begin
  i := 1;
  while (i < Length(a)) and (a[i] = '0') do Inc(i);
  Result := Copy(a, i, MaxInt);
  if Result = '' then Result := '0';
end;

function MagCmp(const a, b: string): Integer;
begin
  if Length(a) <> Length(b) then
  begin
    if Length(a) < Length(b) then Exit(-1) else Exit(1);
  end;
  if a < b then Result := -1
  else if a > b then Result := 1
  else Result := 0;
end;

function MagAdd(const a, b: string): string;
var
  i, j, k, s, carry: Integer;
begin
  SetLength(Result, Length(a) + Length(b) + 1);
  i := Length(a); j := Length(b); k := Length(Result);
  carry := 0;
  while (i > 0) or (j > 0) or (carry > 0) do
  begin
    s := carry;
    if i > 0 then begin Inc(s, Ord(a[i]) - 48); Dec(i); end;
    if j > 0 then begin Inc(s, Ord(b[j]) - 48); Dec(j); end;
    Result[k] := Chr(48 + s mod 10);
    carry := s div 10;
    Dec(k);
  end;
  Result := MagStrip(Copy(Result, k + 1, MaxInt));
end;

{ a - b, with a >= b }
function MagSub(const a, b: string): string;
var
  i, j, s, borrow: Integer;
begin
  SetLength(Result, Length(a));
  i := Length(a); j := Length(b);
  borrow := 0;
  while i > 0 do
  begin
    s := Ord(a[i]) - 48 - borrow;
    if j > 0 then begin Dec(s, Ord(b[j]) - 48); Dec(j); end;
    if s < 0 then begin Inc(s, 10); borrow := 1; end else borrow := 0;
    Result[i] := Chr(48 + s);
    Dec(i);
  end;
  Result := MagStrip(Result);
end;

function MagMul(const a, b: string): string;
var
  r: array of Integer;
  i, j, n, carry: Integer;
begin
  if (a = '0') or (b = '0') then Exit('0');
  SetLength(r, Length(a) + Length(b));
  for i := 0 to High(r) do r[i] := 0;
  for i := Length(a) downto 1 do
    for j := Length(b) downto 1 do
      Inc(r[i + j - 1], (Ord(a[i]) - 48) * (Ord(b[j]) - 48));
  carry := 0;
  for i := High(r) downto 0 do
  begin
    n := r[i] + carry;
    r[i] := n mod 10;
    carry := n div 10;
  end;
  SetLength(Result, Length(r));
  for i := 0 to High(r) do Result[i + 1] := Chr(48 + r[i]);
  Result := MagStrip(Result);
end;

{ quotient and remainder by long division }
procedure MagDivMod(const a, b: string; out q, r: string);
var
  i, cnt: Integer;
begin
  q := '';
  r := '0';
  for i := 1 to Length(a) do
  begin
    if r = '0' then r := a[i] else r := r + a[i];
    cnt := 0;
    while MagCmp(r, b) >= 0 do
    begin
      r := MagSub(r, b);
      Inc(cnt);
    end;
    q := q + Chr(48 + cnt);
  end;
  q := MagStrip(q);
end;

function Zeros(n: Integer): string;
begin
  if n <= 0 then Result := '' else Result := StringOfChar('0', n);
end;

{ ---- normal form ---- }

procedure Normalize(var d: TDec);
begin
  d.Digits := MagStrip(d.Digits);
  if d.Digits = '0' then
  begin
    d.Neg := False;
    d.Scale := 0;
    Exit;
  end;
  while (d.Scale > 0) and (d.Digits[Length(d.Digits)] = '0') do
  begin
    SetLength(d.Digits, Length(d.Digits) - 1);
    Dec(d.Scale);
  end;
end;

{ keeps DEC_SIG significant digits, rounding half away from zero }
procedure Limit(var d: TDec);
var
  drop: Integer;
  kept: string;
begin
  drop := Length(d.Digits) - DEC_SIG;
  if drop <= 0 then Exit;
  kept := Copy(d.Digits, 1, DEC_SIG);
  if d.Digits[DEC_SIG + 1] >= '5' then kept := MagAdd(kept, '1');
  if drop <= d.Scale then
  begin
    d.Digits := kept;
    Dec(d.Scale, drop);
  end
  else
  begin
    d.Digits := kept + Zeros(drop);
    d.Scale := 0;
  end;
  Normalize(d);
end;

function DecZero: TDec;
begin
  Result.Neg := False;
  Result.Digits := '0';
  Result.Scale := 0;
end;

function DecFromInt(i: Int64): TDec;
var
  s: string;
begin
  s := IntToStr(i);
  Result.Neg := i < 0;
  if Result.Neg then Delete(s, 1, 1);
  Result.Digits := s;
  Result.Scale := 0;
  Normalize(Result);
end;

function DecFromStr(const s: UnicodeString; out d: TDec): Boolean;
var
  i, n, expv, expSign, intLen, fracLen: Integer;
  neg: Boolean;
  intp, fracp: string;
begin
  d := DecZero;
  Result := False;
  n := Length(s);
  i := 1;
  neg := False;
  if (i <= n) and ((s[i] = '+') or (s[i] = '-')) then
  begin
    neg := s[i] = '-';
    Inc(i);
  end;
  intp := '';
  while (i <= n) and (s[i] >= '0') and (s[i] <= '9') do
  begin
    intp := intp + Chr(Ord(s[i]));
    Inc(i);
  end;
  fracp := '';
  if (i <= n) and (s[i] = '.') then
  begin
    Inc(i);
    while (i <= n) and (s[i] >= '0') and (s[i] <= '9') do
    begin
      fracp := fracp + Chr(Ord(s[i]));
      Inc(i);
    end;
  end;
  if (intp = '') and (fracp = '') then Exit;
  expv := 0;
  if (i <= n) and ((s[i] = 'e') or (s[i] = 'E')) then
  begin
    Inc(i);
    expSign := 1;
    if (i <= n) and ((s[i] = '+') or (s[i] = '-')) then
    begin
      if s[i] = '-' then expSign := -1;
      Inc(i);
    end;
    if (i > n) or (s[i] < '0') or (s[i] > '9') then Exit;
    while (i <= n) and (s[i] >= '0') and (s[i] <= '9') do
    begin
      expv := expv * 10 + (Ord(s[i]) - 48);
      if expv > 1000 then Exit;
      Inc(i);
    end;
    expv := expv * expSign;
  end;
  if i <= n then Exit;
  intLen := Length(intp);
  fracLen := Length(fracp);
  d.Neg := neg;
  d.Digits := intp + fracp;
  d.Scale := fracLen - expv;
  if d.Scale < 0 then
  begin
    d.Digits := d.Digits + Zeros(-d.Scale);
    d.Scale := 0;
  end;
  if intLen < 0 then Exit;
  Normalize(d);
  Limit(d);
  Result := True;
end;

function DecFromDouble(x: Double; out d: TDec): Boolean;
var
  fs: TFormatSettings;
begin
  d := DecZero;
  if IsNan(x) or IsInfinite(x) then Exit(False);
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := DecFromStr(UnicodeString(FloatToStrF(x, ffGeneral, 15, 0, fs)), d);
end;

function DecToStr(const d: TDec): string;
var
  m: string;
begin
  m := d.Digits;
  if d.Scale > 0 then
  begin
    if Length(m) > d.Scale then
      m := Copy(m, 1, Length(m) - d.Scale) + '.' + Copy(m, Length(m) - d.Scale + 1, MaxInt)
    else
      m := '0.' + Zeros(d.Scale - Length(m)) + m;
  end;
  if d.Neg then Result := '-' + m else Result := m;
end;

function DecToDouble(const d: TDec): Double;
var
  fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := StrToFloatDef(DecToStr(d), 0, fs);
end;

function DecToInt64(const d: TDec; out i: Int64): Boolean;
var
  v: Int64;
begin
  i := 0;
  if (d.Scale <> 0) or (Length(d.Digits) > 18) then Exit(False);
  v := StrToInt64(d.Digits);
  if d.Neg then v := -v;
  i := v;
  Result := True;
end;

function DecIsZero(const d: TDec): Boolean;
begin
  Result := d.Digits = '0';
end;

function DecSign(const d: TDec): Integer;
begin
  if d.Digits = '0' then Result := 0
  else if d.Neg then Result := -1
  else Result := 1;
end;

function DecIsInt(const d: TDec): Boolean;
begin
  Result := d.Scale = 0;
end;

function DecNeg(const d: TDec): TDec;
begin
  Result := d;
  if Result.Digits <> '0' then Result.Neg := not Result.Neg;
end;

function DecAbs(const d: TDec): TDec;
begin
  Result := d;
  Result.Neg := False;
end;

{ both magnitudes brought to the same scale }
procedure Align(const a, b: TDec; out ma, mb: string; out scale: Integer);
begin
  scale := a.Scale;
  if b.Scale > scale then scale := b.Scale;
  ma := a.Digits + Zeros(scale - a.Scale);
  mb := b.Digits + Zeros(scale - b.Scale);
end;

function DecCmp(const a, b: TDec): Integer;
var
  ma, mb: string;
  sc, c: Integer;
begin
  if a.Neg <> b.Neg then
  begin
    if a.Neg then Exit(-1) else Exit(1);
  end;
  Align(a, b, ma, mb, sc);
  c := MagCmp(ma, mb);
  if a.Neg then c := -c;
  Result := c;
end;

function DecCmpSpread(const a, b: TDec): Integer;
begin
  Result := DecCmp(DecRoundSig(a, DEC_CMP_SIG), DecRoundSig(b, DEC_CMP_SIG));
end;

function DecAdd(const a, b: TDec): TDec;
var
  ma, mb: string;
  sc, c: Integer;
begin
  Align(a, b, ma, mb, sc);
  Result.Scale := sc;
  if a.Neg = b.Neg then
  begin
    Result.Neg := a.Neg;
    Result.Digits := MagAdd(ma, mb);
  end
  else
  begin
    c := MagCmp(ma, mb);
    if c = 0 then
    begin
      Result.Neg := False;
      Result.Digits := '0';
    end
    else if c > 0 then
    begin
      Result.Neg := a.Neg;
      Result.Digits := MagSub(ma, mb);
    end
    else
    begin
      Result.Neg := b.Neg;
      Result.Digits := MagSub(mb, ma);
    end;
  end;
  Normalize(Result);
  Limit(Result);
end;

function DecSub(const a, b: TDec): TDec;
begin
  Result := DecAdd(a, DecNeg(b));
end;

function DecMul(const a, b: TDec): TDec;
begin
  Result.Neg := a.Neg <> b.Neg;
  Result.Digits := MagMul(a.Digits, b.Digits);
  Result.Scale := a.Scale + b.Scale;
  Normalize(Result);
  Limit(Result);
end;

function DecDiv(const a, b: TDec; var r: TDec): Boolean;
var
  k: Integer;
  num, q, rem: string;
  res: TDec;
begin
  { r may be the same variable as a or b, so it is only written at the end }
  if b.Digits = '0' then
  begin
    r := DecZero;
    Exit(False);
  end;
  if a.Digits = '0' then
  begin
    r := DecZero;
    Exit(True);
  end;
  { value = (A / B) * 10^(sb - sa); take A * 10^k div B so the quotient has DEC_SIG digits }
  k := DEC_SIG - (Length(a.Digits) - Length(b.Digits));
  if k < 0 then k := 0;
  num := a.Digits + Zeros(k);
  MagDivMod(num, b.Digits, q, rem);
  if MagCmp(MagAdd(rem, rem), b.Digits) >= 0 then q := MagAdd(q, '1');
  res.Neg := a.Neg <> b.Neg;
  res.Digits := q;
  res.Scale := k + a.Scale - b.Scale;
  if res.Scale < 0 then
  begin
    res.Digits := res.Digits + Zeros(-res.Scale);
    res.Scale := 0;
  end;
  Normalize(res);
  Limit(res);
  r := res;
  Result := True;
end;

function DecRound(const d: TDec; places: Integer; mode: TRoundMode): TDec;
var
  drop, keepLen: Integer;
  m, lead, dropped: string;
  bump, anyDropped: Boolean;
  i: Integer;
begin
  if (d.Digits = '0') or (places >= d.Scale) then Exit(d);
  drop := d.Scale - places;
  m := d.Digits;
  if drop >= Length(m) then
  begin
    dropped := Zeros(drop - Length(m)) + m;
    lead := '0';
  end
  else
  begin
    keepLen := Length(m) - drop;
    lead := Copy(m, 1, keepLen);
    dropped := Copy(m, keepLen + 1, MaxInt);
  end;
  anyDropped := False;
  for i := 1 to Length(dropped) do
    if dropped[i] <> '0' then
    begin
      anyDropped := True;
      Break;
    end;
  case mode of
    rmHalfAway: bump := dropped[1] >= '5';
    rmAway: bump := anyDropped;
    rmToward: bump := False;
    rmFloor: bump := d.Neg and anyDropped;
    rmCeil: bump := (not d.Neg) and anyDropped;
  else
    bump := False;
  end;
  if bump then lead := MagAdd(lead, '1');
  Result.Neg := d.Neg;
  if places >= 0 then
  begin
    Result.Digits := lead;
    Result.Scale := places;
  end
  else
  begin
    Result.Digits := lead + Zeros(-places);
    Result.Scale := 0;
  end;
  Normalize(Result);
end;

function DecRoundSig(const d: TDec; sig: Integer): TDec;
begin
  if Length(d.Digits) <= sig then Exit(d);
  Result := DecRound(d, d.Scale - (Length(d.Digits) - sig), rmHalfAway);
end;

function DecMod(const a, b: TDec; var r: TDec): Boolean;
var
  q, res: TDec;
begin
  if not DecDiv(a, b, q) then
  begin
    r := DecZero;
    Exit(False);
  end;
  q := DecRound(q, 0, rmFloor);
  res := DecSub(a, DecMul(b, q));
  r := res;
  Result := True;
end;

function SqrtImpl(const a: TDec; out r: TDec): Boolean; forward;

function PowImpl(const a, e: TDec; out r: TDec): Boolean;
var
  n, k: Int64;
  base, acc: TDec;
  x: Double;
begin
  r := DecZero;
  if DecIsZero(e) then
  begin
    r := DecFromInt(1);
    Exit(True);
  end;
  if DecToInt64(e, n) then
  begin
    if Abs(n) > 5000 then Exit(False);
    if DecIsZero(a) then
    begin
      if n < 0 then Exit(False);
      Exit(True);
    end;
    k := Abs(n);
    acc := DecFromInt(1);
    base := a;
    while k > 0 do
    begin
      if (k and 1) = 1 then acc := DecMul(acc, base);
      k := k shr 1;
      if k > 0 then base := DecMul(base, base);
    end;
    if n < 0 then Exit(DecDiv(DecFromInt(1), acc, r));
    r := acc;
    Exit(True);
  end;
  { a fractional exponent: only for a positive base, and only to double precision }
  if DecSign(a) < 0 then Exit(False);
  if DecIsZero(a) then Exit(DecSign(e) > 0);
  { the power of a half is a square root, which every platform rounds the same way }
  if (not e.Neg) and (e.Digits = '5') and (e.Scale = 1) then Exit(SqrtImpl(a, r));
  x := Power(DecToDouble(a), DecToDouble(e));
  Result := DecFromDouble(x, r);
end;

function SqrtImpl(const a: TDec; out r: TDec): Boolean;
var
  x: Double;
begin
  r := DecZero;
  if DecSign(a) < 0 then Exit(False);
  if DecIsZero(a) then Exit(True);
  x := Sqrt(DecToDouble(a));
  Result := DecFromDouble(x, r);
end;

{ the result variable may be one of the inputs: these take it as var (an out record is cleared on entry), and work on copies }
function DecPow(const a, e: TDec; var r: TDec): Boolean;
var
  aa, ee, res: TDec;
begin
  aa := a;
  ee := e;
  Result := PowImpl(aa, ee, res);
  r := res;
end;

function DecSqrt(const a: TDec; var r: TDec): Boolean;
var
  aa, res: TDec;
begin
  aa := a;
  Result := SqrtImpl(aa, res);
  r := res;
end;

function DecToFixed(const d: TDec; decimals: Integer; thousands: Boolean): string;
var
  v: TDec;
  s, ip, fp: string;
  i, cnt: Integer;
begin
  if decimals < 0 then decimals := 0;
  v := DecRound(d, decimals, rmHalfAway);
  s := v.Digits;
  if v.Scale > 0 then
  begin
    if Length(s) <= v.Scale then s := Zeros(v.Scale - Length(s) + 1) + s;
    ip := Copy(s, 1, Length(s) - v.Scale);
    fp := Copy(s, Length(s) - v.Scale + 1, MaxInt);
  end
  else
  begin
    ip := s;
    fp := '';
  end;
  fp := fp + Zeros(decimals - Length(fp));
  if thousands then
  begin
    s := '';
    cnt := 0;
    for i := Length(ip) downto 1 do
    begin
      if (cnt > 0) and (cnt mod 3 = 0) then s := ',' + s;
      s := ip[i] + s;
      Inc(cnt);
    end;
    ip := s;
  end;
  Result := ip;
  if decimals > 0 then Result := Result + '.' + fp;
  if v.Neg then Result := '-' + Result;
end;

end.
