{ tests_structure.inc - inserting and deleting rows and columns, and sorting (included by test_engine.pas) }

procedure TestInsertDelete;
var
  sh: TSheet;
  f: TFormat;

  procedure Raw(col, row: Integer; const want: string; const msg: string);
  begin
    CheckEq(string(sh.GetRaw(col, row)), want, msg);
  end;

  procedure Fresh;
  begin
    sh.Clear;
    sh.SetEntry(0, 0, '1');                 { A1 }
    sh.SetEntry(0, 1, '=A1+1');             { A2 }
    sh.SetEntry(0, 2, '=SUM(A1:A2)');       { A3 }
    sh.SetEntry(1, 0, '=$A$1*10');          { B1 }
    sh.SetEntry(1, 2, '=A3');               { B3 }
  end;

begin
  sh := TSheet.Create;
  try
    { rows: a row in the middle of a block stretches the block }
    Fresh;
    sh.InsertRows(1, 1);
    Raw(0, 0, '1', 'above the new row nothing moves');
    Check(not sh.Exists(0, 1), 'the new row is empty');
    Raw(0, 2, '=A1+1', 'a formula below moved down and kept its reference');
    Raw(0, 3, '=SUM(A1:A3)', 'a range over the new row grew');
    Raw(1, 0, '=$A$1*10', 'a fixed reference above is untouched');
    Raw(1, 3, '=A4', 'a reference below followed what it points at');
    CheckEq(string(sh.Display(0, 3)), '3', 'the totals still add up');
    { inserting at the very top moves every reference }
    Fresh;
    sh.InsertRows(0, 2);
    Raw(0, 2, '1', 'two rows at the top');
    Raw(0, 3, '=A3+1', 'references moved by two');
    Raw(0, 4, '=SUM(A3:A4)', 'ranges too');
    Raw(1, 2, '=$A$3*10', 'fixed references move as well when rows are inserted above them');
    { inserting after a range does not grow it }
    Fresh;
    sh.InsertRows(2, 1);
    Raw(0, 3, '=SUM(A1:A2)', 'a row just after a range is not part of it');
    { deleting }
    Fresh;
    sh.DeleteRows(0, 1);
    Raw(0, 0, '=#REF!+1', 'a reference to a deleted row is #REF!');
    Raw(0, 1, '=SUM(A1:A1)', 'a range that loses its first row shrinks');
    Raw(1, 0, '', 'B1 went with the row');
    Raw(1, 1, '=A2', 'B3 moved up to B2 and still points at what it did (A3 is now A2)');
    CheckEq(string(sh.Display(0, 0)), '#REF!', 'and shows it');
    Fresh;
    sh.DeleteRows(1, 1);
    Raw(0, 1, '=SUM(A1:A1)', 'a range loses its last row');
    sh.SetEntry(3, 0, '=A2');
    Fresh;
    sh.DeleteRows(0, 2);
    Raw(0, 0, '=SUM(#REF!)', 'a range that is gone entirely is #REF!');
    Raw(1, 0, '=A1', 'B3 is now B1 and A3 is now A1');
    Fresh;
    sh.DeleteRows(5, 3);
    Raw(0, 2, '=SUM(A1:A2)', 'deleting rows nobody refers to changes nothing');
    { a block written the other way round }
    sh.Clear;
    sh.SetEntry(0, 5, '=SUM(B4:A2)');
    sh.InsertRows(2, 1);
    Raw(0, 6, '=SUM(B5:A2)', 'a reversed block keeps its direction');
    { columns }
    Fresh;
    sh.InsertCols(0, 1);
    Raw(1, 0, '1', 'everything moved right');
    Raw(1, 1, '=B1+1', 'with its references');
    Raw(2, 0, '=$B$1*10', 'fixed ones too');
    Fresh;
    sh.InsertCols(1, 1);
    Raw(0, 1, '=A1+1', 'a column inserted to the right changes nothing on the left');
    Raw(2, 2, '=A3', 'B3 is now C3');
    Fresh;
    sh.DeleteCols(0, 1);
    Raw(0, 0, '=#REF!*10', 'a fixed reference to a deleted column');
    sh.Clear;
    sh.SetEntry(1, 0, '5');
    sh.SetEntry(2, 0, '7');
    sh.SetEntry(3, 0, '=SUM(A1:C1)');
    sh.DeleteCols(1, 1);
    Raw(2, 0, '=SUM(A1:B1)', 'a range over a deleted column closes up');
    CheckEq(string(sh.Display(2, 0)), '7', 'the sum of what is left');
    { widths and column formats move with their columns }
    sh.Clear;
    sh.SetEntry(0, 0, 'a');
    sh.SetEntry(1, 0, 'b');
    sh.SetEntry(2, 0, 'c');
    sh.SetColWidth(1, 30);
    sh.SetColWidth(2, 40);
    f.Kind := nfCurrency; f.Decimals := 2; f.Thousands := True;
    sh.SetColFormat(2, f);
    sh.InsertCols(1, 1);
    CheckInt(sh.ColWidth(1), DEFAULT_COL_WIDTH, 'the new column has the default width');
    CheckInt(sh.ColWidth(2), 30, 'a width moved with its column');
    CheckInt(sh.ColWidth(3), 40, 'and another');
    Check(sh.ColFormat(3).Kind = nfCurrency, 'a column format too');
    Check(sh.ColFormat(2).Kind = nfGeneral, 'and left nothing behind');
    sh.DeleteCols(2, 1);
    CheckInt(sh.ColWidth(2), 40, 'deleting a column brings the next width back');
    CheckInt(sh.ColWidth(3), DEFAULT_COL_WIDTH, 'and the last one is the default again');
    { the end of the sheet: what is pushed off it is gone }
    sh.Clear;
    sh.SetEntry(0, MAX_ROW, 'last');
    sh.SetEntry(0, 0, 'first');
    sh.InsertRows(1, 1);
    Check(not sh.Exists(0, MAX_ROW), 'a cell pushed past the last row is dropped');
    CheckInt(sh.CellCount, 1, 'only the first remains');
    { a formula that is a loop after the change still says so }
    sh.Clear;
    sh.SetEntry(0, 0, '=A3');
    sh.SetEntry(0, 2, '=A1');
    sh.InsertRows(1, 1);
    CheckEq(string(sh.Display(0, 0)), '#CIRC!', 'loops are still found after a change');
    { many rows at once, and the results recalculate }
    sh.Clear;
    sh.SetEntry(0, 0, '5');
    sh.SetEntry(0, 1, '=A1*2');
    sh.InsertRows(0, 100);
    CheckEq(string(sh.Display(0, 101)), '10', 'a hundred rows inserted at the top');
  finally
    sh.Free;
  end;
end;

procedure TestSort;
var
  sh: TSheet;
  i: Integer;

  procedure Load(const items: array of string);
  var
    k: Integer;
  begin
    sh.Clear;
    for k := 0 to High(items) do
      if items[k] <> '' then sh.SetEntry(0, k, UnicodeString(items[k]));
  end;

  function Column: string;
  var
    k: Integer;
    lc, lr: Integer;
  begin
    Result := '';
    if not sh.Extent(lc, lr) then Exit;
    for k := 0 to lr do
    begin
      if k > 0 then Result := Result + '|';
      Result := Result + string(sh.Display(0, k));
    end;
  end;

begin
  sh := TSheet.Create;
  try
    Load(['10', '2', '33', '4']);
    CheckEq(sh.SortRows(0, 0, 0, 3, 0, True), '', 'sort');
    CheckEq(Column, '2|4|10|33', 'numbers ascending (numerically, not as text)');
    sh.SortRows(0, 0, 0, 3, 0, False);
    CheckEq(Column, '33|10|4|2', 'descending');
    Load(['pear', 'Apple', 'cherry', 'banana']);
    sh.SortRows(0, 0, 0, 3, 0, True);
    CheckEq(Column, 'Apple|banana|cherry|pear', 'text ignores case');
    Load(['b', '5', 'a', '1', 'TRUE']);
    sh.SortRows(0, 0, 0, 4, 0, True);
    CheckEq(Column, '1|5|a|b|TRUE', 'numbers, then text, then yes/no');
    { empty cells go last, whichever way }
    Load(['3', '', '1', '', '2']);
    sh.SortRows(0, 0, 0, 4, 0, True);
    CheckEq(Column, '1|2|3', 'empty last, ascending');
    Check((not sh.Exists(0, 3)) and (not sh.Exists(0, 4)), 'and the empty cells are at the end');
    Load(['3', '', '1', '', '2']);
    sh.SortRows(0, 0, 0, 4, 0, False);
    CheckEq(Column, '3|2|1', 'empty last, descending');
    Check((not sh.Exists(0, 3)) and (not sh.Exists(0, 4)), 'and still at the end');
    { a heading row is left out by sorting the rows below it }
    Load(['Name', 'c', 'a', 'b']);
    sh.SortRows(0, 1, 0, 3, 0, True);
    CheckEq(Column, 'Name|a|b|c', 'the heading stays on top');
    { the other columns move with the key }
    sh.Clear;
    sh.SetEntry(0, 0, 'b'); sh.SetEntry(1, 0, '2'); sh.SetEntry(2, 0, 'two');
    sh.SetEntry(0, 1, 'c'); sh.SetEntry(1, 1, '3'); sh.SetEntry(2, 1, 'three');
    sh.SetEntry(0, 2, 'a'); sh.SetEntry(1, 2, '1'); sh.SetEntry(2, 2, 'one');
    sh.SortRows(0, 0, 2, 2, 1, True);
    CheckEq(string(sh.Display(0, 0)) + string(sh.Display(1, 0)) + string(sh.Display(2, 0)), 'a1one', 'row 1 after sorting by column B');
    CheckEq(string(sh.Display(0, 2)) + string(sh.Display(1, 2)) + string(sh.Display(2, 2)), 'c3three', 'row 3');
    { stable: equal keys stay in their order }
    sh.Clear;
    sh.SetEntry(0, 0, '1'); sh.SetEntry(1, 0, 'x');
    sh.SetEntry(0, 1, '1'); sh.SetEntry(1, 1, 'y');
    sh.SetEntry(0, 2, '0'); sh.SetEntry(1, 2, 'z');
    sh.SetEntry(0, 3, '1'); sh.SetEntry(1, 3, 'w');
    sh.SortRows(0, 0, 1, 3, 0, True);
    CheckEq(string(sh.Display(1, 0)) + string(sh.Display(1, 1)) + string(sh.Display(1, 2)) + string(sh.Display(1, 3)), 'zxyw', 'a stable sort');
    { formulas travel with their row, their references following }
    sh.Clear;
    sh.SetEntry(0, 0, '3'); sh.SetEntry(1, 0, '=A1*10');
    sh.SetEntry(0, 1, '1'); sh.SetEntry(1, 1, '=A2*10');
    sh.SetEntry(0, 2, '2'); sh.SetEntry(1, 2, '=A3*10');
    sh.SortRows(0, 0, 1, 2, 0, True);
    CheckEq(string(sh.GetRaw(1, 0)), '=A1*10', 'the formula of the first row');
    CheckEq(string(sh.Display(1, 0)) + '|' + string(sh.Display(1, 1)) + '|' + string(sh.Display(1, 2)), '10|20|30', 'each result goes with its number');
    { formats travel too }
    sh.Clear;
    sh.SetEntry(0, 0, '$5.00');
    sh.SetEntry(0, 1, '$1.00');
    sh.SortRows(0, 0, 0, 1, 0, True);
    CheckEq(string(sh.Display(0, 0)), '$1.00', 'a currency cell keeps its format');
    { a sort column outside the block, or nothing to sort }
    Check(sh.SortRows(0, 0, 0, 1, 3, True) <> '', 'the key must be inside the block');
    CheckEq(sh.SortRows(0, 0, 0, 0, 0, True), '', 'one row is already sorted');
    { sorting many rows is quick enough }
    sh.Clear;
    for i := 0 to 1999 do sh.SetEntry(0, i, UnicodeString(IntToStr((i * 7919) mod 2000)));
    sh.SortRows(0, 0, 0, 1999, 0, True);
    CheckEq(string(sh.Display(0, 0)) + '|' + string(sh.Display(0, 1999)), '0|1999', 'two thousand rows');
  finally
    sh.Free;
  end;
end;
