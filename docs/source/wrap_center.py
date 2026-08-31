# Wrap every table float body in a center environment (deterministic centering).
p = 'report_power_system_project_final_th.tex'
s = open(p, encoding='utf-8').read()

a = '\\begin{table}[H]\n\\centering\\tablefont\n'
b = '\\begin{table}[H]\n\\begin{center}\n\\tablefont\n'
n1 = s.count(a)
s = s.replace(a, b)

a2 = '\\end{tabularx}\n\\end{table}'
b2 = '\\end{tabularx}\n\\end{center}\n\\end{table}'
n2 = s.count(a2)
s = s.replace(a2, b2)

a3 = '\\end{tabular}\n\\end{table}'
b3 = '\\end{tabular}\n\\end{center}\n\\end{table}'
n3 = s.count(a3)
s = s.replace(a3, b3)

open(p, 'w', encoding='utf-8', newline='\n').write(s)
print('openers:', n1, 'tabularx closers:', n2, 'tabular closers:', n3)
