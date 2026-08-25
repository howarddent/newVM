Mesh.MshFileVersion=1;
ch_length = 0.2;

p1 = newp; Point(p1) = {0, 0, 0, ch_length} ;
p2 = newp; Point(p2) = {2, 0, 0, ch_length} ;
p3 = newp; Point(p3) = {2, 2, 0, ch_length} ;
p4 = newp; Point(p4) = {0, 2, 0, ch_length} ;
p5 = newp; Point(p5) = {0.5, 0.5, 0, ch_length*0.1} ;

l1 = newl; Line(l1) = {p1, p2} ;
l2 = newl; Line(l2) = {p2, p3} ;
l3 = newl; Line(l3) = {p3, p4} ;
l4 = newl; Line(l4) = {p4, p1} ;

ll1 = newll; Line Loop (ll1) = {l1, l2, l3, l4} ;
s1 = news; Plane Surface (s1) = {ll1} ;

Point{p5} In Surface{s1} ;
Recombine Surface {7};