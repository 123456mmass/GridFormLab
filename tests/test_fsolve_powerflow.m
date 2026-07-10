function tests = test_fsolve_powerflow()
tests=functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function test_fsolve_matches_project_newton_solver(testCase)
c=cases.kundur_ex126_book_case();
opt=struct('verbose',false,'plot_results',false,'tolerance',1e-10);
nr=pfsolver.powerflow_newton_raphson(c,struct('verbose',false, ...
    'plot_results',false,'tolerance',1e-10,'enforce_q_limits',false));
fs=pfsolver.powerflow_fsolve(c,opt);
verifyTrue(testCase,fs.converged);
verifyLessThan(testCase,fs.fsolve.residual_inf,1e-10);
verifyEqual(testCase,fs.bus_voltage,nr.bus_voltage,'AbsTol',1e-10);
verifyEqual(testCase,fs.bus_angle_deg,nr.bus_angle_deg,'AbsTol',1e-9);
end

function test_path_bootstrap_repairs_removed_internal_path(testCase)
root=fileparts(fileparts(mfilename('fullpath')));
internal=fullfile(root,'internal');
old=path;
cleanup=onCleanup(@() path(old)); %#ok<NASGU>
rmpath(genpath(internal));
verifyEmpty(testCase,which('pf_get_option'));
pf_init_paths();
verifyNotEmpty(testCase,which('pf_get_option'));
end
