function case_data = case_saadat_opf_example_7_5()
%CASE_SAADAT_OPF_EXAMPLE_7_5 Saadat dispatch-program benchmark.
%   Uses the same three-generator data as Example 7.4 and verifies the
%   textbook dispatch-program output. Reference: Hadi Saadat, Chapter 7,
%   Example 7.5, printed pages 275-276.

case_data = cases.case_saadat_opf_example_7_4();
case_data.system_name = 'Saadat Example 7.5 - Dispatch Program No Limits';
case_data.reference = struct( ...
    'source', 'Power System Analysis, Hadi Saadat, Chapter 7, Example 7.5', ...
    'pdf_file', 'power system analysis - hadi saadat_320503100.pdf', ...
    'printed_pages', '275-276');
end
