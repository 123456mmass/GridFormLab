# Build the flagship C++-vs-MATLAB report with xelatex (three passes for
# TOC/references).  Style/fonts mirror the other English report builds in
# this directory.  Note: cppdata/ slot files and figures/flagship_cpp/
# figures are placeholder stubs until the C++ slot-filler generator lands
# its real outputs; this script builds whatever is on disk.
Set-Location "D:\4-year-project\GridFormLab\docs\source"
xelatex -interaction=nonstopmode -halt-on-error report_flagship_cpp_en.tex
xelatex -interaction=nonstopmode -halt-on-error report_flagship_cpp_en.tex
xelatex -interaction=nonstopmode -halt-on-error report_flagship_cpp_en.tex
Get-Item report_flagship_cpp_en.pdf | Select-Object Name,Length,LastWriteTime
