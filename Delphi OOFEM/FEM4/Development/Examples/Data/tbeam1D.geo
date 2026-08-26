Mesh.MshFileVersion=1;
cl = 0.049;
dx = 1;
Point(1) = {0,0,0,cl};
Point(2) = {dx,0,0,cl};
Line(1) = {1,2};
Physical Line(2) = {1};
