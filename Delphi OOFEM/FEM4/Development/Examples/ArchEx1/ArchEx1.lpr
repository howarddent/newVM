program ArchEx1;

{ Stresses in a classic Roman semicircular masonry arch - see the header
  comment of uArchEx1.pas for what is modelled and how the results should
  be read.

  Unlike the older examples in this folder, this one is a plain console
  program rather than an LCL form: nothing here needs a GUI, since the
  numeric report goes to stdout and the field results are viewed in gmsh.
  It therefore builds and runs headless, which is also what makes it
  usable as a regression check on TStructuralEngine.

  Usage:  ArchEx1 [1|2|3] [--no-view]

    1  self weight only (default)
    2  self weight + a point load of 25% of the arch's weight on the
       keystone
    3  self weight + the same load on one haunch, near quarter span -
       the asymmetric case, which throws the thrust line hard over to
       the loaded side

    --no-view   write the results but do not launch gmsh afterwards }

{$mode delphi}{$H+}
{$APPTYPE CONSOLE}

uses
  SysUtils, cblas,
  uArchEx1;

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
      WriteLn('Usage: ArchEx1 [1|2|3] [--no-view]');
      WriteLn('  1 = self weight, 2 = load on the keystone, 3 = load on a haunch');
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
