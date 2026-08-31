# Remove zebra row colors from all tables.
p = 'report_power_system_project_final_th.tex'
s = open(p, encoding='utf-8').read()
old = '\\rowcolors{2}{tablerow}{white}\n'
n = s.count(old)
s = s.replace(old, '')
open(p, 'w', encoding='utf-8', newline='\n').write(s)
print('rowcolors removed:', n)
