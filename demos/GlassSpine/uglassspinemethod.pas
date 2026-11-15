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
  Text: array[0..65] of string = (
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
    'The needle cannot be resolved (a 25G lumen is a fifth of a cell), so the injectate enters at the '
      + 'chosen rate in a 2.5 mm sphere at the needle tip, 3 mm inside the posterior dura at the chosen '
      + 'interspace - by default as a true volume source that pushes CSF aside (section 8). '
      + 'The momentum of the jet leaving the needle (flow Q through lumen area A) is spread over the '
      + 'same sphere as a body force of acceleration Q^2 / (A V), directed cephalad or caudad as the '
      + 'needle''s opening faces: a finer needle gives a faster, stronger jet for the same dose and time.',
    '',
    '7. CSF PULSATION',
    '',
    'CSF is not still. With each heartbeat the brain''s arteries fill and push CSF down through the '
      + 'foramen magnum into the spinal sac; the dura and the epidural veins around it give, take the '
      + 'volume up, and hand it back in diastole. Breathing does the same more slowly. Here each wave is '
      + 'a sine, the flow into the top of the sac being pi f V sin(2 pi f t), where V is the volume per '
      + 'cycle through T1 (defaults 0.3 mL a beat at 70 /min and 0.3 mL a breath at 12 /min - estimates; '
      + 'cervical stroke volumes measured by MRI are 0.5-0.8 mL, falling down the canal).',
    'The CSF enters through a 10 mm band at the T1 end and is taken up evenly by every cell of the sac, '
      + 'so the volume crossing a level falls in proportion to the CSF below it, to nothing at S2. In the '
      + 'pressure equation this is a prescribed source, div u = s, instead of zero, which still sums to '
      + 'zero over each sac.',
    'Two numerical points. First, the flow this needs runs the whole length of the sac, and the '
      + 'pressure solver''s sweeps would take thousands of steps to build it; so each step the change in '
      + 'the flow is added directly as a flat ("plug") profile across every section - appropriate, since '
      + 'the Womersley number is about 20, which makes the real profile nearly flat outside a thin layer '
      + 'at the wall. Second, the small error the sweeps leave in each cell is smooth and of one sign over '
      + 'long stretches, and summed over thousands of cells it made the net flow through a level drift by '
      + 'tens of per cent. So before each projection the flow through every cross-section is summed and '
      + 'set exactly to what the sources require (zero without pulsation, as a closed sac demands), '
      + 'leaving the solver only the work within each section. The flow through L3, L1, T8 and T2 then '
      + 'matches the prescription to under 1 %.',
    'Where the dura takes up CSF, a cell of the fixed grid stands for a slightly larger volume; the '
      + 'drug''s concentration there is unchanged (it is carried with the fluid), and the amount of drug '
      + 'reported allows for the dilation, so it stays equal to the dose.',
    'Effect: in the supine position, with the defaults, hyperbaric solution reaches T9-T8 by two '
      + 'minutes instead of T5, and more of it stays at T12-L2. The heartbeat does nearly all of this; '
      + 'breathing at the default volume does little. The likely reason is that the oscillation stirs '
      + 'the thin sheet of heavy solution running down the posterior dura, diluting it and so weakening '
      + 'what drives it - a reading of the numbers, not separately tested. Left lateral it is the same '
      + 'story (T9 instead of T7 at two minutes); sitting, where the heavy solution has only a short way '
      + 'to fall to the sacrum, it makes no difference (S2-L1 either way). Plain solution is unaffected '
      + 'in all three positions.',
    '',
    '8. THE INJECTED VOLUME',
    '',
    'Injecting 3 mL into a closed sac must push 3 mL of CSF somewhere. Most goes up through the foramen '
      + 'magnum into the head, and the rest is taken up by the spinal dura and the epidural veins; the '
      + 'spinal canal holds roughly a third of the craniospinal compliance, so here two thirds of the '
      + 'injected volume leaves through the T1 end and one third is taken up evenly along the sac (an '
      + 'estimate). This is the same machinery as the pulsation: the source sphere is a prescribed '
      + 'source of pure injectate, the outflows are prescribed sinks, the flow is added as a plug and '
      + 'held exact section by section, and the computed flow matches the prescription to under 1 %.',
    'For 3 mL over 15 s that is 1-2 mm/s of CSF moving up the sac above the needle (faster where '
      + 'the sac is narrow) while the '
      + 'injection lasts. Its effect is small but visible: plain solution is carried a little higher '
      + '(T11 rather than T12-T11 at about 2.5 minutes, supine), and sitting the hyperbaric solution '
      + 'reaches T12 rather than L1 at one minute. Untick "Injected volume displaces CSF" to have the '
      + 'injectate replace CSF in place instead, as C := C + f (1 - C) in the source sphere.',
    '',
    '9. WHAT IS LEFT OUT',
    '',
    '  - the true shape of the pulse (here two sines) and where along the canal the dura and epidural '
      + 'veins are most compliant (here everywhere equally);',
    '  - the CSF pressure rise an injection causes, and how the compliance shares out between head and '
      + 'spine with it (here a fixed two thirds and one third);',
    '  - uptake of drug into nerve roots and cord, and its clearance - C here is injectate fraction, not '
      + 'block height, though the two are related;',
    '  - the arachnoid trabeculae and individual nerve roots.',
    'Concentration is the volume fraction of injectate; multiply by the solution''s strength for mg/mL.',
    '',
    '10. DISPLAY',
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
      Lines.Add('11. THIS RUN');
      Lines.Add('');
      Lines.Add(Format('  device: %s', [Sim.DeviceName]));
      Lines.Add(Format('  grid: %d x %d x %d cells of %.2f mm, %d fluid cells a sac, %.1f mL CSF a sac, '
        + 'sac %.0f mm long', [Sim.Geom.NX, Sim.Geom.NY, Sim.Geom.NZ, Sim.Geom.Dx,
        Sim.Geom.FluidCount[0], Sim.Geom.FluidCount[0] * Sim.Geom.CellVolume / 1000, Sim.Geom.Length]));
      Lines.Add(Format('  time step %.3f s; viscosity %.2f mm^2/s, %d Jacobi sweeps; pressure %d SOR sweeps, '
        + 'over-relaxation %.2f; drug sub-steps to Courant %.2f',
        [Sim.Dt, Sim.Nu, Sim.ViscIters, Sim.PressureIters, Sim.Omega, Sim.CFL]));
      Lines.Add(Format('  CSF density %.5f g/mL; g = %.0f mm/s^2', [CSFDensity, GravityMM]));
      if Sim.Pulse then
        Lines.Add(Format('  pulsation %.2f mL a beat at %.0f /min, %.2f mL a breath at %.0f /min',
          [Sim.CardiacML, Sim.HeartRate, Sim.RespML, Sim.RespRate]))
      else
        Lines.Add('  pulsation off');
      if Sim.Displace then
        Lines.Add(Format('  the injected volume displaces CSF, %.0f %% of it to the head',
          [100 * Sim.HeadFraction]))
      else
        Lines.Add('  the injectate replaces CSF in place');
    end;
  finally
    Lines.EndUpdate;
  end;
end;

end.
