# Build the NE39 5SG+5IBR fault+load English report with xelatex (three passes for TOC).
# Style/fonts mirror the delivered NE39 160s report build in this directory.
Set-Location "D:\4-year-project\GridFormLab\docs\source"
xelatex -interaction=nonstopmode -halt-on-error report_ne39_5sg5ibr_fault_load_en.tex
xelatex -interaction=nonstopmode -halt-on-error report_ne39_5sg5ibr_fault_load_en.tex
xelatex -interaction=nonstopmode -halt-on-error report_ne39_5sg5ibr_fault_load_en.tex
Get-Item report_ne39_5sg5ibr_fault_load_en.pdf | Select-Object Name,Length,LastWriteTime
