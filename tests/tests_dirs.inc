{ tests_dirs.inc - folder listings, sizes, typed paths and places (included by test_engine.pas) }

procedure Touch(const fn: string; size: Integer);
var
  fs: TFileStream;
  buf: string;
begin
  fs := TFileStream.Create(fn, fmCreate);
  try
    buf := StringOfChar('x', size);
    if size > 0 then fs.WriteBuffer(buf[1], size);
  finally
    fs.Free;
  end;
end;

function Names(const e: TDirEntries): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(e) do
  begin
    if i > 0 then Result := Result + '|';
    Result := Result + e[i].Name;
  end;
end;

procedure TestDirs;
var
  root: string;
  e: TDirEntries;
  pl: TPlaces;
  i, j: Integer;
begin
  CheckEq(FmtSize(0), '0 B', 'size 0');
  CheckEq(FmtSize(1023), '1023 B', 'size 1023');
  CheckEq(FmtSize(1024), '1.0 KiB', 'size 1 KiB');
  CheckEq(FmtSize(1536), '1.5 KiB', 'size 1.5 KiB');
  CheckEq(FmtSize(1024 * 1024), '1.0 MiB', 'size 1 MiB');
  CheckEq(FmtSize(Int64(3) * 1024 * 1024 * 1024), '3.0 GiB', 'size 3 GiB');
  Check(MatchesAny('a.csv', '*'), 'star matches all');
  Check(MatchesAny('a.csv', ''), 'empty matches all');
  Check(MatchesAny('A.CSV', '*.csv'), 'case does not matter');
  Check(MatchesAny('a.tsh', '*.csv;*.tsh'), 'two masks');
  Check(MatchesAny('a.tsh', '*.csv; *.tsh'), 'spaces after the semicolon');
  Check(not MatchesAny('a.txt', '*.csv;*.tsh'), 'no match');

  root := 'build/test/dirs';
  if DirectoryExists(root) then
  begin
    DeleteFile(root + '/b.csv'); DeleteFile(root + '/A.tsh'); DeleteFile(root + '/c.txt'); DeleteFile(root + '/.hid.csv');
    DeleteFile(root + '/Zed/in.csv');
    RemoveDir(root + '/sub'); RemoveDir(root + '/Zed');
  end;
  ForceDirectories(root + '/sub');
  ForceDirectories(root + '/Zed');
  Touch(root + '/b.csv', 10);
  Touch(root + '/A.tsh', 2048);
  Touch(root + '/c.txt', 0);
  Touch(root + '/.hid.csv', 1);
  Touch(root + '/Zed/in.csv', 1);
  try
    Check(ListDir(root, False, '*', e), 'list the folder');
    CheckEq(Names(e), '..|sub|Zed|A.tsh|b.csv|c.txt', 'up, folders, then files, each without regard to case; hidden left out');
    Check(e[0].IsUp and e[0].IsDir, '.. is the way up');
    Check(e[1].IsDir and (not e[3].IsDir), 'folders and files are told apart');
    CheckInt(Integer(e[3].Size), 2048, 'a size');
    CheckInt(Integer(e[5].Size), 0, 'an empty file');
    Check(Abs(Now - e[4].MTime) < 1 / 24, 'a file just made has a time within the hour (the zone is right)');
    Check(ListDir(root, True, '*', e), 'again with hidden files');
    CheckEq(Names(e), '..|sub|Zed|.hid.csv|A.tsh|b.csv|c.txt', 'hidden files are listed first among the files');
    Check(ListDir(root, False, '*.csv;*.tsh', e), 'with a filter');
    CheckEq(Names(e), '..|sub|Zed|A.tsh|b.csv', 'the filter limits files but not folders');
    Check(ListDir(root + '/sub', False, '*', e), 'an empty folder');
    CheckEq(Names(e), '..', 'has only the way up');
    Check(not ListDir(root + '/nothing', False, '*', e), 'a folder that is not there');
    {$IFDEF UNIX}
    Check(ListDir('/', False, '*', e), 'the top');
    Check((Length(e) = 0) or (not e[0].IsUp), 'has no way up');
    CheckEq(ResolvePath('/a/b', ''), '/a/b', 'nothing typed is the folder itself');
    CheckEq(ResolvePath('/a/b', 'c'), '/a/b/c', 'a name');
    CheckEq(ResolvePath('/a/b', 'c/d.csv'), '/a/b/c/d.csv', 'a relative path');
    CheckEq(ResolvePath('/a/b', '../x'), '/a/x', 'up and across');
    CheckEq(ResolvePath('/a/b', '/etc'), '/etc', 'an absolute path');
    CheckEq(ResolvePath('/a/b', './c/'), '/a/b/c', 'a trailing slash goes');
    CheckEq(ResolvePath('/a/b', '/..'), '/', 'nothing is above the top');
    CheckEq(ResolvePath('/a/b', '~'), ExcludeTrailingPathDelimiter(UserHome), 'home');
    CheckEq(ResolvePath('/a/b', '~/x'), IncludeTrailingPathDelimiter(UserHome) + 'x', 'under home');
    CheckEq(ResolvePath('/a/b', '  c  '), '/a/b/c', 'spaces around it go');
    CheckEq(ParentDir('/a/b'), '/a', 'parent');
    CheckEq(ParentDir('/a/b/'), '/a', 'parent of a path with a slash');
    CheckEq(ParentDir('/a'), '/', 'parent of a top folder');
    CheckEq(ParentDir('/'), '/', 'nothing above the top');
    {$ENDIF}
    pl := GetPlaces;
    Check(Length(pl) >= 1, 'there are places');
    CheckEq(pl[0].Caption, 'Home', 'the first is home');
    for i := 0 to High(pl) do
    begin
      Check(DirectoryExists(pl[i].Path), 'every place exists: ' + pl[i].Path);
      for j := i + 1 to High(pl) do
        Check(pl[i].Path <> pl[j].Path, 'and appears once: ' + pl[i].Path);
    end;
  finally
    DeleteFile(root + '/b.csv'); DeleteFile(root + '/A.tsh'); DeleteFile(root + '/c.txt'); DeleteFile(root + '/.hid.csv');
    DeleteFile(root + '/Zed/in.csv');
    RemoveDir(root + '/sub'); RemoveDir(root + '/Zed'); RemoveDir(root);
  end;
end;
