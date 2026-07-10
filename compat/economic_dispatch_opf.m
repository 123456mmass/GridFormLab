function results = economic_dispatch_opf(case_data, options)
pf_init_paths();
if nargin < 1
    case_data = [];
end
if nargin < 2
    options = struct();
end
results = pfsolver.economic_dispatch_opf(case_data, options);
end
