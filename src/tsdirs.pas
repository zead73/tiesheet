{ tsdirs - what a file picker needs to know about folders: the listing, sizes and times, typed paths, and
  the places worth jumping to.  No screen in here, so it can be tested.

  The listing order, the size format, the local-time fix for file dates and the places list follow tiepick,
  the Far-style picker for the desktop portal. }
unit tsdirs;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes;

type
  TDirEntry = record
    Name: string;
    IsDir, IsUp: Boolean;
    Size: Int64;
    MTime: TDateTime;
  end;
  TDirEntries = array of TDirEntry;

  TPlace = record
    Caption, Path: string;
  end;
  TPlaces = array of TPlace;

function UserHome: string;
function FmtSize(n: Int64): string;
{ patterns: masks such as *.tsh;*.csv separated by semicolons; * (or empty) matches everything }
function MatchesAny(const name, patterns: string): Boolean;
{ the folder's entries: ".." first (except at the top), then folders, then files, each in name order
  without regard to case.  Folders are always listed; patterns only limit files. False if it cannot be read. }
function ListDir(const dir: string; showHidden: Boolean; const patterns: string; out entries: TDirEntries): Boolean;
{ an absolute, tidy path for something typed in a picker: ~, ~/x, absolute, or relative to baseDir }
function ResolvePath(const baseDir, typed: string): string;
function ParentDir(const dir: string): string;
function GetPlaces: TPlaces;

implementation

uses
  DateUtils
  {$IFDEF UNIX}, BaseUnix, Unix, unixutil{$ENDIF}
  {$IFDEF WINDOWS}, Windows{$ENDIF};

function UserHome: string;
begin
  {$IFDEF WINDOWS}
  Result := SysUtils.GetEnvironmentVariable('USERPROFILE');
  {$ELSE}
  Result := SysUtils.GetEnvironmentVariable('HOME');
  {$ENDIF}
  if Result = '' then Result := PathDelim;
end;

function FmtSize(n: Int64): string;
var
  fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  if n < 1024 then Result := IntToStr(n) + ' B'
  else if n < 1024 * 1024 then Result := Format('%.1f KiB', [n / 1024], fs)
  else if n < Int64(1024) * 1024 * 1024 then Result := Format('%.1f MiB', [n / (1024 * 1024)], fs)
  else Result := Format('%.1f GiB', [n / (Int64(1024) * 1024 * 1024)], fs);
end;

{ case-insensitive match with * and ? (the Masks unit is not installed with this compiler) }
function MatchMask(const name, mask: string): Boolean;

  function Rec(n, m: Integer): Boolean;
  begin
    while m <= Length(mask) do
    begin
      if mask[m] = '*' then
      begin
        Inc(m);
        if m > Length(mask) then Exit(True);
        while n <= Length(name) + 1 do
        begin
          if Rec(n, m) then Exit(True);
          Inc(n);
        end;
        Exit(False);
      end
      else if n > Length(name) then Exit(False)
      else if (mask[m] <> '?') and (LowerCase(mask[m]) <> LowerCase(name[n])) then Exit(False);
      Inc(n);
      Inc(m);
    end;
    Result := n > Length(name);
  end;

begin
  Result := Rec(1, 1);
end;

function MatchesAny(const name, patterns: string): Boolean;
var
  sl: TStringList;
  i: Integer;
begin
  if (patterns = '') or (patterns = '*') then Exit(True);
  Result := False;
  sl := TStringList.Create;
  try
    sl.Delimiter := ';';
    sl.StrictDelimiter := True;
    sl.DelimitedText := patterns;
    for i := 0 to sl.Count - 1 do
      if (Trim(sl[i]) <> '') and MatchMask(name, Trim(sl[i])) then Exit(True);
  finally
    sl.Free;
  end;
end;

{ Local modification time.  The time FindFirst gives applies today's UTC offset to every date, which is an
  hour off for dates in the other half of the daylight saving year; GetLocalTimezone looks the offset up for
  that very date.  (Found and fixed in tiepick.) }
function LocalMTime(const path: string; findTime: LongInt): TDateTime;
{$IFDEF UNIX}
var
  st: Stat;
begin
  Result := 0;
  if FpStat(path, st) <> 0 then
    if FpLStat(path, st) <> 0 then Exit;
  Result := UnixToDateTime(st.st_mtime);
  if (st.st_mtime >= 0) and (st.st_mtime <= High(LongInt)) then
  begin
    GetLocalTimezone(cint(st.st_mtime));
    Result := Result + TZSeconds / 86400;
  end;
end;
{$ELSE}
begin
  Result := FileDateToDateTime(findTime);
end;
{$ENDIF}

function IsHiddenEntry(const sr: TSearchRec): Boolean;
begin
  Result := (sr.Name <> '') and (sr.Name[1] = '.');
  {$IFDEF WINDOWS}
  if (sr.Attr and faHidden) <> 0 then Result := True;
  {$ENDIF}
end;

function ParentDir(const dir: string): string;
var
  d: string;
begin
  d := ExcludeTrailingPathDelimiter(dir);
  if d = '' then Exit(PathDelim);
  Result := ExtractFilePath(d);
  if Result = '' then Result := PathDelim;
  if (Length(Result) > 1) and (Result[Length(Result)] = PathDelim) then
  begin
    {$IFDEF WINDOWS}
    if not ((Length(Result) = 3) and (Result[2] = ':')) then
    {$ENDIF}
    SetLength(Result, Length(Result) - 1);
  end;
end;

function ListDir(const dir: string; showHidden: Boolean; const patterns: string; out entries: TDirEntries): Boolean;
var
  base, full: string;
  sr: TSearchRec;
  dirs, files: array of TDirEntry;
  e: TDirEntry;
  nd, nf, i, j: Integer;
  tmp: TDirEntry;

  procedure Sort(var a: array of TDirEntry; n: Integer);
  var
    x, y: Integer;
    t: TDirEntry;
  begin
    for x := 1 to n - 1 do
    begin
      t := a[x];
      y := x - 1;
      while (y >= 0) and (LowerCase(a[y].Name) > LowerCase(t.Name)) do
      begin
        a[y + 1] := a[y];
        Dec(y);
      end;
      a[y + 1] := t;
    end;
  end;

begin
  entries := nil;
  base := ExcludeTrailingPathDelimiter(ExpandFileName(dir));
  if base = '' then base := PathDelim;
  if not DirectoryExists(base) then Exit(False);
  nd := 0;
  nf := 0;
  if FindFirst(IncludeTrailingPathDelimiter(base) + '*', faAnyFile, sr) = 0 then
  begin
    repeat
      if (sr.Name = '.') or (sr.Name = '..') then Continue;
      if (not showHidden) and IsHiddenEntry(sr) then Continue;
      full := IncludeTrailingPathDelimiter(base) + sr.Name;
      e := Default(TDirEntry);
      e.Name := sr.Name;
      e.IsDir := ((sr.Attr and faDirectory) <> 0) or (((sr.Attr and faSymLink) <> 0) and DirectoryExists(full));
      e.Size := sr.Size;
      e.MTime := LocalMTime(full, sr.Time);
      if e.IsDir then
      begin
        SetLength(dirs, nd + 1);
        dirs[nd] := e;
        Inc(nd);
      end
      else if MatchesAny(e.Name, patterns) then
      begin
        SetLength(files, nf + 1);
        files[nf] := e;
        Inc(nf);
      end;
    until FindNext(sr) <> 0;
    SysUtils.FindClose(sr);
  end;
  Sort(dirs, nd);
  Sort(files, nf);
  SetLength(entries, 0);
  if ParentDir(base) <> base then
  begin
    tmp := Default(TDirEntry);
    tmp.Name := '..';
    tmp.IsDir := True;
    tmp.IsUp := True;
    SetLength(entries, 1);
    entries[0] := tmp;
  end;
  j := Length(entries);
  SetLength(entries, j + nd + nf);
  for i := 0 to nd - 1 do entries[j + i] := dirs[i];
  for i := 0 to nf - 1 do entries[j + nd + i] := files[i];
  Result := True;
end;

function ResolvePath(const baseDir, typed: string): string;
var
  t: string;
begin
  t := Trim(typed);
  if t = '' then Exit(ExcludeTrailingPathDelimiter(ExpandFileName(baseDir)));
  if t = '~' then t := UserHome
  else if (Length(t) >= 2) and (t[1] = '~') and ((t[2] = '/') or (t[2] = '\')) then
    t := IncludeTrailingPathDelimiter(UserHome) + Copy(t, 3, MaxInt);
  {$IFDEF WINDOWS}
  if not ((Length(t) >= 2) and (t[2] = ':')) and not ((t <> '') and (t[1] in ['/', '\'])) then
    t := IncludeTrailingPathDelimiter(baseDir) + t;
  {$ELSE}
  if t[1] <> '/' then t := IncludeTrailingPathDelimiter(baseDir) + t;
  {$ENDIF}
  Result := ExpandFileName(t);
  if (Length(Result) > 1) and (Result[Length(Result)] = PathDelim) then
  begin
    {$IFDEF WINDOWS}
    if not ((Length(Result) = 3) and (Result[2] = ':')) then
    {$ENDIF}
    SetLength(Result, Length(Result) - 1);
  end;
end;

function GetPlaces: TPlaces;
var
  n: Integer;
  seen: TStringList;

  procedure Add(const cap, path: string);
  begin
    if (path = '') or (not DirectoryExists(path)) then Exit;
    if seen.IndexOf(path) >= 0 then Exit;
    seen.Add(path);
    SetLength(Result, n + 1);
    Result[n].Caption := cap;
    Result[n].Path := path;
    Inc(n);
  end;

  {$IFDEF UNIX}
  function PathOfUri(const uri: string): string;
  var
    i: Integer;
    hex: string;
  begin
    Result := '';
    i := 8;                                  { after file:// }
    while i <= Length(uri) do
    begin
      if (uri[i] = '%') and (i + 2 <= Length(uri)) then
      begin
        hex := '$' + Copy(uri, i + 1, 2);
        Result := Result + Chr(StrToIntDef(hex, 63));
        Inc(i, 3);
      end
      else
      begin
        Result := Result + uri[i];
        Inc(i);
      end;
    end;
  end;

{$ENDIF}

var
  {$IFDEF UNIX}
  f: TextFile;
  line, mp: string;
  p: Integer;
  {$ENDIF}
  {$IFDEF WINDOWS}
  c: Char;
  {$ENDIF}

begin
  Result := nil;
  n := 0;
  seen := TStringList.Create;
  try
    Add('Home', UserHome);
    {$IFDEF UNIX}
    Add('Root', '/');
    { mounted drives }
    AssignFile(f, '/proc/self/mounts');
    {$I-} Reset(f); {$I+}
    if IOResult = 0 then
    begin
      while not Eof(f) do
      begin
        ReadLn(f, line);
        p := Pos(' ', line);
        if p = 0 then Continue;
        mp := Copy(line, p + 1, MaxInt);
        p := Pos(' ', mp);
        if p > 0 then mp := Copy(mp, 1, p - 1);
        mp := StringReplace(mp, '\040', ' ', [rfReplaceAll]);
        if (Copy(mp, 1, 5) = '/mnt/') or (Copy(mp, 1, 7) = '/media/') or (Copy(mp, 1, 11) = '/run/media/') then
          Add('Drive', mp);
      end;
      CloseFile(f);
    end;
    { GTK bookmarks }
    AssignFile(f, UserHome + '/.config/gtk-3.0/bookmarks');
    {$I-} Reset(f); {$I+}
    if IOResult = 0 then
    begin
      while not Eof(f) do
      begin
        ReadLn(f, line);
        p := Pos(' ', line);
        if p > 0 then line := Copy(line, 1, p - 1);
        if Copy(line, 1, 7) = 'file://' then Add('Bookmark', PathOfUri(line));
      end;
      CloseFile(f);
    end;
    {$ENDIF}
    {$IFDEF WINDOWS}
    for c := 'A' to 'Z' do Add('Drive', c + ':\');
    {$ENDIF}
  finally
    seen.Free;
  end;
end;

end.
