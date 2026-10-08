unit uDABCodecs;

{*******************************************************************************

     Runtime (dlopen) bindings to the two audio codec libraries DAB needs:

       libmpg123 - MPEG-1/2 Layer II, the codec of original "DAB" services
                   (most BBC national stations still).
       libfaad2  - AAC (HE-AAC v1/v2 with SBR and PS), the codec of "DAB+"
                   services. Needs the 960-sample frame length DAB+ uses,
                   which faad2's standard builds include.

     Loaded at runtime rather than linked, the same as fftw3.pas: distro
     packages ship only versioned names (libfaad.so.2, libmpg123.so.0) with
     no -dev symlink, and a missing codec should cost only the stations
     that need it - DAB scanning and the other codec keep working, and the
     receiver reports which library is missing - rather than stopping the
     whole program from starting.

     Only the calls uDABAudio.pas uses are bound. Struct layouts follow
     neaacdec.h (faad2 2.11) with C record packing; "unsigned long" is
     culong, which is 4 bytes on Windows and 8 on 64-bit Unix, and that
     difference has to be carried through for the layouts to match.

*******************************************************************************}

{$mode objfpc}{$H+}
{$PACKRECORDS C}

interface

uses
  SysUtils, DynLibs, ctypes;

const
  {$IFDEF WINDOWS}
  MPG123LibNames: array[0..1] of string = ('libmpg123-0.dll', 'mpg123.dll');
  FAADLibNames: array[0..2] of string = ('libfaad-2.dll', 'libfaad2.dll', 'faad.dll');
  {$ELSE}{$IFDEF DARWIN}
  MPG123LibNames: array[0..1] of string = ('libmpg123.0.dylib', 'libmpg123.dylib');
  FAADLibNames: array[0..1] of string = ('libfaad.2.dylib', 'libfaad.dylib');
  {$ELSE}
  MPG123LibNames: array[0..1] of string = ('libmpg123.so.0', 'libmpg123.so');
  FAADLibNames: array[0..1] of string = ('libfaad.so.2', 'libfaad.so');
  {$ENDIF}{$ENDIF}

  // mpg123.h
  MPG123_OK = 0;
  MPG123_ERR = -1;
  MPG123_NEED_MORE = -10;
  MPG123_NEW_FORMAT = -11;
  MPG123_DONE = -12;
  MPG123_MONO = 1;
  MPG123_STEREO = 2;
  MPG123_ENC_SIGNED_16 = $D0;
  MPG123_ADD_FLAGS = 2;
  MPG123_QUIET = $20;

  // neaacdec.h
  FAAD_FMT_FLOAT = 4;

type
  // neaacdec.h, faad2 2.11
  TNeAACDecConfiguration = record
    defObjectType: cuchar;
    defSampleRate: culong;
    outputFormat: cuchar;
    downMatrix: cuchar;
    useOldADTSFormat: cuchar;
    dontUpSampleImplicitSBR: cuchar;
  end;
  PNeAACDecConfiguration = ^TNeAACDecConfiguration;

  TNeAACDecFrameInfo = record
    bytesconsumed: culong;
    samples: culong;          // total over all channels
    channels: cuchar;
    error: cuchar;
    samplerate: culong;
    sbr: cuchar;
    object_type: cuchar;
    header_type: cuchar;
    num_front_channels: cuchar;
    num_side_channels: cuchar;
    num_back_channels: cuchar;
    num_lfe_channels: cuchar;
    channel_position: array[0..63] of cuchar;
    ps: cuchar;
    reserved: array[0..63] of cuchar;   // headroom in case a later faad2 grows the struct
  end;

var
  mpg123_init: function: cint; cdecl;
  mpg123_new: function(decoder: PAnsiChar; error: pcint): Pointer; cdecl;
  mpg123_delete: procedure(mh: Pointer); cdecl;
  mpg123_param: function(mh: Pointer; ptype: cint; value: clong; fvalue: cdouble): cint; cdecl;
  mpg123_format_none: function(mh: Pointer): cint; cdecl;
  mpg123_format: function(mh: Pointer; rate: clong; channels, encodings: cint): cint; cdecl;
  mpg123_getformat: function(mh: Pointer; rate: pclong; channels, encoding: pcint): cint; cdecl;
  mpg123_open_feed: function(mh: Pointer): cint; cdecl;
  mpg123_feed: function(mh: Pointer; inbuf: Pointer; size: csize_t): cint; cdecl;
  mpg123_read: function(mh: Pointer; outmemory: Pointer; outmemsize: csize_t; done: pcsize_t): cint; cdecl;

  NeAACDecOpen: function: Pointer; cdecl;
  NeAACDecClose: procedure(h: Pointer); cdecl;
  NeAACDecGetCurrentConfiguration: function(h: Pointer): PNeAACDecConfiguration; cdecl;
  NeAACDecSetConfiguration: function(h: Pointer; config: PNeAACDecConfiguration): cuchar; cdecl;
  NeAACDecInit2: function(h: Pointer; buffer: PByte; size: culong; samplerate: pculong;
    channels: pcuchar): cchar; cdecl;
  NeAACDecDecode: function(h: Pointer; info: Pointer; buffer: PByte; size: culong): Pointer; cdecl;
  NeAACDecGetErrorMessage: function(code: cuchar): PAnsiChar; cdecl;

// True once the library is loaded and every entry point above resolved.
// Safe to call repeatedly; the first call does the loading.
function LoadMPG123: Boolean;
function LoadFAAD: Boolean;

implementation

var
  MPG123Handle: TLibHandle = NilHandle;
  FAADHandle: TLibHandle = NilHandle;
  MPG123Ok, FAADOk: Boolean;

function OpenFirst(const Names: array of string): TLibHandle;
var
  i: Integer;
begin
  for i := 0 to High(Names) do begin
    Result := LoadLibrary(Names[i]);
    if Result <> NilHandle then Exit;
  end;
  Result := NilHandle;
end;

function LoadMPG123: Boolean;
begin
  if MPG123Handle = NilHandle then begin
    MPG123Handle := OpenFirst(MPG123LibNames);
    if MPG123Handle = NilHandle then Exit(False);
    Pointer(mpg123_init) := GetProcedureAddress(MPG123Handle, 'mpg123_init');
    Pointer(mpg123_new) := GetProcedureAddress(MPG123Handle, 'mpg123_new');
    Pointer(mpg123_delete) := GetProcedureAddress(MPG123Handle, 'mpg123_delete');
    Pointer(mpg123_param) := GetProcedureAddress(MPG123Handle, 'mpg123_param');
    Pointer(mpg123_format_none) := GetProcedureAddress(MPG123Handle, 'mpg123_format_none');
    Pointer(mpg123_format) := GetProcedureAddress(MPG123Handle, 'mpg123_format');
    Pointer(mpg123_getformat) := GetProcedureAddress(MPG123Handle, 'mpg123_getformat');
    Pointer(mpg123_open_feed) := GetProcedureAddress(MPG123Handle, 'mpg123_open_feed');
    Pointer(mpg123_feed) := GetProcedureAddress(MPG123Handle, 'mpg123_feed');
    Pointer(mpg123_read) := GetProcedureAddress(MPG123Handle, 'mpg123_read');
    MPG123Ok := Assigned(mpg123_new) and Assigned(mpg123_delete) and Assigned(mpg123_param) and
      Assigned(mpg123_format_none) and Assigned(mpg123_format) and Assigned(mpg123_getformat) and
      Assigned(mpg123_open_feed) and Assigned(mpg123_feed) and Assigned(mpg123_read);
    // Deprecated (a no-op) from mpg123 1.27, required before that.
    if MPG123Ok and Assigned(mpg123_init) then mpg123_init();
  end;
  Result := MPG123Ok;
end;

function LoadFAAD: Boolean;
begin
  if FAADHandle = NilHandle then begin
    FAADHandle := OpenFirst(FAADLibNames);
    if FAADHandle = NilHandle then Exit(False);
    Pointer(NeAACDecOpen) := GetProcedureAddress(FAADHandle, 'NeAACDecOpen');
    Pointer(NeAACDecClose) := GetProcedureAddress(FAADHandle, 'NeAACDecClose');
    Pointer(NeAACDecGetCurrentConfiguration) := GetProcedureAddress(FAADHandle, 'NeAACDecGetCurrentConfiguration');
    Pointer(NeAACDecSetConfiguration) := GetProcedureAddress(FAADHandle, 'NeAACDecSetConfiguration');
    Pointer(NeAACDecInit2) := GetProcedureAddress(FAADHandle, 'NeAACDecInit2');
    Pointer(NeAACDecDecode) := GetProcedureAddress(FAADHandle, 'NeAACDecDecode');
    Pointer(NeAACDecGetErrorMessage) := GetProcedureAddress(FAADHandle, 'NeAACDecGetErrorMessage');
    FAADOk := Assigned(NeAACDecOpen) and Assigned(NeAACDecClose) and
      Assigned(NeAACDecGetCurrentConfiguration) and Assigned(NeAACDecSetConfiguration) and
      Assigned(NeAACDecInit2) and Assigned(NeAACDecDecode);
  end;
  Result := FAADOk;
end;

finalization
  if MPG123Handle <> NilHandle then UnloadLibrary(MPG123Handle);
  if FAADHandle <> NilHandle then UnloadLibrary(FAADHandle);
end.
