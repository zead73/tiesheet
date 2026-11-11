{ tsapp - the TieSheet screen: a grid of cells in a coloured border, like the C64.

    tsapp_input.inc   events, the Ctrl tap, scripted input for the tests, prompts
    tsapp_draw.inc    drawing the grid, the input line and the status line
    tsapp_edit.inc    moving, entering, selecting, the clipboard, undo
    tsapp_files.inc   loading, saving, quitting
    tsapp_screens.inc help, column width, format, find, go to }
unit tsapp;

{$mode objfpc}{$H+}
{$codepage utf8}

interface

uses
  SysUtils, Classes, tssdl, tsconfig, tsgfx, tsdec, tsvalue, tsformula, tssheet, tscsv, tsfile, tsdate, tsprint, tsdirs;

const
  SYM_CTRLTAP = $7FFF0001;      { a Control key pressed and released on its own }

type
  TEvKind = (ekNone, ekKey, ekText, ekWheel, ekClick, ekDrag, ekRelease, ekQuit, ekResize);

  TKeyEv = record
    Kind: TEvKind;
    Sym: LongInt;
    Ctrl, Shift, Alt: Boolean;
    Text: UnicodeString;
    X, Y, Wheel, Clicks: Integer;
  end;

  TProc = procedure of object;
  TFileKind = (fkNone, fkTsh, fkCsv);
  TPickMode = (pmOpen, pmSave);

  TUndoStep = record
    Text: UnicodeString;       { the whole sheet as a TieSheet file }
    C, R: Integer;
  end;

  TClipCell = record
    Has: Boolean;
    Raw: UnicodeString;
    Fmt: TFormat;
  end;

  TApp = class
  public
    Gfx: TGfx;
    Sheet: TSheet;
    Cfg: TSettings;
    ConfigPath: string;
    constructor Create;
    destructor Destroy; override;
    function Start(const initialFile: string): string;
    procedure Run;
    procedure SetScript(const fn: string);
    procedure SaveConfig;
  private
    { ---- view ---- }
    CurC, CurR, AnchorC, AnchorR: Integer;
    TopRow, LeftCol: Integer;
    SelActive, SelCols: Boolean;
    BlinkOn, FollowCursor: Boolean;
    CtrlHeld, CtrlTapOK, CtrlMode: Boolean;
    SwallowText: Boolean;
    SwallowUntil: LongWord;
    Msg: UnicodeString;
    MsgErr: Boolean;
    ShownTitle: string;
    { ---- entering ---- }
    Editing: Boolean;
    EditBuf: UnicodeString;
    EditPos: Integer;
    { ---- files ---- }
    FileName: string;
    FileKind: TFileKind;
    CsvValues: Boolean;
    Dirty: Boolean;
    { ---- undo ---- }
    UndoStack, RedoStack: array of TUndoStep;
    UndoBytes: Int64;
    { ---- clipboard, kept with its formulas ---- }
    ClipText: UnicodeString;
    ClipValid: Boolean;
    ClipC, ClipR, ClipW, ClipH: Integer;
    ClipCells: array of TClipCell;
    { ---- search ---- }
    FindText: UnicodeString;
    { ---- prompts and screens ---- }
    PromptText, PromptInput: UnicodeString;
    PromptCur: Integer;
    PromptYN, PromptFresh: Boolean;
    HelpText, HelpLines: TStringList;
    HelpTop, HelpWrapW: Integer;
    PrintJob: TPrintJob;
    { the file picker }
    PkMode: TPickMode;
    PkTitle, PkDir: string;
    PkEntries: TDirEntries;
    PkSel, PkTop, PkFilter, PkPos: Integer;
    PkEdit: UnicodeString;
    PkFresh, PkHidden, PkNavigated: Boolean;
    PkFilterNames, PkFilterPats: TStringList;
    PkPlaces: TPlaces;
    PkPlaceSel: Integer;
    PrevPage, PrevLeft, PrevTop: Integer;
    FullScreen, Overlay: TProc;
    { ---- events and scripts ---- }
    Script: TStringList;
    ScriptPos: Integer;
    ScriptRunning, Done, QuitReq: Boolean;

    { input }
    function Translate(var e: TSDL_Event; var ev: TKeyEv): Boolean;
    function NextEvent(var ev: TKeyEv; waitMs: Integer): Boolean;
    function ScriptNext(var ev: TKeyEv): Boolean;
    function WaitKey(var ev: TKeyEv): Boolean;
    procedure Render;
    procedure SetMsg(const s: UnicodeString; err: Boolean = False);
    procedure CheckDate;
    procedure UpdateTitle;
    { prompts }
    procedure DrawPromptOverlay;
    function Prompt(const text: UnicodeString; var value: UnicodeString; files: Boolean = False): Boolean;
    function AskChoice(const text, keys: UnicodeString): Integer;
    procedure CompleteName;
    { drawing }
    procedure DrawScreen;
    procedure DrawTitleBar;
    procedure DrawInputLine;
    procedure DrawHeaders;
    procedure DrawGrid;
    procedure DrawStatus;
    function GutterW: Integer;
    function VisRows: Integer;
    function VisColsEnd(left: Integer): Integer;
    procedure CellLook(c, r: Integer; out s: UnicodeString; out right: Boolean; out fg: LongWord);
    function SelSummary: UnicodeString;
    { moving and selecting }
    procedure SelRect(out c1, r1, c2, r2: Integer);
    procedure EnsureVisible;
    procedure MoveCursor(nc, nr: Integer; extend: Boolean);
    procedure JumpCursor(dc, dr: Integer; extend: Boolean);
    procedure SelectAll;
    procedure SelectColumn;
    function CellAt(x, y: Integer; out c, r: Integer): Boolean;
    function LastUsed(out lc, lr: Integer): Boolean;
    { entering }
    procedure BeginEdit(replace: Boolean; const initial: UnicodeString);
    procedure EditKey(const ev: TKeyEv);
    procedure CommitEdit(dc, dr: Integer);
    procedure CancelEdit;
    procedure EditInsert(const s: UnicodeString);
    { commands }
    procedure HandleEvent(var ev: TKeyEv);
    procedure HandleKey(const ev: TKeyEv);
    procedure ClearSelection;
    procedure ClipCopy(cut: Boolean);
    procedure ClipPaste;
    procedure FillDown;
    procedure FillRight;
    procedure PushUndo(const before: UnicodeString);
    function Snapshot: UnicodeString;
    procedure DoUndo;
    procedure DoRedo;
    procedure Changed(const before: UnicodeString);
    { files }
    procedure ResetDocument;
    function LoadPath(const fn: string): Boolean;
    procedure DoLoad;
    function DoSave(askName: Boolean): Boolean;
    function ConfirmDiscard: Boolean;
    procedure TryQuit;
    { screens }
    procedure DoHelp;
    procedure WrapHelp(width: Integer);
    procedure DrawHelp;
    procedure DoWidth;
    procedure DoFormat;
    procedure DoGoto;
    procedure DoFind(askFirst: Boolean);
    procedure DoInsert;
    procedure DoDelete;
    procedure DoSort;
    function CurrentRegion(out c1, r1, c2, r2: Integer): Boolean;
    function BuildJob: Boolean;
    function PickFile(mode: TPickMode; const title, startDir, startName: string; const filters: array of string;
      filterIndex: Integer; out path: string): Boolean;
    procedure PkLoad(const dir, focus: string);
    procedure DrawPicker;
    procedure DrawPlaces;
    procedure PkEnter(var finished, ok: Boolean; out path: string);
    function PkPlacesScreen: Boolean;
    procedure PkMakeDir;
    procedure DoPreview;
    procedure DrawPreview;
    procedure DoOutput;
  end;

implementation

const
  SDLK_KP_ENTER = 1073741912;
  SDLK_KP_MINUS = 1073741910;
  SDLK_KP_PLUS = 1073741911;

type
  TRectI = record
    C1, R1, C2, R2: Integer;
  end;

function IfThenStr(c: Boolean; const a, b: string): string;
begin
  if c then Result := a else Result := b;
end;

{ Windows hands clipboard text back with CR LF line ends: make them all LF, which is what was put in }
function NormalizeLineEnds(const s: UnicodeString): UnicodeString;
var
  i, n: Integer;
begin
  SetLength(Result, Length(s));
  n := 0;
  i := 1;
  while i <= Length(s) do
  begin
    if s[i] = #13 then
    begin
      Inc(n);
      Result[n] := #10;
      if (i < Length(s)) and (s[i + 1] = #10) then Inc(i);
    end
    else
    begin
      Inc(n);
      Result[n] := s[i];
    end;
    Inc(i);
  end;
  SetLength(Result, n);
end;

function IfThenInt(c: Boolean; a, b: Integer): Integer;
begin
  if c then Result := a else Result := b;
end;

function LetterOf(sym: LongInt): Char;
begin
  if (sym >= Ord('a')) and (sym <= Ord('z')) then Result := Chr(sym) else Result := #0;
end;

constructor TApp.Create;
begin
  inherited Create;
  Gfx := TGfx.Create;
  Sheet := TSheet.Create;
  Script := TStringList.Create;
  PkFilterNames := TStringList.Create;
  PkFilterPats := TStringList.Create;
  HelpText := TStringList.Create;
  HelpLines := TStringList.Create;
  BlinkOn := True;
  FollowCursor := True;
end;

destructor TApp.Destroy;
begin
  HelpLines.Free;
  HelpText.Free;
  Script.Free;
  PkFilterNames.Free;
  PkFilterPats.Free;
  Sheet.Free;
  Gfx.Free;
  inherited Destroy;
end;

{$I tsapp_input.inc}
{$I tsapp_draw.inc}
{$I tsapp_edit.inc}
{$I tsapp_files.inc}
{$I tsapp_screens.inc}
{$I tsapp_print.inc}
{$I tsapp_picker.inc}

end.
