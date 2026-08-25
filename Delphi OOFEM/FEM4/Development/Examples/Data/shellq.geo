Mesh.MshFileVersion=1;

lc=0.1;

Point(1) = {0,0,0,lc};
Point(2) = {0.5,0,0,lc};
Point(3) = {0,0.5,0,lc};
Point(4) = {-0.5,0,0,lc};
Point(5) = {0,-0.5,0,lc};
Circle(1) = {2,1,3};
Circle(2) = {3,1,4};

Extrude {0,0,2} {
  Line{1,2};
}
Transfinite Surface {6} = {6,8,3,2};
Transfinite Surface {10} = {4,3,8,11};
Recombine Surface {10,6};
Physical Surface(11) = {6,10};
