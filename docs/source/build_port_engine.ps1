# Build the port-engine optimization English report with xelatex (three
# passes for TOC).  Style/fonts mirror the delivered NE39 report builds in
# this directory.
Set-Location "D:\4-year-project\GridFormLab\docs\source"
xelatex -interaction=nonstopmode -halt-on-error report_port_engine_en.tex
xelatex -interaction=nonstopmode -halt-on-error report_port_engine_en.tex
xelatex -interaction=nonstopmode -halt-on-error report_port_engine_en.tex
Get-Item report_port_engine_en.pdf | Select-Object Name,Length,LastWriteTime
