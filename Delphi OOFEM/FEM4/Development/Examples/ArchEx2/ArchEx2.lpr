program ArchEx2;

{ Stresses in a Perpendicular (four-centred) masonry arch - the Gothic
  companion to ArchEx1's Roman semicircle. Same span, ring, barrel,
  masonry, mesh density, solve and report; only the shape of the arch
  differs, so the two reports can be compared line for line. See the
  header comment of uArchEx2.pas for the geometry, and uArchEx1.pas's
  for how a bonded elastic result should be read as masonry.

  Like ArchEx1 this is a plain console program rather than an LCL form:
  the numeric report goes to stdout and the field results are viewed in
  gmsh, so it runs headless.

  Usage:  ArchEx2 [1|2|3] [--no-view]

    1  self weight only (default)
    2  self weight + a point load of 25% of the arch's weight on the
       keystone
    3  self weight + the same load at the quarter point of the arch's
       own length, measured from the left springing - the same station
       ArchEx1 loads in its own load case 3

    --no-view   write the results but do not launch gmsh afterwards }

{$mode delphi}{$H+}
{$APPTYPE CONSOLE}

uses
  SysUtils, cblas,
  uArchEx2;

var

  Arch : TArchModel;

  LoadCase, i, v : Integer;

  ViewResults : Boolean;

  Arg : String;

begin

  InitializeCBLAS;

  LoadCase := LoadCaseSelfWeight;
  ViewResults := True;

  for i := 1 to ParamCount do
  begin

    Arg := ParamStr(i);

    if (Arg = '--no-view') or (Arg = '-n') then
      ViewResults := False
    else if TryStrToInt(Arg, v) and (v >= LoadCaseSelfWeight) and (v <= LoadCaseHaunch) then
      LoadCase := v
    else
    begin
      WriteLn('Usage: ArchEx2 [1|2|3] [--no-view]');
      WriteLn('  1 = self weight, 2 = load at the apex, 3 = load on a haunch');
      Halt(1);
    end;

  end;

  Arch := TArchModel.Create(LoadCase);

  try

    try
      Arch.Run(ViewResults);
    except
      on E : Exception do
      begin
        WriteLn;
        WriteLn('ERROR: ', E.Message);
        Halt(1);
      end;
    end;

  finally

    Arch.Free;

  end;

end.
