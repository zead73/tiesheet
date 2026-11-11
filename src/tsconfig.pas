{ tsconfig - settings, the C64 palette, and where things live on disk.

  The settings file is ~/.config/tiesheet/tiesheet.ini (the tiesheet folder under the app-data folder on
  Windows), whatever the executable is called.  It is separate from TiePaper's. }
unit tsconfig;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, IniFiles;

const
  { Colodore C64 palette }
  Palette: array[0..15] of LongWord = (
    $000000, $FFFFFF, $813338, $75CEC8, $8E3C97, $56AC4D, $2E2C9B, $EDF171,
    $8E5029, $553800, $C46C71, $4A4A4A, $7B7B7B, $A9FF9F, $706DEB, $B2B2B2);
  PaletteNames: array[0..15] of string = (
    'Black', 'White', 'Red', 'Cyan', 'Purple', 'Green', 'Blue', 'Yellow',
    'Orange', 'Brown', 'L Red', 'D Gray', 'Gray', 'L Green', 'L Blue', 'L Gray');

type
  TSettings = record
    ColText, ColBack, ColBorder: Integer;
    ColFormula: Integer;         { results of formulas }
    ColError: Integer;
    ColHeader: Integer;          { the row numbers and column letters }
    ColSelect: Integer;          { the background of selected cells }
    FontSize: Integer;
    FontFamily: string;          { file prefix, e.g. LiberationMono }
    FontDir: string;             { empty = look in the usual places }
    WinW, WinH: Integer;
    LastDir: string;
    Paper: Integer;              { 0 = Letter, 1 = A4 }
  end;

procedure DefaultSettings(var s: TSettings);
function ConfigDir: string;
function ConfigFile(const name: string): string;
procedure LoadSettings(var s: TSettings; const fn: string);
procedure SaveSettings(const s: TSettings; const fn: string);
function FindFontFile(const s: TSettings; const style: string): string;   { style: Regular, Bold, ... }
function AppDir: string;

implementation

procedure DefaultSettings(var s: TSettings);
begin
  s.ColText := 15;
  s.ColBack := 6;
  s.ColBorder := 14;
  s.ColFormula := 3;
  s.ColError := 10;
  s.ColHeader := 14;
  s.ColSelect := 4;
  s.FontSize := 20;
  s.FontFamily := 'LiberationMono';
  s.FontDir := '';
  s.WinW := 1100;
  s.WinH := 760;
  s.LastDir := '';
  s.Paper := 0;
end;

function AppDir: string;
begin
  Result := ExtractFilePath(ParamStr(0));
end;

function ConfigDir: string;
begin
  Result := GetAppConfigDir(False);
end;

{ the config folder is always named tiesheet, whatever the executable is called }
function AppName: string;
begin
  Result := 'tiesheet';
end;

function ConfigFile(const name: string): string;
begin
  Result := IncludeTrailingPathDelimiter(ConfigDir) + name;
end;

function Clamp(v, lo, hi: Integer): Integer;
begin
  if v < lo then Result := lo else if v > hi then Result := hi else Result := v;
end;

procedure LoadSettings(var s: TSettings; const fn: string);
var
  ini: TIniFile;
begin
  DefaultSettings(s);
  if not FileExists(fn) then Exit;
  ini := TIniFile.Create(fn);
  try
    s.ColText := Clamp(ini.ReadInteger('colors', 'text', s.ColText), 0, 15);
    s.ColBack := Clamp(ini.ReadInteger('colors', 'background', s.ColBack), 0, 15);
    s.ColBorder := Clamp(ini.ReadInteger('colors', 'border', s.ColBorder), 0, 15);
    s.ColFormula := Clamp(ini.ReadInteger('colors', 'formula', s.ColFormula), 0, 15);
    s.ColError := Clamp(ini.ReadInteger('colors', 'error', s.ColError), 0, 15);
    s.ColHeader := Clamp(ini.ReadInteger('colors', 'header', s.ColHeader), 0, 15);
    s.ColSelect := Clamp(ini.ReadInteger('colors', 'selection', s.ColSelect), 0, 15);
    s.FontSize := Clamp(ini.ReadInteger('display', 'fontsize', s.FontSize), 8, 72);
    s.FontFamily := ini.ReadString('display', 'fontfamily', s.FontFamily);
    s.FontDir := ini.ReadString('display', 'fontdir', s.FontDir);
    s.WinW := Clamp(ini.ReadInteger('window', 'width', s.WinW), 400, 8000);
    s.WinH := Clamp(ini.ReadInteger('window', 'height', s.WinH), 300, 6000);
    s.LastDir := ini.ReadString('files', 'lastdir', s.LastDir);
    s.Paper := Clamp(ini.ReadInteger('output', 'paper', s.Paper), 0, 1);
  finally
    ini.Free;
  end;
end;

procedure SaveSettings(const s: TSettings; const fn: string);
var
  ini: TIniFile;
begin
  ForceDirectories(ExtractFilePath(fn));
  ini := TIniFile.Create(fn);
  try
    ini.WriteInteger('colors', 'text', s.ColText);
    ini.WriteInteger('colors', 'background', s.ColBack);
    ini.WriteInteger('colors', 'border', s.ColBorder);
    ini.WriteInteger('colors', 'formula', s.ColFormula);
    ini.WriteInteger('colors', 'error', s.ColError);
    ini.WriteInteger('colors', 'header', s.ColHeader);
    ini.WriteInteger('colors', 'selection', s.ColSelect);
    ini.WriteInteger('display', 'fontsize', s.FontSize);
    ini.WriteString('display', 'fontfamily', s.FontFamily);
    ini.WriteString('display', 'fontdir', s.FontDir);
    ini.WriteInteger('window', 'width', s.WinW);
    ini.WriteInteger('window', 'height', s.WinH);
    ini.WriteString('files', 'lastdir', s.LastDir);
    ini.WriteInteger('output', 'paper', s.Paper);
  finally
    ini.Free;
  end;
end;

function FindFontFile(const s: TSettings; const style: string): string;
var
  dirs: array of string;
  fams: array of string;
  d, f: Integer;
  cand: string;

  procedure AddDir(const x: string);
  begin
    SetLength(dirs, Length(dirs) + 1);
    dirs[High(dirs)] := IncludeTrailingPathDelimiter(x);
  end;

  procedure AddFam(const x: string);
  begin
    SetLength(fams, Length(fams) + 1);
    fams[High(fams)] := x;
  end;

begin
  SetLength(dirs, 0);
  SetLength(fams, 0);
  if s.FontDir <> '' then AddDir(s.FontDir);
  AddDir(AppDir + 'fonts');
  AddDir(AppDir + '..' + PathDelim + 'fonts');
  AddDir(ConfigDir + 'fonts');
  {$IFDEF WINDOWS}
  AddDir('C:\Windows\Fonts');
  {$ELSE}
  AddDir('/usr/share/fonts/liberation');
  AddDir('/usr/share/fonts/liberation-fonts');
  AddDir('/usr/share/fonts/truetype/liberation');
  AddDir('/usr/share/fonts/TTF');
  AddDir('/usr/share/fonts/truetype/dejavu');
  {$ENDIF}
  AddFam(s.FontFamily);
  AddFam('LiberationMono');
  AddFam('DejaVuSansMono');
  for f := 0 to High(fams) do
    for d := 0 to High(dirs) do
    begin
      if style = 'Regular' then
      begin
        cand := dirs[d] + fams[f] + '-Regular.ttf';
        if FileExists(cand) then Exit(cand);
        cand := dirs[d] + fams[f] + '.ttf';
        if FileExists(cand) then Exit(cand);
      end
      else
      begin
        cand := dirs[d] + fams[f] + '-' + style + '.ttf';
        if FileExists(cand) then Exit(cand);
        if style = 'Bold' then
        begin
          cand := dirs[d] + fams[f] + '-Bold.ttf';
          if FileExists(cand) then Exit(cand);
        end;
      end;
    end;
  Result := '';
end;

initialization
  OnGetApplicationName := @AppName;
end.
