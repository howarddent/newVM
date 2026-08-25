
Mesh.MshFileVersion=1;

lc = 0.1;

// Rectangle
/*
a = 8;
b = 6;

Point(1) = {-a*0.5,-b*0.5,0,lc};
Point(2) = {+a*0.5,-b*0.5,0,lc};
Point(3) = {+a*0.5,+b*0.5,0,lc};
Point(4) = {-a*0.5,+b*0.5,0,lc};

Line(1) = {1,2};
Line(2) = {2,3};
Line(3) = {3,4};
Line(4) = {4,1};
Line Loop(5) = {1,2,3,4};
Plane Surface(6) = {5};
Physical Surface(7) = {6};
*/

// Circle
r = 3;

Point(1) = {0,0,0,lc};
Point(2) = {r,0,0,lc};
Point(3) = {0,r,0,lc};
Point(4) = {-r,0,0,lc};
Point(5) = {0,-r,0,lc};

Circle(1) = {2,1,3};
Circle(2) = {3,1,4};
Circle(3) = {4,1,5};
Circle(4) = {5,1,2};

Line Loop(5) = {2,3,4,1};
Plane Surface(6) = {5};
Physical Surface(7) = {6};
