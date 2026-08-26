
Mesh.MshFileVersion=1;

mm=0.001; //Millimeter
radius_core=0.5*mm;
radius_eps=2.*mm;
radius_hull=2.5*mm;

meshfactor=2;  //0.5 for finer mesh

mcentral=radius_core/30.*meshfactor;
m_core=radius_core/25.*meshfactor;
m_eps=radius_eps/30.*meshfactor;
m_hull=radius_hull/30.*meshfactor;

//Phsical names
FACE_CORE=10000;
FACE_EPS=10002;
FACE_HULL=10003;
LINE_OUTER=10004;


Point(1000)= {0,0,0, mcentral};
Point(1001)= {-radius_core,0,0, m_core};
Point(1002)= {radius_core,0,0, m_core};

Point(2001)= {-radius_eps,0,0, m_eps};
Point(2002)= {radius_eps,0,0, m_eps};

Point(3001)= {-radius_hull,0,0, m_hull};
Point(3002)= {radius_hull,0,0, m_hull};


Circle(111) = {1001,1000,1002};
Circle(112) = {1002,1000,1001};
Circle(121) = {2001,1000,2002};
Circle(122) = {2002,1000,2001};
Circle(131) = {3001,1000,3002};
Circle(132) = {3002,1000,3001};

Line Loop(211) = {111,112};
Line Loop(221) = {121,122};
Line Loop(231) = {131,132};

Plane Surface(301) = {211};
Plane Surface(302) = {221,211};
Plane Surface(303) = {231,221};

//Physical Surface (FACE_CORE)={301};
Physical Surface (FACE_EPS) ={302};
Physical Surface (FACE_HULL)={303};

//Physical Line (LINE_OUTER)={131,132};