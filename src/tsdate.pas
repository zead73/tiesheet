{ tsdate - dates as serial day numbers.  Serial 0 is 1899-12-30, as in LibreOffice, so a
  serial means the same thing in both programs (and 1900 is not treated as a leap year). }
unit tsdate;

{$mode objfpc}{$H+}

interface

function DaysFromCivil(y, m, d: Int64): Int64;                    { days since 1970-01-01 }
procedure CivilFromDays(z: Int64; out y, m, d: Integer);
function DaysInMonth(y, m: Integer): Integer;

{ month and day may overflow or be zero or negative, like DATE(2026;13;1); False outside years 1..9999 }
function SerialFromYMD(y, m, d: Int64; out serial: Int64): Boolean;
procedure YMDFromSerial(serial: Int64; out y, m, d: Integer);
function SerialValid(serial: Int64): Boolean;
function ParseIsoDate(const s: UnicodeString; out serial: Int64): Boolean;   { YYYY-MM-DD, strictly }
function SerialToIso(serial: Int64): string;
function WeekdaySunday0(serial: Int64): Integer;                  { 0 = Sunday .. 6 = Saturday }
function AddMonths(serial: Int64; months: Int64; out res: Int64): Boolean;   { the day is clamped to the month }
function TodaySerial: Int64;

implementation

uses
  SysUtils;

const
  EPOCH_OFFSET = -25569;   { DaysFromCivil(1899, 12, 30) }
  MIN_SERIAL = -693593;    { 0001-01-01 }
  MAX_SERIAL = 2958465;    { 9999-12-31 }

function FloorDiv(a, b: Int64): Int64;
begin
  Result := a div b;
  if (a mod b <> 0) and ((a < 0) <> (b < 0)) then Dec(Result);
end;

function DaysFromCivil(y, m, d: Int64): Int64;
var
  era, yoe, doy, doe, mp: Int64;
begin
  if m <= 2 then Dec(y);
  if y >= 0 then era := y div 400 else era := (y - 399) div 400;
  yoe := y - era * 400;
  if m > 2 then mp := m - 3 else mp := m + 9;
  doy := (153 * mp + 2) div 5 + d - 1;
  doe := yoe * 365 + yoe div 4 - yoe div 100 + doy;
  Result := era * 146097 + doe - 719468;
end;

procedure CivilFromDays(z: Int64; out y, m, d: Integer);
var
  era, doe, yoe, doy, mp, yy: Int64;
begin
  Inc(z, 719468);
  if z >= 0 then era := z div 146097 else era := (z - 146096) div 146097;
  doe := z - era * 146097;
  yoe := (doe - doe div 1460 + doe div 36524 - doe div 146096) div 365;
  yy := yoe + era * 400;
  doy := doe - (365 * yoe + yoe div 4 - yoe div 100);
  mp := (5 * doy + 2) div 153;
  d := Integer(doy - (153 * mp + 2) div 5 + 1);
  if mp < 10 then m := Integer(mp + 3) else m := Integer(mp - 9);
  if m <= 2 then Inc(yy);
  y := Integer(yy);
end;

function DaysInMonth(y, m: Integer): Integer;
begin
  case m of
    1, 3, 5, 7, 8, 10, 12: Result := 31;
    4, 6, 9, 11: Result := 30;
  else
    if ((y mod 4 = 0) and (y mod 100 <> 0)) or (y mod 400 = 0) then Result := 29 else Result := 28;
  end;
end;

function SerialValid(serial: Int64): Boolean;
begin
  Result := (serial >= MIN_SERIAL) and (serial <= MAX_SERIAL);
end;

function SerialFromYMD(y, m, d: Int64; out serial: Int64): Boolean;
var
  m0, yy: Int64;
begin
  serial := 0;
  if (y < -100000) or (y > 100000) or (m < -2000000) or (m > 2000000) or (Abs(d) > 100000000) then Exit(False);
  m0 := m - 1;
  yy := y + FloorDiv(m0, 12);
  m0 := m0 - FloorDiv(m0, 12) * 12;
  if (yy < 1) or (yy > 9999) then Exit(False);
  serial := DaysFromCivil(yy, m0 + 1, 1) + (d - 1) - EPOCH_OFFSET;
  Result := SerialValid(serial);
end;

procedure YMDFromSerial(serial: Int64; out y, m, d: Integer);
begin
  CivilFromDays(serial + EPOCH_OFFSET, y, m, d);
end;

function ParseIsoDate(const s: UnicodeString; out serial: Int64): Boolean;
var
  y, m, d, i: Integer;
begin
  serial := 0;
  Result := False;
  if (Length(s) <> 10) or (s[5] <> '-') or (s[8] <> '-') then Exit;
  for i := 1 to 10 do
    if (i <> 5) and (i <> 8) and ((s[i] < '0') or (s[i] > '9')) then Exit;
  y := StrToInt(string(Copy(s, 1, 4)));
  m := StrToInt(string(Copy(s, 6, 2)));
  d := StrToInt(string(Copy(s, 9, 2)));
  if (y < 1) or (m < 1) or (m > 12) or (d < 1) or (d > DaysInMonth(y, m)) then Exit;
  Result := SerialFromYMD(y, m, d, serial);
end;

function SerialToIso(serial: Int64): string;
var
  y, m, d: Integer;
begin
  if not SerialValid(serial) then Exit('#NUM!');
  YMDFromSerial(serial, y, m, d);
  Result := Format('%.4d-%.2d-%.2d', [y, m, d]);
end;

function WeekdaySunday0(serial: Int64): Integer;
var
  z: Int64;
begin
  z := serial + EPOCH_OFFSET;                       { days since 1970-01-01, a Thursday }
  Result := Integer((((z mod 7) + 7) mod 7 + 4) mod 7);
end;

function AddMonths(serial: Int64; months: Int64; out res: Int64): Boolean;
var
  y, m, d, dim: Integer;
  total: Int64;
  yy: Int64;
begin
  res := 0;
  if not SerialValid(serial) then Exit(False);
  if Abs(months) > 200000 then Exit(False);
  YMDFromSerial(serial, y, m, d);
  total := Int64(y) * 12 + (m - 1) + months;
  yy := FloorDiv(total, 12);
  m := Integer(total - yy * 12) + 1;
  if (yy < 1) or (yy > 9999) then Exit(False);
  dim := DaysInMonth(Integer(yy), m);
  if d > dim then d := dim;
  Result := SerialFromYMD(yy, m, d, res);
end;

function TodaySerial: Int64;
begin
  Result := Trunc(Now);       { a TDateTime counts days from 1899-12-30 too }
end;

end.
