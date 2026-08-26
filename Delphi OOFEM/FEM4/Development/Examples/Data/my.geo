// Gmsh project created on Tue Feb 09 12:57:54 2016
Point(1) = {0.2, -0, -0.3, 1.0};
Point(2) = {0, -1.1, -0.9, 1.0};
Point(3) = {0.1, -0.9, -0.8, 1.0};
Point(4) = {0.2, -0.6, -0.7, 1.0};
Point(5) = {0.3, -0.4, -0.8, 1.0};
Circle(1) = {2, 3, 4};
Extrude {0, 0, 1} {
  Line{1};
}
