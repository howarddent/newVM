program ThermSlab;

{ Verification of the framework's 3D conduction against a slab, whose
  answer is known exactly. Written because ThermEx1's radial gradient
  came out about a third steeper than the closed form for its geometry,
  mesh-converged, which pointed at the elements rather than at that
  model - see the VERIFICATION STATUS note in uThermEx1.pas.

  See uThermSlab.pas for why a patch test settles it: a linear
  temperature field is exactly representable by both element types, so a
  correct element must reproduce it to machine precision on any mesh,
  and there is no discretisation error to hide behind.

  Usage:  ThermSlab }

{$mode delphi}{$H+}
{$APPTYPE CONSOLE}

uses
  SysUtils, cblas,
  CXS.FEMLAP.Gmsh,
  uThermSlab;

var

  Check : TSlabCheck;

begin

  InitializeCBLAS;

  WriteLn('ThermSlab - is the framework''s 3D conduction right on a slab?');
  WriteLn;

  Check := TSlabCheck.Create;

  try

    try

      Check.UsePenalty := True;
      WriteLn('penalty method:');
      WriteLn('PATCH TEST - both faces held, exact answer linear in x.');
      WriteLn('A linear field is exact in these elements, so anything above');
      WriteLn('rounding is the element formulation, not the mesh.');
      WriteLn;

      Check.PatchTest(GMSH_HEXA, 'hexa', MeshCoarse);
      Check.PatchTest(GMSH_HEXA, 'hexa', MeshFine);
      Check.PatchTest(GMSH_PRISM, 'prism', MeshCoarse);
      Check.PatchTest(GMSH_PRISM, 'prism', MeshFine);

      WriteLn;
      WriteLn('elimination method - rules out the penalty BC as the cause:');
      Check.UsePenalty := False;
      Check.PatchTest(GMSH_HEXA, 'hexa', MeshCoarse);
      Check.PatchTest(GMSH_PRISM, 'prism', MeshCoarse);

      WriteLn;
      WriteLn('GENERATION - uniform source, both faces held, exact peak q*L^2/(8k).');
      WriteLn;
      Check.UsePenalty := False;
      Check.GenerationTest(GMSH_HEXA, 'hexa', MeshCoarse);
      Check.GenerationTest(GMSH_HEXA, 'hexa', MeshFine);
      Check.GenerationTest(GMSH_PRISM, 'prism', MeshCoarse);
      Check.GenerationTest(GMSH_PRISM, 'prism', MeshFine);

      WriteLn;
      WriteLn('CONDUCTANCE - one face held, the other convecting.');
      WriteLn('Exact flux is (T1 - Tinf) / (L/k + 1/h): conduction and film');
      WriteLn('in series. This is the magnitude the patch test cannot check.');
      WriteLn;

      Check.UsePenalty := True;
      Check.ConductanceTest(GMSH_HEXA, 'hexa', MeshCoarse);
      Check.ConductanceTest(GMSH_HEXA, 'hexa', MeshFine);
      Check.ConductanceTest(GMSH_PRISM, 'prism', MeshCoarse);
      Check.ConductanceTest(GMSH_PRISM, 'prism', MeshFine);

      WriteLn;

      if Check.NbFail = 0 then
        WriteLn('All checks passed - the 3D conduction is sound on a slab.')
      else
        WriteLn(Format('%d check(s) FAILED.', [Check.NbFail]));

    except
      on E : Exception do
      begin
        WriteLn;
        WriteLn('ERROR: ', E.Message);
        Halt(1);
      end;
    end;

  finally

    Check.Free;

  end;

end.
