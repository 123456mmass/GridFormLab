function tests=test_all_network_analyses()
% Every catalogued power_case must support PF, classical SSSA and TS.
tests=functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function test_catalog_contract(testCase)
cat=cases.network_case_catalog();
verifyEqual(testCase,numel(unique({cat.id})),numel(cat));
for k=1:numel(cat)
    c=cat(k).loader();
    verifyEqual(testCase,c.schema_version,'power_case/1.0',cat(k).id);
    verifyEqual(testCase,c.case_kind,'network',cat(k).id);
    verifyTrue(testCase,isfield(c,'mpc'),cat(k).id);
end
end

function test_every_network_case_runs_pf(testCase)
cat=cases.network_case_catalog();
for k=1:numel(cat)
    c=cat(k).loader();
    r=pfsolver.powerflow_newton_raphson(c,struct('verbose',false, ...
        'plot_results',false,'enforce_q_limits',false, ...
        'max_iter',50,'tolerance',1e-10));
    verifyTrue(testCase,r.converged,sprintf('%s PF',cat(k).id));
    verifyLessThan(testCase,r.mismatch_history(end),1e-8,cat(k).id);
end
end

function test_every_network_case_runs_classical_sssa(testCase)
cat=cases.network_case_catalog();
for k=1:numel(cat)
    c=cat(k).loader();
    r=stability.multicase_sssa(c,struct('model','classical'));
    verifyEqual(testCase,numel(r.state_names),size(r.Afull,1),cat(k).id);
    verifyTrue(testCase,all(isfinite(r.eigenvalues)),cat(k).id);
    verifyTrue(testCase,isfield(r,'stability_status'),cat(k).id);
    names=string(r.state_names);
    verifyTrue(testCase,all(contains(names,"delta_",'IgnoreCase',true) | ...
        contains(names,"omega_",'IgnoreCase',true)),cat(k).id);
end
end

function test_every_network_case_runs_ts_smoke(testCase)
cat=cases.network_case_catalog();
for k=1:numel(cat)
    c=cat(k).loader();
    opt=struct('model','classical','t_end',0.02,'dt',0.01, ...
        'fault_bus',cat(k).ts_options.fault_bus, ...
        't_fault',99,'t_clear',99.1,'Zf',1i*0.1, ...
        'method','trapezoidal','corrector_mode','adaptive','verbose',false);
    r=stability.ts_simulate(c,opt);
    verifyEqual(testCase,numel(r.t),3,cat(k).id);
    verifyTrue(testCase,all(isfinite(r.delta),'all'),cat(k).id);
    verifyTrue(testCase,all(isfinite(r.omega),'all'),cat(k).id);
end
end

function test_rts24_sssa_states_and_status(testCase)
r=solve_case('analysis','sssa','case','rts24');
verifyEqual(testCase,numel(r.state_names),22);
verifyEqual(testCase,numel(r.reduced_eigenvalues),20);
verifyEqual(testCase,r.stability_status,'MARGINAL');
txt=fileread(r.launcher.log_file);
verifyNotEmpty(testCase,strfind(txt,'STATE INVENTORY')); %#ok<STRIFCND>
verifyNotEmpty(testCase,strfind(txt,'delta_G1@Bus1')); %#ok<STRIFCND>
verifyNotEmpty(testCase,strfind(txt,'Stability status: MARGINAL')); %#ok<STRIFCND>
end
