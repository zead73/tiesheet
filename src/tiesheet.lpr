{ TieSheet - a small keyboard-first spreadsheet in the style of TiePaper.

  tiesheet [file]                      start the editor (a .tsh file or a .csv)
  tiesheet --convert in out [--values] convert between .tsh and .csv with no window
  tiesheet --script commands.txt [file]  run scripted keystrokes (used by the tests)
  tiesheet --version | --help }
program tiesheet;

{$mode objfpc}{$H+}
{$IFDEF WINDOWS}{$APPTYPE GUI}{$ENDIF}

uses
  {$IFDEF UNIX}cwstring,{$ENDIF}
  {$IFDEF WINDOWS}Windows,{$ENDIF}
  Math, SysUtils, Classes, tsconfig, tssdl, tssheet, tscsv, tsfile, tsapp;

const
  Version = '0.1.0';

{$IFDEF WINDOWS}
function AttachConsole(pid: LongWord): LongBool; stdcall; external 'kernel32.dll' name 'AttachConsole';

var
  ConsoleTried: Boolean = False;
{$ENDIF}

{ The Windows exe has no console of its own; borrow the one it was started from. }
procedure Say(const s: string);
begin
  {$IFDEF WINDOWS}
  if not ConsoleTried then
  begin
    ConsoleTried := True;
    if AttachConsole(LongWord(-1)) then
    begin
      AssignFile(Output, 'CONOUT$');
      {$I-}
      Rewrite(Output);
      {$I+}
      if IOResult <> 0 then Exit;
    end;
  end;
  {$I-}
  WriteLn(s);
  {$I+}
  if IOResult <> 0 then Exit;
  {$ELSE}
  WriteLn(s);
  {$ENDIF}
end;

function LoadAny(sheet: TSheet; const fn: string; warn: TStrings): string;
var
  text: UnicodeString;
begin
  Result := ReadTextFile(fn, text);
  if Result <> '' then Exit;
  if Copy(text, 1, 9) = 'tiesheet ' then Result := SheetFromText(sheet, text, warn)
  else ImportCsv(sheet, text, warn);
end;

function Convert(const inFile, outFile: string; values: Boolean): Integer;
var
  sh: TSheet;
  warn: TStringList;
  err: string;
  i: Integer;
begin
  Result := 1;
  sh := TSheet.Create;
  warn := TStringList.Create;
  try
    err := LoadAny(sh, inFile, warn);
    if err <> '' then begin Say(err); Exit; end;
    for i := 0 to warn.Count - 1 do Say('warning: ' + warn[i]);
    if LowerCase(ExtractFileExt(outFile)) = '.csv' then err := WriteTextFile(outFile, ExportCsv(sh, values))
    else err := SaveSheetFile(sh, outFile);
    if err <> '' then begin Say(err); Exit; end;
    Say(Format('%s: %d cell(s)', [outFile, sh.CellCount]));
    Result := 0;
  finally
    warn.Free;
    sh.Free;
  end;
end;

var
  app: TApp;
  err, arg, file_, scriptFile: string;
  i: Integer;
  values: Boolean;

begin
  { FPC leaves floating-point exceptions unmasked; software OpenGL and some Windows drivers divide by
    zero on their own threads and would kill the program with SIGFPE }
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  {$IFDEF WINDOWS}
  SetMultiByteConversionCodePage(CP_UTF8);
  SetMultiByteRTLFileSystemCodePage(CP_UTF8);
  DefaultSystemCodePage := CP_UTF8;
  {$ENDIF}
  file_ := '';
  scriptFile := '';
  values := False;
  for i := 1 to ParamCount do
    if ParamStr(i) = '--values' then values := True;
  i := 1;
  while i <= ParamCount do
  begin
    arg := ParamStr(i);
    if (arg = '--version') or (arg = '-v') then
    begin
      Say('TieSheet ' + Version);
      Halt(0);
    end
    else if (arg = '--help') or (arg = '-h') then
    begin
      Say('TieSheet ' + Version);
      Say('  tiesheet [file]');
      Say('  tiesheet --convert in out [--values]');
      Halt(0);
    end
    else if (arg = '--convert') and (i + 2 <= ParamCount) then
      Halt(Convert(ParamStr(i + 1), ParamStr(i + 2), values))
    else if (arg = '--script') and (i + 1 <= ParamCount) then
    begin
      scriptFile := ParamStr(i + 1);
      Inc(i);
    end
    else if (Length(arg) > 0) and (arg[1] <> '-') then
      file_ := arg;
    Inc(i);
  end;

  app := TApp.Create;
  try
    err := app.Start(file_);
    if err <> '' then
    begin
      {$IFDEF WINDOWS}
      MessageBoxA(0, PAnsiChar(err), 'TieSheet', 0);
      {$ELSE}
      WriteLn(StdErr, 'TieSheet: ', err);
      {$ENDIF}
      Halt(1);
    end;
    if scriptFile <> '' then app.SetScript(scriptFile);
    app.Run;
  finally
    app.Free;
  end;
end.
