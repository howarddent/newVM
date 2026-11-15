{
  This file is part of newVM.
  Copyright (C) 2026 Howard Dent
  SPDX-License-Identifier: GPL-3.0-or-later

  newVM is free software: you can redistribute it and/or modify it under
  the terms of the GNU General Public License as published by the Free
  Software Foundation, either version 3 of the License, or (at your
  option) any later version. It is distributed WITHOUT ANY WARRANTY; see
  the file LICENSE at the top of the repository for details.
}

unit uGlassSpineMethod;

{*******************************************************************************

  The text of GlassSpine's "Methodology" tab: how the simulation works, in
  plain prose, one paragraph per line (the memo word-wraps). The closing
  section is filled in from the running simulation, so its figures are
  this run's, not copies that could drift from the code.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, uSpineGeom, uGlassSpineSim;

procedure FillMethodology(Lines: TStrings; Sim: TSpineSim);

implementation

const
  Text: array[0..52] of string = (
    'GLASSSPINE - HOW THE SIMULATION WORKS',
    '',
    'GlassSpine follows a spinal anaesthetic as it spreads through the cerebrospinal fluid (CSF) of a '
      + 'transparent dural sac. Two sacs are simulated side by side under the same posture, one solution '
      + 'in each, so two baricities can be compared directly. Everything runs on the GPU in OpenCL and is '
      + 'drawn with OpenGL.',
    '',
    '1. WHAT DRIVES THE SPREAD',
    '',
    'Baricity is the solution''s density divided by that of CSF (1.00059 g/mL at 37 C). Hyperbaric '
      + 'bupivacaine (glucose 8 %, baricity about 1.020) is heavier than CSF and sinks; plain "isobaric" '
      + 'bupivacaine is slightly lighter at body temperature (about 0.999) and floats a little. The density '
      + 'differences are a few parts in a thousand, so the flow they drive is slow (mm/s), and the CSF is '
      + 'treated by the Boussinesq approximation: incompressible fluid of constant density, with buoyancy '
      + 'as a body force (baricity - 1) C g, where C is the local volume fraction of injectate.',
    '',
    'The spread is therefore set by the posture, which decides where "down" lies along the curved sac, '
      + 'and by the shape of the sac itself: the lumbar lordosis (high point near L3 when supine) and the '
      + 'thoracic kyphosis (low point near T8) divide a hyperbaric dose between the sacrum and the mid '
      + 'thoracic hollow.',
    '',
    '2. THE FLUID: STAM''S STABLE FLUIDS',
    '',
    'The CSF velocity is solved by Jos Stam''s Stable Fluids method (SIGGRAPH 1999), as in his "Real-Time '
      + 'Fluid Dynamics for Games". Each time step (0.01 s) does, in his order:',
    '  - forces: add buoyancy, the needle''s jet and (optionally) drag from the cauda equina;',
    '  - diffuse: viscosity (CSF kinematic viscosity 0.7 mm^2/s), implicitly, by Jacobi sweeps;',
    '  - project: make the velocity divergence-free by solving a Poisson equation for pressure;',
    '  - advect: carry the velocity along itself, tracing each point back along the flow '
      + '(semi-Lagrangian, second-order Runge-Kutta backtrace, trilinear interpolation);',
    '  - project again.',
    'Every step is unconditionally stable, which is what lets the solver run in real time with a fixed '
      + 'step.',
    '',
    'Two changes from Stam''s published method were needed for accuracy in a narrow, curved tube:',
    '  - The grid is staggered (a "MAC" grid, as in Fedkiw, Stam and Jensen 2001): each velocity '
      + 'component lives on the cell faces normal to it rather than at cell centres. Stam''s collocated '
      + 'grid uses a central-difference divergence that cannot see a checkerboard pattern, so the '
      + 'projected flow leaked through the dura and was far from divergence-free near the walls. On the '
      + 'staggered grid a face on the dura is simply closed (zero velocity), and the remaining divergence '
      + 'is about a thousandth of the flow speed per cell.',
    '  - The pressure equation is solved by red-black successive over-relaxation (over-relaxation 1.7, '
      + '30 sweeps, half that for the first projection), started from the previous step''s pressure, '
      + 'rather than by plain Jacobi iteration. The walls are no-flux (Neumann) boundaries.',
    '',
    '3. THE DRUG: CONSERVATIVE TRANSPORT',
    '',
    'Stam moves a dye by the same semi-Lagrangian step as the velocity. That step does not conserve '
      + 'mass: tried here (and its MacCormack refinement), the sacs gained or lost 10-90 % of the dose '
      + 'within half a minute, because a narrow plume of injectate is only a few cells across. So the '
      + 'concentration is moved instead by a finite-volume scheme: whatever leaves one cell through a '
      + 'face enters its neighbour. Face values are reconstructed by MUSCL with the monotonised-central '
      + 'limiter (sharp edges, no new maxima or minima), and time is advanced by a two-stage strong-'
      + 'stability-preserving Runge-Kutta method. The drug step is divided into sub-steps so that no face '
      + 'carries more than 0.3 of a cell per sub-step; the fastest face speed is found on the GPU each '
      + 'step. The injected dose is now conserved exactly.',
    '',
    'No molecular diffusion is added: bupivacaine''s (about 0.001 mm^2/s) is far smaller than the slight '
      + 'smoothing the scheme itself introduces at this resolution.',
    '',
    '4. POSTURE AND GRAVITY',
    '',
    'Gravity is fixed, pointing down the screen. Turning the patient rotates the body, not gravity: '
      + 'from supine (head to the right of the table, anterior up), Roll turns the patient about the long '
      + 'axis (+90 = left lateral, 180 = prone) and Tilt tips the table (+ = head up, +90 = sitting, '
      + '- = head down). The solver works in the body''s own frame, so a change of posture only changes '
      + 'the gravity vector it sees. Turning is assumed slow, so there are no Coriolis or centrifugal '
      + 'forces, and the CSF turns with the dura.',
    '',
    '5. THE DURAL SAC',
    '',
    'The sac runs from S2 to T1 (19 levels, about 54 cm). Each level has a typical length and an '
      + 'elliptical cross-section, interpolated smoothly between levels; the sagittal curve follows the '
      + 'lumbar lordosis (apex at L3) and thoracic kyphosis (nadir at T8) of a supine adult (Hirabayashi '
      + '1995), about 34 mm deep. The spinal cord is a solid elliptical cylinder ending in the conus at '
      + 'L1-L2; below it the cauda equina can be represented, if ticked, as a drag on the flow among the '
      + 'nerve roots. The domain is a regular grid of cubic cells; only the fluid cells are computed. The '
      + 'dimensions are typical values for an adult, not those of a particular patient.',
    '',
    '6. THE INJECTION',
    '',
    'The needle cannot be resolved (a 25G lumen is a fifth of a cell), so the injectate appears at the '
      + 'chosen rate in a 2.5 mm sphere at the needle tip, 3 mm inside the posterior dura at the chosen '
      + 'interspace, as C := C + f (1 - C). The bookkeeping of how much has gone in is done on the GPU. '
      + 'The momentum of the jet leaving the needle (flow Q through lumen area A) is spread over the '
      + 'same sphere as a body force of acceleration Q^2 / (A V), directed cephalad or caudad as the '
      + 'needle''s opening faces: a finer needle gives a faster, stronger jet for the same dose and time.',
    '',
    '7. WHAT IS LEFT OUT',
    '',
    '  - CSF pulsation with the heartbeat and breathing, which adds slow mixing;',
    '  - the injected volume pushing CSF aside (the injectate replaces CSF in place; the displacement is '
      + 'about 1 mm/s along the sac, small beside the buoyant flow);',
    '  - uptake of drug into nerve roots and cord, and its clearance - C here is injectate fraction, not '
      + 'block height, though the two are related;',
    '  - the arachnoid trabeculae and individual nerve roots.',
    'Concentration is the volume fraction of injectate; multiply by the solution''s strength for mg/mL.',
    '',
    '8. DISPLAY',
    '',
    'Each frame the concentration is copied to a 3-D texture and ray-marched by a shader: the dura as '
      + 'glass with a bright rim where it is seen edge-on, the cord as an opaque solid, and the drug as a '
      + 'coloured glow whose opacity grows with the square root of concentration, so thin plumes stay '
      + 'visible. The plot below the view gives the injectate (mL) at each vertebral level.'
  );

procedure FillMethodology(Lines: TStrings; Sim: TSpineSim);
var
  i: Integer;
begin
  Lines.BeginUpdate;
  try
    Lines.Clear;
    for i := 0 to High(Text) do Lines.Add(Text[i]);
    if Sim <> nil then
    begin
      Lines.Add('');
      Lines.Add('9. THIS RUN');
      Lines.Add('');
      Lines.Add(Format('  device: %s', [Sim.DeviceName]));
      Lines.Add(Format('  grid: %d x %d x %d cells of %.2f mm, %d fluid cells a sac, %.1f mL CSF a sac, '
        + 'sac %.0f mm long', [Sim.Geom.NX, Sim.Geom.NY, Sim.Geom.NZ, Sim.Geom.Dx,
        Sim.Geom.FluidCount[0], Sim.Geom.FluidCount[0] * Sim.Geom.CellVolume / 1000, Sim.Geom.Length]));
      Lines.Add(Format('  time step %.3f s; viscosity %.2f mm^2/s, %d Jacobi sweeps; pressure %d SOR sweeps, '
        + 'over-relaxation %.2f; drug sub-steps to Courant %.2f',
        [Sim.Dt, Sim.Nu, Sim.ViscIters, Sim.PressureIters, Sim.Omega, Sim.CFL]));
      Lines.Add(Format('  CSF density %.5f g/mL; g = %.0f mm/s^2', [CSFDensity, GravityMM]));
    end;
  finally
    Lines.EndUpdate;
  end;
end;

end.
