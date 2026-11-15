/*
  This file is part of newVM.
  Copyright (C) 2026 Howard Dent
  SPDX-License-Identifier: GPL-3.0-or-later

  GlassSpine kernels: Stam's Stable Fluids (SIGGRAPH 1999) - semi-
  Lagrangian advection, implicit viscosity, pressure projection - on a
  staggered (MAC) grid, as in Fedkiw, Stam & Jensen (SIGGRAPH 2001), with
  an arbitrary solid mask: the two dural sacs of uSpineGeom.pas.

  Why staggered: Stam's collocated grid takes the divergence with central
  differences, which the projection can't drive to zero in the compact
  sense, and semi-Lagrangian transport of the drug through that field
  made or destroyed tens of per cent of the injectate within 30 s. On the
  MAC grid the projected field is divergence-free to the solver's
  tolerance.

  STORAGE. v is a float4 per cell: .x is the velocity on the cell's -x
  face (between i-1 and i), .y on its -y face, .z on its -z face. A face
  is open only if both its cells are fluid; closed faces hold zero and are
  never written. Every kernel runs over the list of fluid cells, and a
  fluid cell owns its three lower faces, so each open face is updated
  exactly once. A margin of solid cells round each sac means a fluid
  cell's neighbours always exist.

  NX, NY, NZ come in as build options. Velocity is in mm/s, positions in
  cells (a cell centre at integer coordinates; the -x face of cell i at
  i - 1/2); dtdx = dt/dx converts.

  Concentration C is the injectate's volume fraction (0..1), at cell
  centres. It is NOT advected semi-Lagrangian, which is Stam's way: the
  injectate forms sharp, sheared sheets a cell or two thick, and
  interpolating them gained or lost 10-90 % of the dose within 30 s
  (MacCormack worse than plain). Instead it is a conservative finite-
  volume scheme on the MAC faces - MUSCL with the MC limiter, SSP-RK2,
  sub-cycled by the host to CFL 0.3 - so injectate is neither made nor
  lost. Buoyancy is Boussinesq: the injectate's density excess
  (baricity - 1) times C times gravity - the only force, since CSF of
  uniform density is in hydrostatic balance whatever the posture.

  CSF PULSATION. Each sac exchanges CSF with the head through its top
  end: a flow q(t) (mm^3/s, + = into the sac, i.e. caudally) enters a band
  of cells at the T1 end and is taken up by the dura's compliance, spread
  evenly over every fluid cell. So the projection drives the divergence to
  a prescribed source, div u = q pw.x, where pw.x = w / Vcell with
  w = 1/N_top (band) - 1/N_sac; it sums to zero over a sac, as Neumann
  walls require. The axial flow this needs runs the length of the sac,
  which red-black SOR would take thousands of sweeps to build from
  scratch, so `forces` adds each step's change of q as a plug flow,
  pw.y q on every open z face (pw.y = the volume crossing that face per
  unit q, over the face area; Womersley number ~20, so the real profile
  is nearly flat), and the projection only has to tidy each cross-
  section. The drug keeps its concentration as a cell dilates
  (DC/Dt = 0): c_update adds C div u to the conservative update.

  THE INJECTED VOLUME (Displace) is a second prescribed source of the
  same kind, pwi (float4): .x = w/Vcell with w = +1/n_src in the source
  sphere, -HeadFraction/N_band in the T1 band (CSF pushed out to the
  head) and -(1 - HeadFraction)/N_sac everywhere (the dura's share), .y
  its plug, .z the source sphere's part alone. In c_update the source
  part brings in pure injectate (C = 1, scaled to undilated volumes) and
  the rest leaves or dilates at the local C, so the dose goes in exactly.
  The old replace-in-place injection (inject_prepare/inject) is kept for
  Displace off.

  SECTION FLUX CORRECTION. Even so, the per-cell residual the SOR sweeps
  leave (~1e-3 of the speed) is smooth and of one sign over long
  stretches, and summed over the thousands of cells below a level it
  made the net flux through it drift tens of per cent from what the
  sources dictate - the long axial mode SOR barely touches. So before
  each projection, plane_flux sums the flux through every cross-section
  of each sac (one work-item per section) and plane_correct adds the
  uniform plug that brings it to q G_k (zero without pulsation, so this
  also holds the buoyant flow's net section flux at zero, as a closed sac
  requires). The projection then only works within each section.
*/

#define NXY (NX*NY)
#define FLUID 1
#define SAC1 4
#define ROOTS 8

inline int3 cellOf(int id)
{
  int k = id / NXY;
  int r = id - k * NXY;
  int j = r / NX;
  return (int3)(r - j * NX, j, k);
}

inline float3 clampPos(float3 p)
{
  return clamp(p, (float3)(0.0f), (float3)(NX - 1.001f, NY - 1.001f, NZ - 1.001f));
}

/* trilinear sample of one component (0, 1, 2) of v, at a position given
   in that component's own index coordinates */
inline float sampleComp(__global const float* v, int comp, float3 p)
{
  p = clampPos(p);
  float3 b = floor(p);
  float3 f = p - b;
  int id = (int)b.x + NX * ((int)b.y + NY * (int)b.z);
  #define V(o) v[4 * (id + (o)) + comp]
  float c00 = mix(V(0),         V(1),          f.x);
  float c10 = mix(V(NX),        V(NX + 1),     f.x);
  float c01 = mix(V(NXY),       V(NXY + 1),    f.x);
  float c11 = mix(V(NXY + NX),  V(NXY + NX + 1), f.x);
  #undef V
  return mix(mix(c00, c10, f.y), mix(c01, c11, f.y), f.z);
}

/* the velocity at a point (cell coordinates); the -x face of cell i sits
   at x = i - 1/2, so the x component's index coordinate is x + 1/2 */
inline float3 sampleVel(__global const float4* v, float3 p)
{
  __global const float* vf = (__global const float*)v;
  return (float3)(sampleComp(vf, 0, p + (float3)(0.5f, 0.0f, 0.0f)),
                  sampleComp(vf, 1, p + (float3)(0.0f, 0.5f, 0.0f)),
                  sampleComp(vf, 2, p + (float3)(0.0f, 0.0f, 0.5f)));
}

/* RK2 (midpoint) backtrace from x, starting velocity u */
inline float3 backtrace(__global const float4* v, float3 x, float3 u, float dtdx)
{
  float3 xm = x - 0.5f * dtdx * u;
  return x - dtdx * sampleVel(v, xm);
}

/* body forces on the cell's open lower faces: buoyancy (with C averaged
   onto the face), the needle's jet inside the source sphere, and the
   cauda equina's drag */
__kernel void forces(__global const int* fluid, int n, __global const uchar* fl,
  __global float4* v, __global const float* c,
  float4 g0, float4 g1,      /* (baricity-1)*g in the body frame, mm/s^2, per sac */
  float4 src0, float4 src1,  /* injection sphere: centre (cells), w = radius (cells) */
  float4 jet0, float4 jet1,  /* jet acceleration, mm/s^2 (zero when not injecting) */
  float drag, float dt, __global const float2* pw, float dq,
  __global const float4* pwi, float dqi)
{
  int g = get_global_id(0);
  if (g >= n) return;
  int id = fluid[g];
  uchar f = fl[id];
  int s1 = (f & SAC1) != 0;
  float4 gr = s1 ? g1 : g0;
  float4 src = s1 ? src1 : src0;
  float4 jet = s1 ? jet1 : jet0;
  float3 x = convert_float3(cellOf(id));
  float4 u = v[id];
  float cc = c[id];
  int nb[3] = { id - 1, id - NX, id - NXY };
  for (int a = 0; a < 3; a++)
  {
    uchar fn = fl[nb[a]];
    if (!(fn & FLUID)) continue;
    float3 face = x;
    if (a == 0) face.x -= 0.5f; else if (a == 1) face.y -= 0.5f; else face.z -= 0.5f;
    float cf = 0.5f * (cc + c[nb[a]]);
    float3 d = face - src.xyz;
    int inSrc = dot(d, d) <= src.w * src.w;
    float acc = cf * (a == 0 ? gr.x : a == 1 ? gr.y : gr.z)
              + (inSrc ? (a == 0 ? jet.x : a == 1 ? jet.y : jet.z) : 0.0f);
    float val = (a == 0 ? u.x : a == 1 ? u.y : u.z) + dt * acc;
    if ((f | fn) & ROOTS) val /= (1.0f + dt * drag);
    if (a == 0) u.x = val; else if (a == 1) u.y = val; else u.z = val;
  }
  if (fl[id - NXY] & FLUID) u.z += dq * pw[id].y + dqi * pwi[id].y;
  v[id] = u;
}

/* one Jacobi sweep of Stam's implicit viscous step on each open face,
   (1 + 6a) u - a sum(neighbours) = u0, a = nu dt / dx^2; a closed
   neighbouring face is zero (no slip) */
__kernel void diffuse_vel(__global const int* fluid, int n, __global const uchar* fl,
  __global const float4* v0, __global const float4* vin, __global float4* vout, float a)
{
  int g = get_global_id(0);
  if (g >= n) return;
  int id = fluid[g];
  float4 s = vin[id - 1] + vin[id + 1] + vin[id - NX] + vin[id + NX]
           + vin[id - NXY] + vin[id + NXY];
  float4 r = (v0[id] + a * s) / (1.0f + 6.0f * a);
  if (!(fl[id - 1] & FLUID)) r.x = 0.0f;
  if (!(fl[id - NX] & FLUID)) r.y = 0.0f;
  if (!(fl[id - NXY] & FLUID)) r.z = 0.0f;
  r.w = 0.0f;
  vout[id] = r;
}

/* the divergence of each fluid cell (closed faces carry zero), less the
   pulsation's prescribed source q pw.x */
__kernel void divergence(__global const int* fluid, int n,
  __global const float4* v, __global float* div, float invdx,
  __global const float2* pw, float q, __global const float4* pwi, float qi)
{
  int g = get_global_id(0);
  if (g >= n) return;
  int id = fluid[g];
  float4 u = v[id];
  div[id] = (v[id + 1].x - u.x + v[id + NX].y - u.y + v[id + NXY].z - u.z) * invdx
          - q * pw[id].x - qi * pwi[id].x;
}

/* one red-black SOR half-sweep of lap p = div, with zero normal gradient
   at the walls (a solid neighbour drops out of the stencil). p carries
   dt/rho. */
__kernel void pressure_rb(__global const int* fluid, int n, __global const uchar* fl,
  __global float* p, __global const float* div, float dx2, int colour, float omega)
{
  int g = get_global_id(0);
  if (g >= n) return;
  int id = fluid[g];
  int3 c = cellOf(id);
  if (((c.x + c.y + c.z) & 1) != colour) return;
  float s = 0.0f;
  int cnt = 0;
  if (fl[id - 1] & FLUID)   { s += p[id - 1];   cnt++; }
  if (fl[id + 1] & FLUID)   { s += p[id + 1];   cnt++; }
  if (fl[id - NX] & FLUID)  { s += p[id - NX];  cnt++; }
  if (fl[id + NX] & FLUID)  { s += p[id + NX];  cnt++; }
  if (fl[id - NXY] & FLUID) { s += p[id - NXY]; cnt++; }
  if (fl[id + NXY] & FLUID) { s += p[id + NXY]; cnt++; }
  if (cnt == 0) return;
  float pn = (s - dx2 * div[id]) / (float)cnt;
  p[id] += omega * (pn - p[id]);
}

/* u -= grad p on the open lower faces */
__kernel void subtract_grad(__global const int* fluid, int n, __global const uchar* fl,
  __global float4* v, __global const float* p, float invdx)
{
  int g = get_global_id(0);
  if (g >= n) return;
  int id = fluid[g];
  float pc = p[id];
  float4 u = v[id];
  if (fl[id - 1] & FLUID)   u.x -= (pc - p[id - 1]) * invdx;
  if (fl[id - NX] & FLUID)  u.y -= (pc - p[id - NX]) * invdx;
  if (fl[id - NXY] & FLUID) u.z -= (pc - p[id - NXY]) * invdx;
  v[id] = u;
}

/* semi-Lagrangian self-advection of each open face's velocity */
__kernel void advect_vel(__global const int* fluid, int n, __global const uchar* fl,
  __global const float4* vin, __global float4* vout, float dtdx)
{
  int g = get_global_id(0);
  if (g >= n) return;
  int id = fluid[g];
  __global const float* vf = (__global const float*)vin;
  float3 x = convert_float3(cellOf(id));
  float4 r = (float4)(0.0f);
  if (fl[id - 1] & FLUID)
  {
    float3 p = x - (float3)(0.5f, 0.0f, 0.0f);
    float3 b = backtrace(vin, p, sampleVel(vin, p), dtdx);
    r.x = sampleComp(vf, 0, b + (float3)(0.5f, 0.0f, 0.0f));
  }
  if (fl[id - NX] & FLUID)
  {
    float3 p = x - (float3)(0.0f, 0.5f, 0.0f);
    float3 b = backtrace(vin, p, sampleVel(vin, p), dtdx);
    r.y = sampleComp(vf, 1, b + (float3)(0.0f, 0.5f, 0.0f));
  }
  if (fl[id - NXY] & FLUID)
  {
    float3 p = x - (float3)(0.0f, 0.0f, 0.5f);
    float3 b = backtrace(vin, p, sampleVel(vin, p), dtdx);
    r.z = sampleComp(vf, 2, b + (float3)(0.0f, 0.0f, 0.5f));
  }
  vout[id] = r;
}

/* MC-limited slope from the differences either side */
inline float mcSlope(float a, float b)
{
  if (a * b <= 0.0f) return 0.0f;
  float m = fmin(fmin(2.0f * fabs(a), 2.0f * fabs(b)), 0.5f * fabs(a + b));
  return a > 0.0f ? m : -m;
}

/* the upwind, MUSCL-reconstructed C on the face between cell L and cell R
   (R = L + step), for face velocity u; a solid cell beyond L or R gives a
   zero slope there */
inline float faceC(__global const float* c, __global const uchar* fl, int L, int R,
                   int step, float u)
{
  if (u >= 0.0f)
  {
    int LL = L - step;
    float cl = c[L];
    float sl = (fl[LL] & FLUID) ? mcSlope(cl - c[LL], c[R] - cl) : 0.0f;
    return cl + 0.5f * sl;
  }
  else
  {
    int RR = R + step;
    float cr = c[R];
    float sr = (fl[RR] & FLUID) ? mcSlope(cr - c[L], c[RR] - cr) : 0.0f;
    return cr - 0.5f * sr;
  }
}

/* the volume flux of injectate through each open lower face, times
   dt/dx (so in cell volumes); closed faces carry none */
__kernel void c_flux(__global const int* fluid, int n, __global const uchar* fl,
  __global const float4* v, __global const float* c, __global float4* flux, float dtdx)
{
  int g = get_global_id(0);
  if (g >= n) return;
  int id = fluid[g];
  float4 u = v[id];
  float4 F = (float4)(0.0f);
  if (fl[id - 1] & FLUID)   F.x = dtdx * u.x * faceC(c, fl, id - 1, id, 1, u.x);
  if (fl[id - NX] & FLUID)  F.y = dtdx * u.y * faceC(c, fl, id - NX, id, NX, u.y);
  if (fl[id - NXY] & FLUID) F.z = dtdx * u.z * faceC(c, fl, id - NXY, id, NXY, u.z);
  flux[id] = F;
}

/* one SSP-RK2 stage: cout = a cbase + (1 - a) (cin - div flux + C div u),
   with div u the pulsation's source (sdt = q times the sub-step) */
__kernel void c_update(__global const int* fluid, int n,
  __global const float4* flux, __global const float* cin, __global const float* cbase,
  __global float* cout, float a, __global const float2* pw, float sdt,
  __global const float4* pwi, float sdti, float srcScale)
{
  int g = get_global_id(0);
  if (g >= n) return;
  int id = fluid[g];
  float4 F = flux[id];
  float d = flux[id + 1].x - F.x + flux[id + NX].y - F.y + flux[id + NXY].z - F.z;
  float ci = cin[id];
  float4 wi = pwi[id];
  /* the injection: pure injectate in through the source (wi.z), and the
     rest of its divergence - CSF leaving for the head or the dura - at
     the local concentration */
  float si = sdti * (srcScale * wi.z + (wi.x - wi.z) * ci);
  cout[id] = a * cbase[id] + (1.0f - a) * (ci - d + sdt * pw[id].x * ci + si);
}

/* the largest face speed (mm/s), as float bits into *mx (non-negative
   floats order like their bit patterns) */
__kernel void max_speed(__global const int* fluid, int n, __global const float4* v,
  __global int* mx)
{
  int g = get_global_id(0);
  if (g >= n) return;
  float4 u = fabs(v[fluid[g]]);
  float m = fmax(u.x, fmax(u.y, u.z));
  if (m > 0.0f) atomic_max(mx, as_int(m));
}

/* the injection's bookkeeping, one work-item: for each sac, the volume
   owed (state[s], mm^3) grows by add_s; the source's free capacity is
   sum (1 - C) Vcell; the fraction f of it that pays the debt (at most all
   of it) goes to state[4+s] for `inject`, and what it adds to the running
   total state[2+s]. srcCells holds sac 0's n0 source cells then sac 1's. */
__kernel void inject_prepare(__global const int* srcCells, int n0, int n1,
  __global const float* c, __global float* state, float add0, float add1, float vcell)
{
  if (get_global_id(0) != 0) return;
  for (int s = 0; s < 2; s++)
  {
    int first = s ? n0 : 0;
    int count = s ? n1 : n0;
    float cap = 0.0f;
    for (int i = 0; i < count; i++) cap += (1.0f - c[srcCells[first + i]]) * vcell;
    float pending = state[s] + (s ? add1 : add0);
    float f = 0.0f;
    if (cap > 1e-6f && pending > 0.0f) f = fmin(1.0f, pending / cap);
    state[s] = pending - f * cap;
    state[2 + s] += f * cap;
    state[4 + s] = f;
  }
}

/* the injection: C -> C + f (1 - C) inside the source sphere, f from
   inject_prepare */
__kernel void inject(__global const int* fluid, int n, __global const uchar* fl,
  __global float* c, float4 src0, float4 src1, __global const float* state)
{
  int g = get_global_id(0);
  if (g >= n) return;
  int id = fluid[g];
  int s1 = (fl[id] & SAC1) != 0;
  float4 src = s1 ? src1 : src0;
  float f = state[4 + s1];
  if (f <= 0.0f) return;
  float3 d = convert_float3(cellOf(id)) - src.xyz;
  if (dot(d, d) <= src.w * src.w) c[id] += f * (1.0f - c[id]);
}

/* the flux through each sac's cross-section k (between slices k-1 and
   k), one work-item per (sac, k), and the plug velocity that would make
   it q G[s,k]: corr[s,k] = (q G - flux) / (A dx^2) */
__kernel void plane_flux(__global const uchar* fl, __global const float4* v,
  __global const float* G, __global const int* A, float q, float dx2,
  __global float* corr, __global const float* Gi, float qi)
{
  int g = get_global_id(0);
  if (g >= 2 * (NZ + 1)) return;
  int s = g / (NZ + 1);
  int k = g - s * (NZ + 1);
  corr[g] = 0.0f;
  if (k < 1 || k >= NZ || A[g] == 0) return;
  float sum = 0.0f;
  int base = k * NXY;
  for (int j = 0; j < NY; j++)
    for (int i = 0; i < NX; i++)
    {
      int id = base + j * NX + i;
      uchar f = fl[id];
      if (!(f & FLUID) || !(fl[id - NXY] & FLUID)) continue;
      if (((f & SAC1) != 0) != (s == 1)) continue;
      sum += v[id].z;
    }
  corr[g] = (q * G[g] + qi * Gi[g] - sum * dx2) / (A[g] * dx2);
}

__kernel void plane_correct(__global const int* fluid, int n, __global const uchar* fl,
  __global float4* v, __global const float* corr)
{
  int g = get_global_id(0);
  if (g >= n) return;
  int id = fluid[g];
  if (!(fl[id - NXY] & FLUID)) return;
  int k = id / NXY;
  int s = (fl[id] & SAC1) != 0;
  v[id].z += corr[s * (NZ + 1) + k];
}
