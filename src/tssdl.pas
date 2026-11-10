{ tssdl - minimal SDL2 / SDL2_ttf bindings, loaded at run time.

  Nothing is linked at build time, so the program builds without SDL headers or
  import libraries, and the command-line export modes work on a machine that has
  no SDL at all.  Layouts below were checked against the SDL 2.32 headers for
  64-bit builds (sizeof SDL_Event = 56, SDL_Surface.pixels at offset 32). }
unit tssdl;

{$mode objfpc}{$H+}
{$IFNDEF CPU64}{$ERROR tssdl only supports 64-bit targets}{$ENDIF}

interface

uses
  SysUtils, dynlibs;

const
  SDL_INIT_VIDEO = $00000020;
  SDL_WINDOWPOS_UNDEFINED = $1FFF0000;
  SDL_WINDOW_RESIZABLE = $00000020;
  SDL_RENDERER_SOFTWARE = $00000001;
  SDL_RENDERER_ACCELERATED = $00000002;
  SDL_PIXELFORMAT_ARGB8888 = 372645892;
  SDL_BLENDMODE_NONE = 0;
  SDL_BLENDMODE_BLEND = 1;

  SDL_QUITEV = $100;
  SDL_WINDOWEVENT = $200;
  SDL_KEYDOWN = $300;
  SDL_KEYUP = $301;
  SDL_TEXTINPUT = $303;
  SDL_MOUSEMOTION = $400;
  SDL_MOUSEBUTTONDOWN = $401;
  SDL_MOUSEBUTTONUP = $402;
  SDL_MOUSEWHEEL = $403;

  SDL_RENDER_TARGETS_RESET = $2000;
  SDL_RENDER_DEVICE_RESET = $2001;

  SDL_WINDOWEVENT_EXPOSED = 3;
  SDL_WINDOWEVENT_RESIZED = 5;
  SDL_WINDOWEVENT_SIZE_CHANGED = 6;
  SDL_WINDOWEVENT_CLOSE = 14;

  KMOD_LSHIFT = $0001;
  KMOD_RSHIFT = $0002;
  KMOD_LCTRL = $0040;
  KMOD_RCTRL = $0080;
  KMOD_LALT = $0100;
  KMOD_RALT = $0200;
  KMOD_SHIFT = KMOD_LSHIFT or KMOD_RSHIFT;
  KMOD_CTRL = KMOD_LCTRL or KMOD_RCTRL;
  KMOD_ALT = KMOD_LALT or KMOD_RALT;

  SDLK_RETURN = 13;
  SDLK_ESCAPE = 27;
  SDLK_BACKSPACE = 8;
  SDLK_TAB = 9;
  SDLK_SPACE = 32;
  SDLK_DELETE = 127;
  SDLK_F1 = 1073741882;
  SDLK_F2 = 1073741883;
  SDLK_F3 = 1073741884;
  SDLK_F4 = 1073741885;
  SDLK_F5 = 1073741886;
  SDLK_F6 = 1073741887;
  SDLK_F7 = 1073741888;
  SDLK_F8 = 1073741889;
  SDLK_F9 = 1073741890;
  SDLK_F10 = 1073741891;
  SDLK_F11 = 1073741892;
  SDLK_F12 = 1073741893;
  SDLK_INSERT = 1073741897;
  SDLK_HOME = 1073741898;
  SDLK_PAGEUP = 1073741899;
  SDLK_END = 1073741901;
  SDLK_PAGEDOWN = 1073741902;
  SDLK_RIGHT = 1073741903;
  SDLK_LEFT = 1073741904;
  SDLK_DOWN = 1073741905;
  SDLK_UP = 1073741906;
  SDLK_KP_ENTER = 1073741912;
  SDLK_LCTRL = 1073742048;
  SDLK_RCTRL = 1073742052;

type
  TSDL_Rect = record
    x, y, w, h: LongInt;
  end;
  PSDL_Rect = ^TSDL_Rect;

  TSDL_Surface = record
    flags: LongWord;
    pad0: LongWord;
    format: Pointer;
    w, h, pitch: LongInt;
    pad1: LongInt;
    pixels: Pointer;
  end;
  PSDL_Surface = ^TSDL_Surface;

  TSDL_Event = record
    case Integer of
      0: (typ: LongWord);
      1: (raw: array[0..55] of Byte);
  end;

{ Event field accessors (offsets verified against the headers). }
function EvU32(const e: TSDL_Event; ofs: Integer): LongWord;
function EvI32(const e: TSDL_Event; ofs: Integer): LongInt;
function EvKeySym(const e: TSDL_Event): LongInt;
function EvKeyMod(const e: TSDL_Event): LongInt;
function EvKeyRepeat(const e: TSDL_Event): Boolean;
function EvText(const e: TSDL_Event): UnicodeString;
function EvWinEvent(const e: TSDL_Event): Integer;
function EvWinData1(const e: TSDL_Event): LongInt;
function EvWinData2(const e: TSDL_Event): LongInt;
function EvWheelY(const e: TSDL_Event): LongInt;
function EvButton(const e: TSDL_Event): Integer;
function EvButtonX(const e: TSDL_Event): LongInt;
function EvButtonY(const e: TSDL_Event): LongInt;
function EvMotionX(const e: TSDL_Event): LongInt;
function EvMotionY(const e: TSDL_Event): LongInt;
function EvMotionState(const e: TSDL_Event): LongWord;

var
  SDL_Init: function(flags: LongWord): LongInt; cdecl;
  SDL_Quit: procedure; cdecl;
  SDL_GetError: function: PAnsiChar; cdecl;
  SDL_SetHint: function(name, value: PAnsiChar): LongInt; cdecl;
  SDL_CreateWindow: function(title: PAnsiChar; x, y, w, h: LongInt; flags: LongWord): Pointer; cdecl;
  SDL_DestroyWindow: procedure(win: Pointer); cdecl;
  SDL_SetWindowTitle: procedure(win: Pointer; title: PAnsiChar); cdecl;
  SDL_SetWindowMinimumSize: procedure(win: Pointer; w, h: LongInt); cdecl;
  SDL_GetWindowSize: procedure(win: Pointer; var w, h: LongInt); cdecl;
  SDL_SetWindowSize: procedure(win: Pointer; w, h: LongInt); cdecl;
  SDL_CreateRenderer: function(win: Pointer; index: LongInt; flags: LongWord): Pointer; cdecl;
  SDL_DestroyRenderer: procedure(r: Pointer); cdecl;
  SDL_GetRendererOutputSize: function(r: Pointer; var w, h: LongInt): LongInt; cdecl;
  SDL_SetRenderDrawColor: function(r: Pointer; red, green, blue, alpha: Byte): LongInt; cdecl;
  SDL_SetRenderDrawBlendMode: function(r: Pointer; mode: LongInt): LongInt; cdecl;
  SDL_RenderClear: function(r: Pointer): LongInt; cdecl;
  SDL_RenderPresent: procedure(r: Pointer); cdecl;
  SDL_RenderFillRect: function(r: Pointer; const rect: PSDL_Rect): LongInt; cdecl;
  SDL_RenderDrawRect: function(r: Pointer; const rect: PSDL_Rect): LongInt; cdecl;
  SDL_RenderDrawLine: function(r: Pointer; x1, y1, x2, y2: LongInt): LongInt; cdecl;
  SDL_RenderSetClipRect: function(r: Pointer; const rect: PSDL_Rect): LongInt; cdecl;
  SDL_RenderCopy: function(r, tex: Pointer; const src, dst: PSDL_Rect): LongInt; cdecl;
  SDL_RenderReadPixels: function(r: Pointer; const rect: PSDL_Rect; format: LongWord;
    pixels: Pointer; pitch: LongInt): LongInt; cdecl;
  SDL_CreateTextureFromSurface: function(r: Pointer; surf: PSDL_Surface): Pointer; cdecl;
  SDL_DestroyTexture: procedure(tex: Pointer); cdecl;
  SDL_SetTextureColorMod: function(tex: Pointer; red, green, blue: Byte): LongInt; cdecl;
  SDL_SetTextureAlphaMod: function(tex: Pointer; alpha: Byte): LongInt; cdecl;
  SDL_SetTextureBlendMode: function(tex: Pointer; mode: LongInt): LongInt; cdecl;
  SDL_FreeSurface: procedure(surf: PSDL_Surface); cdecl;
  SDL_CreateRGBSurfaceFrom: function(pixels: Pointer; w, h, depth, pitch: LongInt;
    rmask, gmask, bmask, amask: LongWord): PSDL_Surface; cdecl;
  SDL_SetWindowIcon: procedure(win: Pointer; icon: PSDL_Surface); cdecl;
  SDL_PollEvent: function(var e: TSDL_Event): LongInt; cdecl;
  SDL_WaitEventTimeout: function(var e: TSDL_Event; ms: LongInt): LongInt; cdecl;
  SDL_StartTextInput: procedure; cdecl;
  SDL_StopTextInput: procedure; cdecl;
  SDL_GetModState: function: LongInt; cdecl;
  SDL_GetTicks: function: LongWord; cdecl;
  SDL_Delay: procedure(ms: LongWord); cdecl;
  SDL_GetClipboardText: function: PAnsiChar; cdecl;
  SDL_SetClipboardText: function(text: PAnsiChar): LongInt; cdecl;
  SDL_free: procedure(p: Pointer); cdecl;

  TTF_Init: function: LongInt; cdecl;
  TTF_Quit: procedure; cdecl;
  TTF_OpenFont: function(fname: PAnsiChar; ptsize: LongInt): Pointer; cdecl;
  TTF_CloseFont: procedure(font: Pointer); cdecl;
  TTF_FontHeight: function(font: Pointer): LongInt; cdecl;
  TTF_FontAscent: function(font: Pointer): LongInt; cdecl;
  TTF_FontDescent: function(font: Pointer): LongInt; cdecl;
  TTF_GlyphIsProvided32: function(font: Pointer; ch: LongWord): LongInt; cdecl;
  TTF_GlyphMetrics32: function(font: Pointer; ch: LongWord; var minx, maxx, miny, maxy, advance: LongInt): LongInt; cdecl;
  { fg is an SDL_Color passed by value; as four bytes it travels in one integer register }
  TTF_RenderGlyph32_Blended: function(font: Pointer; ch: LongWord; fg: LongWord): PSDL_Surface; cdecl;

{ Loads SDL2 and SDL2_ttf.  Returns '' on success, otherwise a message saying what is missing. }
function LoadSDL: string;
function SDLLoaded: Boolean;

implementation

var
  GotLibs: Boolean = False;
  LibSDL, LibTTF: TLibHandle;

function EvU32(const e: TSDL_Event; ofs: Integer): LongWord;
begin
  Result := PLongWord(@e.raw[ofs])^;
end;

function EvI32(const e: TSDL_Event; ofs: Integer): LongInt;
begin
  Result := PLongInt(@e.raw[ofs])^;
end;

function EvKeySym(const e: TSDL_Event): LongInt;
begin
  Result := EvI32(e, 20);
end;

function EvKeyMod(const e: TSDL_Event): LongInt;
begin
  Result := PWord(@e.raw[24])^;
end;

function EvKeyRepeat(const e: TSDL_Event): Boolean;
begin
  Result := e.raw[13] <> 0;
end;

function EvText(const e: TSDL_Event): UnicodeString;
var
  s: AnsiString;
  i: Integer;
begin
  s := '';
  i := 12;
  while (i < 44) and (e.raw[i] <> 0) do
  begin
    s := s + Chr(e.raw[i]);
    Inc(i);
  end;
  Result := UTF8Decode(s);
end;

function EvWinEvent(const e: TSDL_Event): Integer;
begin
  Result := e.raw[12];
end;

function EvWinData1(const e: TSDL_Event): LongInt;
begin
  Result := EvI32(e, 16);
end;

function EvWinData2(const e: TSDL_Event): LongInt;
begin
  Result := EvI32(e, 20);
end;

function EvWheelY(const e: TSDL_Event): LongInt;
begin
  Result := EvI32(e, 20);
end;

function EvButton(const e: TSDL_Event): Integer;
begin
  Result := e.raw[16];
end;

function EvButtonX(const e: TSDL_Event): LongInt;
begin
  Result := EvI32(e, 20);
end;

function EvButtonY(const e: TSDL_Event): LongInt;
begin
  Result := EvI32(e, 24);
end;

function EvMotionX(const e: TSDL_Event): LongInt;
begin
  Result := EvI32(e, 20);
end;

function EvMotionY(const e: TSDL_Event): LongInt;
begin
  Result := EvI32(e, 24);
end;

function EvMotionState(const e: TSDL_Event): LongWord;
begin
  Result := EvU32(e, 16);
end;

function TryLoad(const names: array of string): TLibHandle;
var
  i: Integer;
begin
  Result := NilHandle;
  for i := 0 to High(names) do
  begin
    Result := LoadLibrary(names[i]);
    if Result <> NilHandle then Exit;
  end;
end;

function SDLLoaded: Boolean;
begin
  Result := GotLibs;
end;

function LoadSDL: string;
var
  missing: string;

  function Sym(lib: TLibHandle; const name: string): Pointer;
  begin
    Result := GetProcedureAddress(lib, name);
    if Result = nil then missing := missing + ' ' + name;
  end;

begin
  if GotLibs then Exit('');
  missing := '';
  {$IFDEF WINDOWS}
  LibSDL := TryLoad(['SDL2.dll']);
  LibTTF := TryLoad(['SDL2_ttf.dll']);
  {$ELSE}
  LibSDL := TryLoad(['libSDL2-2.0.so.0', 'libSDL2.so', 'libSDL2-2.0.so']);
  LibTTF := TryLoad(['libSDL2_ttf-2.0.so.0', 'libSDL2_ttf.so', 'libSDL2_ttf-2.0.so']);
  {$ENDIF}
  if LibSDL = NilHandle then
    Exit('Cannot load the SDL2 library (SDL2.dll / libSDL2-2.0.so.0). Install SDL2.');
  if LibTTF = NilHandle then
    Exit('Cannot load the SDL2_ttf library (SDL2_ttf.dll / libSDL2_ttf-2.0.so.0). Install SDL2_ttf.');

  Pointer(SDL_Init) := Sym(LibSDL, 'SDL_Init');
  Pointer(SDL_Quit) := Sym(LibSDL, 'SDL_Quit');
  Pointer(SDL_GetError) := Sym(LibSDL, 'SDL_GetError');
  Pointer(SDL_SetHint) := Sym(LibSDL, 'SDL_SetHint');
  Pointer(SDL_CreateWindow) := Sym(LibSDL, 'SDL_CreateWindow');
  Pointer(SDL_DestroyWindow) := Sym(LibSDL, 'SDL_DestroyWindow');
  Pointer(SDL_SetWindowTitle) := Sym(LibSDL, 'SDL_SetWindowTitle');
  Pointer(SDL_SetWindowMinimumSize) := Sym(LibSDL, 'SDL_SetWindowMinimumSize');
  Pointer(SDL_GetWindowSize) := Sym(LibSDL, 'SDL_GetWindowSize');
  Pointer(SDL_SetWindowSize) := Sym(LibSDL, 'SDL_SetWindowSize');
  Pointer(SDL_CreateRenderer) := Sym(LibSDL, 'SDL_CreateRenderer');
  Pointer(SDL_DestroyRenderer) := Sym(LibSDL, 'SDL_DestroyRenderer');
  Pointer(SDL_GetRendererOutputSize) := Sym(LibSDL, 'SDL_GetRendererOutputSize');
  Pointer(SDL_SetRenderDrawColor) := Sym(LibSDL, 'SDL_SetRenderDrawColor');
  Pointer(SDL_SetRenderDrawBlendMode) := Sym(LibSDL, 'SDL_SetRenderDrawBlendMode');
  Pointer(SDL_RenderClear) := Sym(LibSDL, 'SDL_RenderClear');
  Pointer(SDL_RenderPresent) := Sym(LibSDL, 'SDL_RenderPresent');
  Pointer(SDL_RenderFillRect) := Sym(LibSDL, 'SDL_RenderFillRect');
  Pointer(SDL_RenderDrawRect) := Sym(LibSDL, 'SDL_RenderDrawRect');
  Pointer(SDL_RenderDrawLine) := Sym(LibSDL, 'SDL_RenderDrawLine');
  Pointer(SDL_RenderSetClipRect) := Sym(LibSDL, 'SDL_RenderSetClipRect');
  Pointer(SDL_RenderCopy) := Sym(LibSDL, 'SDL_RenderCopy');
  Pointer(SDL_RenderReadPixels) := Sym(LibSDL, 'SDL_RenderReadPixels');
  Pointer(SDL_CreateTextureFromSurface) := Sym(LibSDL, 'SDL_CreateTextureFromSurface');
  Pointer(SDL_DestroyTexture) := Sym(LibSDL, 'SDL_DestroyTexture');
  Pointer(SDL_SetTextureColorMod) := Sym(LibSDL, 'SDL_SetTextureColorMod');
  Pointer(SDL_SetTextureAlphaMod) := Sym(LibSDL, 'SDL_SetTextureAlphaMod');
  Pointer(SDL_SetTextureBlendMode) := Sym(LibSDL, 'SDL_SetTextureBlendMode');
  Pointer(SDL_FreeSurface) := Sym(LibSDL, 'SDL_FreeSurface');
  Pointer(SDL_CreateRGBSurfaceFrom) := Sym(LibSDL, 'SDL_CreateRGBSurfaceFrom');
  Pointer(SDL_SetWindowIcon) := Sym(LibSDL, 'SDL_SetWindowIcon');
  Pointer(SDL_PollEvent) := Sym(LibSDL, 'SDL_PollEvent');
  Pointer(SDL_WaitEventTimeout) := Sym(LibSDL, 'SDL_WaitEventTimeout');
  Pointer(SDL_StartTextInput) := Sym(LibSDL, 'SDL_StartTextInput');
  Pointer(SDL_StopTextInput) := Sym(LibSDL, 'SDL_StopTextInput');
  Pointer(SDL_GetModState) := Sym(LibSDL, 'SDL_GetModState');
  Pointer(SDL_GetTicks) := Sym(LibSDL, 'SDL_GetTicks');
  Pointer(SDL_Delay) := Sym(LibSDL, 'SDL_Delay');
  Pointer(SDL_GetClipboardText) := Sym(LibSDL, 'SDL_GetClipboardText');
  Pointer(SDL_SetClipboardText) := Sym(LibSDL, 'SDL_SetClipboardText');
  Pointer(SDL_free) := Sym(LibSDL, 'SDL_free');

  Pointer(TTF_Init) := Sym(LibTTF, 'TTF_Init');
  Pointer(TTF_Quit) := Sym(LibTTF, 'TTF_Quit');
  Pointer(TTF_OpenFont) := Sym(LibTTF, 'TTF_OpenFont');
  Pointer(TTF_CloseFont) := Sym(LibTTF, 'TTF_CloseFont');
  Pointer(TTF_FontHeight) := Sym(LibTTF, 'TTF_FontHeight');
  Pointer(TTF_FontAscent) := Sym(LibTTF, 'TTF_FontAscent');
  Pointer(TTF_FontDescent) := Sym(LibTTF, 'TTF_FontDescent');
  Pointer(TTF_GlyphIsProvided32) := Sym(LibTTF, 'TTF_GlyphIsProvided32');
  Pointer(TTF_GlyphMetrics32) := Sym(LibTTF, 'TTF_GlyphMetrics32');
  Pointer(TTF_RenderGlyph32_Blended) := Sym(LibTTF, 'TTF_RenderGlyph32_Blended');

  if missing <> '' then
    Exit('The SDL2 libraries are too old; missing:' + missing);
  GotLibs := True;
  Result := '';
end;

end.
