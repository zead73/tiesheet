{ tsvalue - what a cell can hold or a formula can return, and how values convert. }
unit tsvalue;

{$mode objfpc}{$H+}

interface

uses
  tsdec;

type
  TErrCode = (ecDiv0, ecValue, ecRef, ecName, ecNum, ecNA, ecCirc, ecSyntax);
  TValKind = (vkEmpty, vkNum, vkText, vkBool, vkErr);

  TValue = record
    Kind: TValKind;
    Num: TDec;
    Text: UnicodeString;
    Bool: Boolean;
    Err: TErrCode;
    IsDate: Boolean;       { the result of a date function: shown as a date unless the cell has a format }
  end;

const
  ErrNames: array[TErrCode] of string =
    ('#DIV/0!', '#VALUE!', '#REF!', '#NAME?', '#NUM!', '#N/A', '#CIRC!', '#SYNTAX!');

function VEmpty: TValue;
function VNum(const d: TDec): TValue;
function VDate(const d: TDec): TValue;
function VInt(i: Int64): TValue;
function VText(const s: UnicodeString): TValue;
function VBool(b: Boolean): TValue;
function VErr(c: TErrCode): TValue;

function NumToText(const d: TDec): UnicodeString;           { plain notation, 15 significant digits }
function TextOf(const v: TValue): UnicodeString;           { for & and the text functions }
function ToNum(const v: TValue; out d: TDec): Boolean;     { empty is 0, TRUE is 1, text that reads as a number }
function IsNumeric(const v: TValue): Boolean;              { a number or a TRUE/FALSE }
function TextToNum(const s: UnicodeString; out d: TDec): Boolean;

implementation

uses
  SysUtils;

function VEmpty: TValue;
begin
  Result.Kind := vkEmpty;
  Result.Num := DecZero;
  Result.Text := '';
  Result.Bool := False;
  Result.Err := ecDiv0;
  Result.IsDate := False;
end;

function VNum(const d: TDec): TValue;
begin
  Result := VEmpty;
  Result.Kind := vkNum;
  Result.Num := d;
end;

function VDate(const d: TDec): TValue;
begin
  Result := VNum(d);
  Result.IsDate := True;
end;

function VInt(i: Int64): TValue;
begin
  Result := VNum(DecFromInt(i));
end;

function VText(const s: UnicodeString): TValue;
begin
  Result := VEmpty;
  Result.Kind := vkText;
  Result.Text := s;
end;

function VBool(b: Boolean): TValue;
begin
  Result := VEmpty;
  Result.Kind := vkBool;
  Result.Bool := b;
end;

function VErr(c: TErrCode): TValue;
begin
  Result := VEmpty;
  Result.Kind := vkErr;
  Result.Err := c;
end;

function NumToText(const d: TDec): UnicodeString;
begin
  Result := UnicodeString(DecToStr(DecRoundSig(d, DEC_CMP_SIG)));
end;

function TextOf(const v: TValue): UnicodeString;
begin
  case v.Kind of
    vkNum: Result := NumToText(v.Num);
    vkText: Result := v.Text;
    vkBool: if v.Bool then Result := 'TRUE' else Result := 'FALSE';
    vkErr: Result := UnicodeString(ErrNames[v.Err]);
  else
    Result := '';
  end;
end;

function TextToNum(const s: UnicodeString; out d: TDec): Boolean;
begin
  Result := DecFromStr(UnicodeString(Trim(string(s))), d);
end;

function ToNum(const v: TValue; out d: TDec): Boolean;
begin
  d := DecZero;
  case v.Kind of
    vkEmpty: Result := True;
    vkNum: begin d := v.Num; Result := True; end;
    vkBool: begin if v.Bool then d := DecFromInt(1); Result := True; end;
    vkText: Result := TextToNum(v.Text, d);
  else
    Result := False;
  end;
end;

function IsNumeric(const v: TValue): Boolean;
begin
  Result := v.Kind in [vkNum, vkBool];
end;

end.
