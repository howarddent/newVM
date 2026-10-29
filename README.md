# newVM

`newVM` is a Free Pascal / Lazarus library providing matrix/vector objects
that wrap Intel MKL (BLAS/LAPACK/VSL), Intel IPP, OpenBLAS, FFTW, and
(where available) GPU acceleration via OpenCL/clFFT and Metal. It is
explicitly inspired by the Dew MtxVec library for Delphi.

## Why this exists

This library was developed largely so that I could migrate my own
software off Delphi/MtxVec and onto Free Pascal, while keeping access to
hardware-accelerated linear algebra where a given machine has it
available. Unlike MtxVec, `newVM` does not distinguish matrix and vector
types — a vector is just an (N,1) or (1,N) matrix — and it ships in four
parallel real/complex × double/single "flavours" plus an integer
companion type for index work. See `CLAUDE.md` for the full architecture
writeup.

## Caveat

This is not a commercial package — I have included only those features I
needed for my own applications, and no guarantees are given as to its
performance. If you want a robust, commercial-level package I recommend
MtxVec or the SDL library.

## Platform support

`newVM` is developed to be multi-platform, and has so far been built and
verified on:

- Windows 11
- Kubuntu
- macOS
- Raspberry Pi

All of the demo applications run on all four platforms. The one
exception is **SDR_Radio** — a small software-defined-radio test
application built on top of `newVMCL` (the OpenCL-backed matrix type),
put together with Claude's help as a way to exercise GPU-accelerated FFT
and real-time DSP through the library rather than as a polished product
in its own right. It works on all four platforms, but is inherently
limited by the SDR hardware and available compute, particularly on
Raspberry Pi.

## Acceleration libraries — you need to configure your own machine

None of MKL, IPP, OpenBLAS, FFTW, OpenCL/clFFT, or Metal are vendored or
auto-installed by this repository. Each machine needs the relevant
libraries installed and discoverable (on `PATH`, or via the platform's
normal dynamic-linker search) before building:

| Platform | Expected acceleration libraries |
|---|---|
| Windows | BLAS (MKL/OpenBLAS), LAPACKE (MKL), FFTW, OpenCL + clFFT |
| Linux (Kubuntu, etc.) | BLAS (MKL/OpenBLAS), LAPACKE (MKL), FFTW, OpenCL + clFFT |
| macOS | FFTW, Metal (+ MetalPerformanceShadersGraph) |
| Raspberry Pi | FFTW, Arm Performance Libraries (ArmPL) |

Run `newvmconfigure` (see `CLAUDE.md`'s "Build" section) after installing
libraries on a given machine — it probes what's actually present and
regenerates `newVMConfig.inc` accordingly. Any backend that isn't found
falls back to a pure-Pascal implementation automatically (`PUREPASCAL`),
so the library still builds and runs correctly without any of these
installed — just slower.

## Acknowledgements

This library's fallback code and a good deal of its implementation work
were built with the assistance of **Claude** (Anthropic). The pure-Pascal
eigenvalue decomposition fallback (`PurePascalEigHqr2`/`S`) is ported from
the EISPACK-derived Balance/Elmhes/Eltran/Hqr2/Balbak routines in
**LMath**, a third-party Pascal numerical library vendored under
`LMath/` for reference. See `CLAUDE.md` for the specifics of what came
from where.

## Contributing

Other developers are welcome to use and extend this code.

## Licence

Copyright (C) 2026 Howard Dent.

newVM is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free
Software Foundation, either version 3 of the License, or (at your option)
any later version. It is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See [`LICENSE`](LICENSE)
for the full text.

Third-party material in this repository keeps its own licence, not this
one: `LMath/`, `Delphi OOFEM/`, `demos/JetVent/naca1135.pas` and
`rayfanno.pas` (public domain), `Anaesthetics/PK-PD/ut_dgls.pas`
(J-P Moreau) and its DMath-derived `ubisect`/`usecant`/`uerrors`, the
three Kaps-Rentrop integrators ported from *Numerical Recipes*
(`Anaesthetics/PK-PD/kaps_Rentrop.PAS`, `Anaesthetics/PK-PD_FPC/uKapsRentrop.pas`,
`demos/Benney/ukapsrentrop.pas`), whose terms are Numerical Recipes'
own, the recorded data under `demos/BioSpectra/data/` (see its
`README.md` for sources and terms), and the place, outline and county
tables in `demos/CanterburyRain/*.inc` (GeoNames, CC BY 4.0; Natural
Earth, public domain; ONS boundaries and Met Office averages, Open
Government Licence).

## Screenshots

`Wave2D_FPC` (under `demos/Chebyshev/`), a Chebyshev-spectral solver for
the 2D wave equation `u_tt = u_xx + u_yy`, rendered live via the
`TVMPlot3D` component:

![2D Wave Equation demo](docs/images/wave2d.png)

`JetFlow` (under `demos/`), a jet-ventilation calculator built on
JetVent's cannula model: oxygen flow from the driving pressure and the
jet's bore and length, whether the jet is choked, the highest Mach number
and lowest temperature and pressure in the jet, its thrust, and the stall
pressure into adult male, adult female and 7-year-old tracheas; any bore
and length, or one of JetVent's six bench cannulae from a list. Here the
Lindholm (2 mm, 9.5 cm) at 3.5 bar is choked and expands to Mach 1.31 at
−55 °C outside it:

![JetFlow jet-ventilation calculator](docs/images/jetflow.png)
