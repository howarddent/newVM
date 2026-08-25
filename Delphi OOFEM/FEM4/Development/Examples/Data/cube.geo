
Mesh.MshFileVersion=1;

lc = 0.1;

L = 1;

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

// Hexas
/*
Transfinite Surface {6} = {1,2,3,4};
Recombine Surface {6};

Extrude Surface { 6, {0,0,L} } {
  Layers { {10}, {1}};
  Recombine;
};
*/

// Tetras
ext() = Extrude {0,0,L} { Surface{6}; };

Physical Volume(29) = {ext(1)};

