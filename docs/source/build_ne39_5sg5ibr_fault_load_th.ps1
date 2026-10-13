# Build the NE39 5SG+5IBR fault+load Thai report with xelatex (three passes for TOC).
# Thai typography mirrors the delivered NE39 160s Thai report build.
Set-Location "D:\4-year-project\GridFormLab\docs\source"
xelatex -interaction=nonstopmode -halt-on-error report_ne39_5sg5ibr_fault_load_th.tex
xelatex -interaction=nonstopmode -halt-on-error report_ne39_5sg5ibr_fault_load_th.tex
xelatex -interaction=nonstopmode -halt-on-error report_ne39_5sg5ibr_fault_load_th.tex
Get-Item report_ne39_5sg5ibr_fault_load_th.pdf | Select-Object Name,Length,LastWriteTime
