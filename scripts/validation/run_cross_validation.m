function run_cross_validation()
%RUN_CROSS_VALIDATION  Fresh three-way (Ours + PSAT + PGAz) cross-validation for
%   case14 and RTS-24. All tools run FRESH this session (no saved .mat). PGAz
%   is mandatory for the gate; PSAT/PGAz are reference tools only (never
%   production deps). Reports per-case pairwise metrics and gate statuses.

pf_init_paths;
fprintf('\n##########################################################\n');
fprintf('# CROSS-VALIDATION SUMMARY (FRESH three-way, this session)#\n');
fprintf('##########################################################\n');

o14 = run_three_way_validation('case_matpower6_case14');
o24 = run_three_way_validation('case_ieee_rts24_pgaz', struct('fault_bus',15));

fprintf('\n################ AGGREGATE GATES ################\n');
fprintf('Case14  ALL_GATES_PASS = %s\n', gate(o14.gates.all_gates_pass));
fprintf('RTS-24  ALL_GATES_PASS = %s\n', gate(o24.gates.all_gates_pass));
fprintf('#################################################\n');
end

function s = gate(c), if c, s='PASS'; else, s='FAIL'; end, end
