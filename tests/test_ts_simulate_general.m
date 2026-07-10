function tests = test_ts_simulate_general()
%TEST_TS_SIMULATE_GENERAL Guardrails for the general transient engine.
%   Verifies that stability.ts_simulate runs ANY case in +cases/ (MATPOWER or
%   Kundur format) with no engine edit, and that case14 reproduces the
%   validated case14_ts_classical result (independently cross-checked vs PSAT).

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function test_kundur_flux6_via_general_engine(testCase)
    % The parameter-driven GENTPJ model must run through the same
    % transient-simulation entry point as classical cases.
    case_data = cases.kundur_ex126_book_case();
    ssa = stability.multicase_sssa(case_data);
    testCase.verifyEqual(numel(ssa.eigenvalues),24);
    testCase.verifyTrue(all(isfinite(ssa.eigenvalues)));
    testCase.verifyLessThan(norm([ssa.debug_residual_f;ssa.debug_residual_g],inf),1e-8);

    opt = struct('model','flux6','t_end',0.7,'dt',1e-3,'fault_bus',8, ...
        't_fault',0.5,'t_clear',0.6,'Zf',[],'method','trapezoidal', ...
        'corrector_mode','fixed','corrector_iter',1,'verbose',false);
    r = stability.ts_simulate(case_data, opt);
    testCase.verifyEqual(r.model, '6th-order GENTPJ full nonlinear');
    testCase.verifyEqual(numel(r.gen_buses), 4);
    testCase.verifySize(r.delta,[numel(r.t),4]);
    testCase.verifySize(r.omega,size(r.delta));
    testCase.verifySize(r.Pgen,size(r.delta));
    testCase.verifySize(r.Vbus,[numel(r.t),size(case_data.bus_data,1)]);
    testCase.verifyTrue(all(isfinite(r.delta),'all'));
    testCase.verifyTrue(all(isfinite(r.omega),'all'));
    testCase.verifyTrue(all(isfinite(r.Pgen),'all'));
    testCase.verifyTrue(all(isfinite(r.Vbus),'all'));

    % The public standalone wrapper must remain numerically compatible.
    r0 = stability.kundur_fault_simulation_6th_order(struct('bus',8,'tclear',0.1, ...
        'tmax',0.7,'dt',1e-3,'tfault_start',0.5,'method','trapezoidal','corrector_iter',1));
    testCase.verifyLessThan(max(abs(rad2deg(r.delta-r0.delta)),[],'all'), 1e-6);
    testCase.verifyLessThan(max(abs(r.omega-r0.omega),[],'all'), 1e-10);
end

function test_case14_matches_validated_engine(testCase)
    % With adaptive corrector and event-aware grid, the general engine uses
    % a different (corrected) event handling than the old case14 engine.
    % The old engine averaged trapezoidal RHS across topology changes.
    % The new engine does not. Both use ci=10 for fair comparison.
    opt = struct('t_end',4,'dt',0.01,'fault_bus',4,'t_fault',1.0,'t_clear',1.1, ...
        'Zf',1i*0.1,'pm_mode','pgaz','corrector_mode','fixed','corrector_iter',10,'verbose',false);
    r_gen = stability.ts_simulate(cases.case_matpower6_case14(), opt);
    r_old = stability.case14_ts_classical(opt);
    testCase.verifyTrue(r_gen.pf.converged);
    % With corrected event handling, trajectories differ slightly at fault.
    testCase.verifyLessThan(max(abs(rad2deg(r_gen.delta - r_old.delta)),[],'all'), 2.0, ...
        'General engine differs from old engine due to event handling fix.');
    % But no-fault equilibrium must be exactly zero for both
    opt_nf = opt; opt_nf.t_fault = 99; opt_nf.t_clear = 99.1;
    r_gen_nf = stability.ts_simulate(cases.case_matpower6_case14(), opt_nf);
    testCase.verifyLessThan(max(abs(rad2deg(r_gen_nf.delta(end,:) - r_gen_nf.delta(1,:)))), 1e-10, ...
        'No-fault drift must be zero.');
end

function test_case9_new_case_runs(testCase)
    % A case never used to build the engine: proves "add a case and it runs".
    opt = struct('t_end',4,'dt',0.01,'fault_bus',7,'t_fault',1.0,'t_clear',1.1, ...
        'Zf',1i*0.1,'pm_mode','pfpg','verbose',false);
    r = stability.ts_simulate(cases.case_matpower6_case9(), opt);
    testCase.verifyTrue(r.pf.converged);
    testCase.verifyEqual(numel(r.gen_buses), 3);
    % Stable: bounded inter-machine angles, speed returns near nominal.
    H = r.H(:).'; dcoi = sum(H.*r.delta,2)/sum(H); drel = r.delta - dcoi;
    testCase.verifyLessThan(max((max(drel)-min(drel))*180/pi), 360);
    testCase.verifyLessThan(max(abs(r.omega(end,:)-1)), 0.1);
end

function test_kundur_runs_with_base_conversion(testCase)
    opt = struct('t_end',4,'dt',0.01,'fault_bus',8,'t_fault',0.5,'t_clear',0.6, ...
        'Zf',1i*0.1,'pm_mode','pfpg','corrector_mode','adaptive','verbose',false);
    r = stability.ts_simulate(cases.case_kundur_two_area_classical(), opt);
    testCase.verifyTrue(r.pf.converged);
    testCase.verifyEqual(numel(r.gen_buses), 4);
    % Machine base 900 MVA -> system 100 MVA: H_sys = H_mach*9, Xdp_sys = 0.3/9.
    testCase.verifyEqual(r.H, [58.5; 58.5; 55.575; 55.575], 'AbsTol', 1e-3);
    testCase.verifyLessThan(max(abs(r.Xdp - 0.3/9)), 1e-6);
    % Pe0 must match the Kundur operating point (system pu).
    testCase.verifyLessThan(max(abs(r.Pe_pu(1,:) - [7.0 7.0 7.2 7.0])), 0.05);
    % Stable.
    H = r.H(:).'; dcoi = sum(H.*r.delta,2)/sum(H); drel = r.delta - dcoi;
    testCase.verifyLessThan(max((max(drel)-min(drel))*180/pi), 360);
end

function test_adaptive_corrector_converges(testCase)
    % Adaptive corrector must converge all steps with small residual.
    c = cases.case_ieee_rts24_pgaz();
    opt = struct('t_end',5,'dt',0.01,'fault_bus',15,'t_fault',1.0,'t_clear',1.1, ...
        'Zf',0+0.1j,'method','trapezoidal','corrector_mode','adaptive', ...
        'corrector_abs_tol',1e-10,'corrector_rel_tol',1e-8, ...
        'max_corrector_iter',10,'verbose',false);
    r = stability.ts_simulate(c, opt);
    testCase.verifyEqual(r.nonconverged_step_count, 0, 'All steps must converge.');
    testCase.verifyLessThan(r.max_corrector_residual, 1e-6, 'Max residual must be small.');
    testCase.verifyLessThanOrEqual(r.max_corrector_iterations_used, 10);
    testCase.verifyEqual(numel(r.corrector_iterations), numel(r.t)-1);
    testCase.verifyEqual(numel(r.corrector_residual), numel(r.t)-1);
    testCase.verifyEqual(numel(r.corrector_converged), numel(r.t)-1);
end

function test_fixed_ci1_higher_residual_than_adaptive(testCase)
    % Fixed ci=1 must have higher trapezoidal residual than adaptive.
    c = cases.case_ieee_rts24_pgaz();
    opt_fixed = struct('t_end',5,'dt',0.01,'fault_bus',15,'t_fault',1.0,'t_clear',1.1, ...
        'Zf',0+0.1j,'method','trapezoidal', ...
        'corrector_mode','fixed','corrector_iter',1,'verbose',false);
    opt_adaptive = struct('t_end',5,'dt',0.01,'fault_bus',15,'t_fault',1.0,'t_clear',1.1, ...
        'Zf',0+0.1j,'method','trapezoidal', ...
        'corrector_mode','adaptive','max_corrector_iter',10,'verbose',false);
    r_fixed = stability.ts_simulate(c, opt_fixed);
    r_adaptive = stability.ts_simulate(c, opt_adaptive);
    testCase.verifyGreaterThan(r_fixed.max_corrector_residual, r_adaptive.max_corrector_residual * 100, ...
        'Fixed ci=1 residual must be >100x adaptive residual.');
end

function test_adaptive_close_to_fixed_ci10(testCase)
    % Adaptive result must be close to fixed ci=10 (both converged).
    c = cases.case_ieee_rts24_pgaz();
    opt_adaptive = struct('t_end',5,'dt',0.01,'fault_bus',15,'t_fault',1.0,'t_clear',1.1, ...
        'Zf',0+0.1j,'method','trapezoidal', ...
        'corrector_mode','adaptive','max_corrector_iter',10,'verbose',false);
    opt_fixed10 = struct('t_end',5,'dt',0.01,'fault_bus',15,'t_fault',1.0,'t_clear',1.1, ...
        'Zf',0+0.1j,'method','trapezoidal', ...
        'corrector_mode','fixed','corrector_iter',10,'verbose',false);
    r_adaptive = stability.ts_simulate(c, opt_adaptive);
    r_fixed10 = stability.ts_simulate(c, opt_fixed10);
    testCase.verifyLessThan(max(abs(rad2deg(r_adaptive.delta - r_fixed10.delta)),[],'all'), 0.01, ...
        'Adaptive and fixed ci=10 must produce nearly identical trajectories.');
end

function test_event_grid_exact(testCase)
    % Time grid must have t_fault and t_clear as exact grid points.
    c = cases.case_ieee_rts24_pgaz();
    opt = struct('t_end',5,'dt',0.01,'fault_bus',15,'t_fault',1.0,'t_clear',1.1, ...
        'Zf',0+0.1j,'method','trapezoidal','corrector_mode','adaptive','verbose',false);
    r = stability.ts_simulate(c, opt);
    min_tf = min(abs(r.t - opt.t_fault));
    testCase.verifyLessThan(min_tf, 1e-14, 't_fault must be on grid.');
    min_tc = min(abs(r.t - opt.t_clear));
    testCase.verifyLessThan(min_tc, 1e-14, 't_clear must be on grid.');
    testCase.verifyEqual(numel(r.event_idx), 2, 'Two event times must be recorded.');
end

function test_no_trapezoidal_step_across_topology(testCase)
    % No trapezoidal step must average RHS from two different topologies.
    c = cases.case_ieee_rts24_pgaz();
    opt = struct('t_end',3,'dt',0.01,'fault_bus',15,'t_fault',1.0,'t_clear',1.1, ...
        'Zf',0+0.1j,'method','trapezoidal','corrector_mode','adaptive','verbose',false);
    r = stability.ts_simulate(c, opt);
    fb_idx = find(r.pf.external_bus_ids == 15, 1);
    tf_idx = find(abs(r.t - 1.0) < 1e-14, 1);
    V_before = r.Vbus(tf_idx-1, fb_idx);
    V_at_fault = r.Vbus(tf_idx, fb_idx);
    testCase.verifyLessThan(V_at_fault, V_before * 0.95, ...
        'Voltage must drop at fault application.');
end

function test_no_fault_equilibrium_adaptive(testCase)
    % With no fault, the system must stay at equilibrium (zero drift).
    c = cases.case_ieee_rts24_pgaz();
    opt = struct('t_end',2,'dt',0.01,'fault_bus',15,'t_fault',99,'t_clear',99.1, ...
        'Zf',0+0.1j,'method','trapezoidal','corrector_mode','adaptive','verbose',false);
    r = stability.ts_simulate(c, opt);
    testCase.verifyLessThan(max(abs(r.delta(end,:) - r.delta(1,:))), 1e-10, ...
        'No-fault delta drift must be zero.');
    testCase.verifyLessThan(max(abs(r.omega(end,:) - 1)), 1e-10, ...
        'No-fault omega drift must be zero.');
end

function test_corrector_diagnostics_size(testCase)
    % Corrector diagnostics must have nt-1 entries.
    c = cases.case_ieee_rts24_pgaz();
    opt = struct('t_end',0.5,'dt',0.01,'fault_bus',15,'t_fault',99,'t_clear',99.1, ...
        'Zf',0+0.1j,'method','trapezoidal','corrector_mode','adaptive','verbose',false);
    r = stability.ts_simulate(c, opt);
    nt = numel(r.t);
    testCase.verifyEqual(numel(r.corrector_iterations), nt-1);
    testCase.verifyEqual(numel(r.corrector_residual), nt-1);
    testCase.verifyEqual(numel(r.corrector_update_norm), nt-1);
    testCase.verifyEqual(numel(r.corrector_converged), nt-1);
    testCase.verifyEqual(numel(r.event_side), nt);
end
