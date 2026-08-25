Mesh.MshFileVersion=1;

lc = 0.1;
L = 1;

// NOTE: this file was reconstructed. The original used the legacy
// "Extrude Surface {...}" statement form (and a second geometry glued on
// via hand-computed Surface Loop/Volume tag numbers assumed to result from
// it), which modern Gmsh (4.x) no longer parses at all - it's a hard
// syntax error, not just a typo, so the volume it tried to build never
// actually existed and meshing silently produced zero usable elements.
// Rewritten below with the same intent - a single connected mesh exercising
// every element type CXS.FEMLAP.Gmsh's element-type dispatch understands
// (BEAM/TRI-or-QUAD/TETRA/HEXA) - using modern Extrude syntax throughout.

// Hex block: X:[0,1], Y:[0,1], Z:[0,1]
Point(1) = {0,0,0,lc};
Point(2) = {L,0,0,lc};
Point(3) = {L,L,0,lc};
Point(4) = {0,L,0,lc};

Line(1) = {1,2};
Line(2) = {2,3};
Line(3) = {3,4};
Line(4) = {4,1};

Line Loop(5) = {1,2,3,4};
Plane Surface(6) = {5};

Transfinite Surface {6} = {1,2,3,4};
Recombine Surface {6};

hex() = Extrude {0,0,L} { Surface{6}; Layers{{10},{1}}; Recombine; };
// hex(0) = top surface (Z=1, quads), hex(1) = hex volume, hex(2..5) = the
// 4 side surfaces (in curve 1..4 order) - hex(5) is the side swept from
// Line(4)={4,1}, i.e. the X=0 face.

Physical Volume(90) = {hex(1)};
Physical Surface(91) = {hex(0)};

// Tetra block glued onto the hex block's X=0 face (shares that face's
// nodes exactly, so the two regions are mesh-conformal at the interface -
// Gmsh automatically bridges the quad/tri mismatch there with a thin layer
// of pyramid elements, which CXS.FEMLAP.Gmsh's dispatch simply doesn't
// have a case for and skips, same as it would for any other unhandled
// element type).
tet() = Extrude {-L,0,0} { Surface{hex(5)}; };
Physical Volume(92) = {tet(1)};

// Beam "spider": a couple of explicit 1D elements from a point in free
// space down to existing corners, so GMSH_BEAM is exercised too.
Point(50) = {0.5,0.5,1.5,lc};
Line(101) = {50,3};
Line(102) = {50,4};
Physical Line(103) = {101,102};
