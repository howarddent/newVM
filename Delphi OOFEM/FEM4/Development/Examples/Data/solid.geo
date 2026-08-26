
Mesh.MshFileVersion=1;

lc=0.06;

Point(1) = {0,0,0,lc};
Point(2) = {+0.2,0,0,lc};
Point(3) = {0,0.2,0,lc};
Point(4) = {-0.2,0,0,lc};
Point(5) = {0,-0.2,0,lc};

Circle(1) = {2,1,5};
Circle(2) = {5,1,4};
Circle(3) = {4,1,3};
Circle(4) = {3,1,2};

Line Loop(5) = {4,1,2,3};
Plane Surface(6) = {5};

ext() = Extrude {0,0,2} { Surface{6}; };
Physical Volume(31) = {ext(1)};

