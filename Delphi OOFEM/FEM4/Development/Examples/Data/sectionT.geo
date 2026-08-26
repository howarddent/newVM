Mesh.MshFileVersion=1;

lc = 0.02;

Point(1) = {0, 0, 0, lc};
Point(2) = {1, 0.6, 0, lc};
Point(3) = {1, 0.3, 0, lc};
Point(4) = {0.4, 0.2, 0, lc};
Point(5) = {0.3, -0.6, 0, lc};
Point(6) = {0, 0.6, 0, lc};
Point(7) = {-0, -0.6, 0, lc};
Point(8) = {0.2, -0, 0, lc};
Point(9) = {0, 0.2, 0, lc};
Point(10) = {0, -0.2, 0, lc};

Line(1) = {7, 5};
Line(2) = {5, 4};
Line(3) = {4, 3};
Line(4) = {3, 2};
Line(5) = {2, 6};
Line(6) = {6, 9};
Line(7) = {10, 7};

Circle(8) = {9, 1, 8};
Circle(9) = {8, 1, 10};

Line Loop(10) = {2, 3, 4, 5, 6, 8, 9, 7, 1};
Plane Surface(11) = {10};

Symmetry {1, 0, 0, 0} {
  Duplicata { Surface{11}; }
}

//Recombine Surface {12, 11};

Physical Surface(22) = {12, 11};
Physical Line(23) = {13, 14, 15, 16, 5, 4, 3, 2, 1, 21};
