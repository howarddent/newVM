
Mesh.MshFileVersion=1;

lc=0.1;

Point(1) = {0,0,0,lc};
Point(2) = {0.5,0,0,lc};
Point(3) = {0,0.5,0,lc};
Point(4) = {-0.5,0,0,lc};
Point(5) = {0,-0.5,0,lc};
Circle(1) = {2,1,3};
Circle(2) = {3,1,4};

Point(6) = {0,0,2,lc};
Point(7) = {0.5,0,2,lc};
Point(8) = {0,0.5,2,lc};
Point(9) = {-0.5,0,2,lc};
Point(10) = {0,-0.5,2,lc};
Circle(4) = {7,6,8};
Circle(5) = {8,6,9};
Line(6) = {9,4};
Line(7) = {3,8};
Line(8) = {7,2};

Line Loop(9) = {2,-6,-5,-7};
Ruled Surface(10) = {9};

Line Loop(11) = {8,1,7,-4};
Ruled Surface(12) = {11};

Physical Surface(13) = {10,12};
Recombine Surface {12,10};
