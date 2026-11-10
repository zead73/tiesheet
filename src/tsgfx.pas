{ tsgfx - the character-cell display.

  The screen is a grid of text cells inside a coloured border, like the C64.
  Glyphs are drawn one at a time from the TTF font so every character sits on
  the grid exactly.  Glyph textures are cached per (character, style). }
unit tsgfx;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Generics.Collections, tssdl, tsconfig;

const
  ST_REGULAR = 0;
  ST_BOLD = 1;
  ST_ITALIC = 2;
  ST_BOLDITALIC = 3;

type
  TGlyph = record
    Tex: Pointer;
    W, H: Integer;
  end;

  TGfx = class
  private
    Win, Ren: Pointer;
    Fonts: array[0..3] of Pointer;
    Cache: specialize TDictionary<QWord, TGlyph>;
    FontFiles: array[0..3] of string;
    FFontPx: Integer;
    procedure ClearCache;
    procedure OpenFonts(px: Integer);
    function GetGlyph(ch: WideChar; style: Integer): TGlyph;
  public
    CellW, CellH: Integer;
    WidthPx, HeightPx: Integer;  { window size in pixels }
    Border: Integer;
    Cols, Rows: Integer;
    constructor Create;
    destructor Destroy; override;
    function Init(const title: string; const s: TSettings): string;
    procedure SetFontSize(px: Integer);
    property FontPx: Integer read FFontPx;
    procedure Resized;
    procedure ForgetGlyphs;      { after a lost render device the cached textures are invalid }
    procedure SetTitle(const t: string);
    procedure ClearAll(borderRGB, backRGB: LongWord);
    procedure FillRectPx(x, y, w, h: Integer; rgb: LongWord);
    procedure FillCells(col, row, ncols, nrows: Integer; rgb: LongWord);
    procedure PutChar(col, row: Integer; ch: WideChar; style: Integer; fg: LongWord; dy: Integer = 0);
    procedure PutText(col, row: Integer; const s: UnicodeString; fg: LongWord; style: Integer = 0);
    procedure PutTextBG(col, row: Integer; const s: UnicodeString; fg, bg: LongWord; style: Integer = 0);
    procedure HLine(col, row, ncols, dy: Integer; rgb: LongWord);
    procedure BoxPx(x, y, w, h: Integer; rgb: LongWord);
    procedure Clip(col, row, ncols, nrows: Integer);
    procedure Unclip;
    function CellX(col: Integer): Integer;
    function CellY(row: Integer): Integer;
    procedure Present;
    function Screenshot(const fn: string): string;
    function HasGlyph(ch: WideChar): Boolean;
    procedure DrawBar(col, row: Integer; kind: Integer; rgb: LongWord);
    function Window: Pointer;
  end;

function RGBOf(idx: Integer): LongWord;

implementation

function RGBOf(idx: Integer): LongWord;
begin
  Result := Palette[idx and 15];
end;

constructor TGfx.Create;
begin
  inherited Create;
  Cache := specialize TDictionary<QWord, TGlyph>.Create;
  Border := 12;
end;

destructor TGfx.Destroy;
var
  i: Integer;
begin
  ClearCache;
  Cache.Free;
  for i := 0 to 3 do
    if Fonts[i] <> nil then TTF_CloseFont(Fonts[i]);
  if Ren <> nil then SDL_DestroyRenderer(Ren);
  if Win <> nil then SDL_DestroyWindow(Win);
  inherited Destroy;
end;

function TGfx.Window: Pointer;
begin
  Result := Win;
end;

procedure TGfx.ClearCache;
var
  g: TGlyph;
begin
  for g in Cache.Values do
    if g.Tex <> nil then SDL_DestroyTexture(g.Tex);
  Cache.Clear;
end;

procedure TGfx.OpenFonts(px: Integer);
var
  i: Integer;
  minx, maxx, miny, maxy, adv: LongInt;
begin
  ClearCache;
  for i := 0 to 3 do
  begin
    if Fonts[i] <> nil then TTF_CloseFont(Fonts[i]);
    Fonts[i] := nil;
    if FontFiles[i] <> '' then Fonts[i] := TTF_OpenFont(PAnsiChar(FontFiles[i]), px);
    if Fonts[i] = nil then Fonts[i] := TTF_OpenFont(PAnsiChar(FontFiles[0]), px);
  end;
  FFontPx := px;
  adv := 0;
  TTF_GlyphMetrics32(Fonts[0], Ord('M'), minx, maxx, miny, maxy, adv);
  CellW := adv;
  if CellW < 4 then CellW := 4;
  CellH := TTF_FontHeight(Fonts[0]);
  if CellH < 6 then CellH := 6;
  Resized;
end;

{ The window icon is 128x128 straight-alpha RGBA, compiled into the program as the
  ICON128 resource (see assets/).  A missing or odd-sized resource just means no icon. }
procedure SetWindowIconFromResource(win: Pointer);
const
  IconPx = 128;
var
  rs: TResourceStream;
  surf: PSDL_Surface;
begin
  try
    rs := TResourceStream.Create(HInstance, 'ICON128', PChar(10));  { RT_RCDATA }
  except
    Exit;
  end;
  try
    if rs.Size <> IconPx * IconPx * 4 then Exit;
    surf := SDL_CreateRGBSurfaceFrom(rs.Memory, IconPx, IconPx, 32, IconPx * 4,
      $000000FF, $0000FF00, $00FF0000, $FF000000);
    if surf = nil then Exit;
    SDL_SetWindowIcon(win, surf);  { SDL copies the pixels }
    SDL_FreeSurface(surf);
  finally
    rs.Free;
  end;
end;

function TGfx.Init(const title: string; const s: TSettings): string;
var
  i: Integer;
  styles: array[0..3] of string;
  err: string;
begin
  err := LoadSDL;
  if err <> '' then Exit(err);
  if SDL_Init(SDL_INIT_VIDEO) <> 0 then Exit('SDL_Init failed: ' + string(SDL_GetError()));
  if TTF_Init() <> 0 then Exit('TTF_Init failed: ' + string(SDL_GetError()));
  styles[0] := 'Regular'; styles[1] := 'Bold'; styles[2] := 'Italic'; styles[3] := 'BoldItalic';
  for i := 0 to 3 do FontFiles[i] := FindFontFile(s, styles[i]);
  if FontFiles[0] = '' then
    Exit('No monospaced TTF font found. Put LiberationMono-Regular.ttf (and -Bold, -Italic, -BoldItalic) in the fonts folder next to the program.');
  SDL_SetHint('SDL_RENDER_SCALE_QUALITY', '0');
  { how the desktop matches the window to tiesheet.desktop (and so to its menu icon) }
  SDL_SetHint('SDL_VIDEO_X11_WMCLASS', 'tiesheet');
  SDL_SetHint('SDL_APP_ID', 'tiesheet');
  Win := SDL_CreateWindow(PAnsiChar(title), SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
    s.WinW, s.WinH, SDL_WINDOW_RESIZABLE);
  if Win = nil then Exit('Cannot create the window: ' + string(SDL_GetError()));
  SetWindowIconFromResource(Win);
  Ren := SDL_CreateRenderer(Win, -1, 0);
  if Ren = nil then Ren := SDL_CreateRenderer(Win, -1, SDL_RENDERER_SOFTWARE);
  if Ren = nil then Exit('Cannot create the renderer: ' + string(SDL_GetError()));
  SDL_SetRenderDrawBlendMode(Ren, SDL_BLENDMODE_BLEND);
  SDL_SetWindowMinimumSize(Win, 320, 200);
  OpenFonts(s.FontSize);
  SDL_StartTextInput;
  Result := '';
end;

procedure TGfx.SetFontSize(px: Integer);
begin
  if px < 8 then px := 8;
  if px > 72 then px := 72;
  if px = FFontPx then Exit;
  OpenFonts(px);
end;

procedure TGfx.ForgetGlyphs;
var
  g: TGlyph;
begin
  { the textures are already gone with the device, so just drop the references }
  Cache.Clear;
  g.Tex := nil;
end;

procedure TGfx.Resized;
var
  ww, hh: LongInt;
begin
  SDL_GetRendererOutputSize(Ren, ww, hh);
  WidthPx := ww;
  HeightPx := hh;
  Cols := (WidthPx - 2 * Border) div CellW;
  Rows := (HeightPx - 2 * Border) div CellH;
  if Cols < 20 then Cols := 20;
  if Rows < 6 then Rows := 6;
end;

procedure TGfx.SetTitle(const t: string);
begin
  SDL_SetWindowTitle(Win, PAnsiChar(t));
end;

function TGfx.CellX(col: Integer): Integer;
begin
  Result := Border + col * CellW;
end;

function TGfx.CellY(row: Integer): Integer;
begin
  Result := Border + row * CellH;
end;

procedure SetColor(ren: Pointer; rgb: LongWord; a: Byte = 255);
begin
  SDL_SetRenderDrawColor(ren, (rgb shr 16) and $FF, (rgb shr 8) and $FF, rgb and $FF, a);
end;

procedure TGfx.ClearAll(borderRGB, backRGB: LongWord);
var
  r: TSDL_Rect;
begin
  SetColor(Ren, borderRGB);
  SDL_RenderClear(Ren);
  r.x := Border; r.y := Border;
  r.w := Cols * CellW; r.h := Rows * CellH;
  SetColor(Ren, backRGB);
  SDL_RenderFillRect(Ren, @r);
end;

procedure TGfx.FillRectPx(x, y, w, h: Integer; rgb: LongWord);
var
  r: TSDL_Rect;
begin
  r.x := x; r.y := y; r.w := w; r.h := h;
  SetColor(Ren, rgb);
  SDL_RenderFillRect(Ren, @r);
end;

procedure TGfx.FillCells(col, row, ncols, nrows: Integer; rgb: LongWord);
begin
  if (ncols <= 0) or (nrows <= 0) then Exit;
  FillRectPx(CellX(col), CellY(row), ncols * CellW, nrows * CellH, rgb);
end;

procedure TGfx.BoxPx(x, y, w, h: Integer; rgb: LongWord);
var
  r: TSDL_Rect;
begin
  r.x := x; r.y := y; r.w := w; r.h := h;
  SetColor(Ren, rgb);
  SDL_RenderDrawRect(Ren, @r);
end;

procedure TGfx.HLine(col, row, ncols, dy: Integer; rgb: LongWord);
begin
  SetColor(Ren, rgb);
  SDL_RenderDrawLine(Ren, CellX(col), CellY(row) + dy, CellX(col + ncols) - 1, CellY(row) + dy);
end;

procedure TGfx.Clip(col, row, ncols, nrows: Integer);
var
  r: TSDL_Rect;
begin
  r.x := CellX(col); r.y := CellY(row); r.w := ncols * CellW; r.h := nrows * CellH;
  SDL_RenderSetClipRect(Ren, @r);
end;

procedure TGfx.Unclip;
begin
  SDL_RenderSetClipRect(Ren, nil);
end;

function TGfx.HasGlyph(ch: WideChar): Boolean;
begin
  Result := TTF_GlyphIsProvided32(Fonts[0], Ord(ch)) <> 0;
end;

function TGfx.GetGlyph(ch: WideChar; style: Integer): TGlyph;
var
  key: QWord;
  surf: PSDL_Surface;
  tex: Pointer;
begin
  key := (QWord(style) shl 32) or QWord(Ord(ch));
  if Cache.TryGetValue(key, Result) then Exit;
  Result.Tex := nil;
  Result.W := 0;
  Result.H := 0;
  surf := TTF_RenderGlyph32_Blended(Fonts[style], Ord(ch), $FFFFFFFF);
  if surf <> nil then
  begin
    tex := SDL_CreateTextureFromSurface(Ren, surf);
    if tex <> nil then
    begin
      SDL_SetTextureBlendMode(tex, SDL_BLENDMODE_BLEND);
      Result.Tex := tex;
      Result.W := surf^.w;
      Result.H := surf^.h;
    end;
    SDL_FreeSurface(surf);
  end;
  Cache.Add(key, Result);
end;

procedure TGfx.PutChar(col, row: Integer; ch: WideChar; style: Integer; fg: LongWord; dy: Integer);
var
  g: TGlyph;
  dst: TSDL_Rect;
begin
  if ch = ' ' then Exit;
  g := GetGlyph(ch, style);
  if g.Tex = nil then Exit;
  SDL_SetTextureColorMod(g.Tex, (fg shr 16) and $FF, (fg shr 8) and $FF, fg and $FF);
  dst.x := CellX(col);
  dst.y := CellY(row) + dy;
  dst.w := g.W;
  dst.h := g.H;
  SDL_RenderCopy(Ren, g.Tex, nil, @dst);
end;

procedure TGfx.PutText(col, row: Integer; const s: UnicodeString; fg: LongWord; style: Integer);
var
  i: Integer;
begin
  for i := 1 to Length(s) do PutChar(col + i - 1, row, s[i], style, fg);
end;

procedure TGfx.PutTextBG(col, row: Integer; const s: UnicodeString; fg, bg: LongWord; style: Integer);
begin
  FillCells(col, row, Length(s), 1, bg);
  PutText(col, row, s, fg, style);
end;

{ small custom shapes for the hard space, conditional hyphen and breakpoint }
procedure TGfx.DrawBar(col, row: Integer; kind: Integer; rgb: LongWord);
var
  x, y: Integer;
begin
  x := CellX(col);
  y := CellY(row);
  case kind of
    0: FillRectPx(x + 1, y + CellH - 4, CellW - 2, 2, rgb);                  { hard space: a low bar }
    1: FillRectPx(x + 2, y + CellH div 2 - 1, CellW - 4, 3, rgb);            { conditional hyphen: a thick dash }
    2: begin                                                                    { breakpoint: a short tick }
         FillRectPx(x + CellW div 2, y + 3, 2, CellH - 6, rgb);
       end;
  end;
end;

procedure TGfx.Present;
begin
  SDL_RenderPresent(Ren);
end;

function TGfx.Screenshot(const fn: string): string;
var
  buf: array of Byte;
  rowBytes, y, x, pitch: Integer;
  fs: TFileStream;
  hdr: array[0..53] of Byte;
  fileSize: LongWord;
  line: array of Byte;
  px: PByte;
  ww, hh: LongInt;
begin
  Result := '';
  { the renderer's real size: WidthPx / HeightPx lag behind a resize that has not been handled yet }
  SDL_GetRendererOutputSize(Ren, ww, hh);
  pitch := ww * 4;
  SetLength(buf, pitch * hh);
  if SDL_RenderReadPixels(Ren, nil, SDL_PIXELFORMAT_ARGB8888, @buf[0], pitch) <> 0 then
    Exit('Cannot read the screen: ' + string(SDL_GetError()));
  rowBytes := ((ww * 3 + 3) div 4) * 4;
  fileSize := 54 + rowBytes * hh;
  FillChar(hdr, SizeOf(hdr), 0);
  hdr[0] := Ord('B'); hdr[1] := Ord('M');
  PLongWord(@hdr[2])^ := fileSize;
  PLongWord(@hdr[10])^ := 54;
  PLongWord(@hdr[14])^ := 40;
  PLongInt(@hdr[18])^ := ww;
  PLongInt(@hdr[22])^ := hh;
  PWord(@hdr[26])^ := 1;
  PWord(@hdr[28])^ := 24;
  PLongWord(@hdr[34])^ := rowBytes * hh;
  SetLength(line, rowBytes);
  fs := TFileStream.Create(fn, fmCreate);
  try
    fs.WriteBuffer(hdr, 54);
    for y := hh - 1 downto 0 do
    begin
      FillChar(line[0], rowBytes, 0);
      px := @buf[y * pitch];
      for x := 0 to ww - 1 do
      begin
        line[x * 3] := px[0];
        line[x * 3 + 1] := px[1];
        line[x * 3 + 2] := px[2];
        Inc(px, 4);
      end;
      fs.WriteBuffer(line[0], rowBytes);
    end;
  finally
    fs.Free;
  end;
end;

end.
