
Mesh.MshFileVersion=1;

lc = 1;

Point(1)={0,0,0,lc};
Point(2)={0,-3,0,lc};
Point(3)={0,-25,0,lc};
Point(4)={30,-25,0,lc};
Point(5)={30,0,0,lc};
Point(6)={12,0,0,lc};
Point(7)={12,-8,0,lc};
Point(8)={11,-8,0,lc};
Point(9)={11,-3,0,lc};
Point(10) = {0,-8,0,lc};
Point(11) = {30,-8,0,lc};
Point(12) = {11,-25,0,lc};
Point(13) = {12,-25,0,lc};

Line(1) = {2,10};
Line(2) = {10,8};
Line(3) = {8,9};
Line(4) = {9,2};
Line(5) = {8,12};
Line(6) = {12,3};
Line(7) = {3,10};
Line(8) = {8,7};
Line(9) = {7,13};
Line(10) = {13,12};
Line(11) = {7,6};
Line(12) = {6,5};
Line(13) = {5,11};
Line(14) = {11,7};
Line(15) = {11,4};
Line(16) = {4,13};
Line Loop(17) = {13,14,11,12};
Plane Surface(18) = {17};
Line Loop(19) = {3,4,1,2};
Plane Surface(20) = {19};
Line Loop(21) = {5,6,7,2};
Plane Surface(22) = {21};
Line Loop(23) = {9,10,-5,8};
Plane Surface(24) = {23};
Line Loop(25) = {16,-9,-14,15};
Plane Surface(26) = {25};

Transfinite Surface {18} = {7,6,5,11};
Transfinite Surface {20} = {10,2,9,8};
Transfinite Surface {22} = {3,10,8,12};
Transfinite Surface {24} = {12,8,7,13};
Transfinite Surface {26} = {13,7,11,4};
Recombine Surface {18,26,22,24,20};
Physical Surface(27) = {18,26,24,22,20};
