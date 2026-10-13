# Build the NE39 160s reclose English report with xelatex (three passes for TOC).
# Style/fonts mirror the IEEE14 report build in this directory.
Set-Location "D:\4-year-project\GridFormLab\docs\source"
xelatex -interaction=nonstopmode -halt-on-error report_ne39_160s_reclose_en.tex
xelatex -interaction=nonstopmode -halt-on-error report_ne39_160s_reclose_en.tex
xelatex -interaction=nonstopmode -halt-on-error report_ne39_160s_reclose_en.tex
Get-Item report_ne39_160s_reclose_en.pdf | Select-Object Name,Length,LastWriteTime
