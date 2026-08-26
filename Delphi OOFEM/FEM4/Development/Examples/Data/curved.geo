Mesh.MshFileVersion=1;

lc = 0.1;

Point(1) = {0,0,0,lc};
Point(2) = {1,0,0,lc};
Point(3) = {2,0,0,lc};
Point(4) = {0,2,0,lc};
Point(5) = {0,1,0,lc};

Circle(1) = {2,1,5};
Circle(2) = {3,1,4};
Line(3) = {4,5};
Line(4) = {2,3};
Line Loop(5) = {2,3,-1,4};
Plane Surface(6) = {5};

Physical Surface(7) = {6};
