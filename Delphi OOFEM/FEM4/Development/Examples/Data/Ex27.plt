set title 'Temperature'
set xlabel 'x(m)'
set ylabel 'Temperature (C)'
plot 'T_FEM_CutGrid.txt' using 2:4 title 'FEM' with lines, 'T_strand7_data.txt' using 2:3 title 'Strand7' with lines
pause -1