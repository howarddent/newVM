
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

Transfinite Surface {6} = {1,2,3,4};
Recombine Surface {6};

ext() = Extrude { {1,0,0}, {0,2,0}, Pi/2 } {
  Surface{6}; Layers { {20}, {1}}; Recombine;
};

Physical Volume(29) = {ext(1)};

