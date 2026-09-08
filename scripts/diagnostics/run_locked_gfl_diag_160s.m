function out = run_locked_gfl_diag_160s(varargin)
%RUN_LOCKED_GFL_DIAG_160S  Fixed-GFL comparison arm for the 160 s full cycle.
%
% The comparison figure the owner asked for needs TWO trajectories on ONE
% schedule: the delivered adaptive switching policy, and the same case with every
% converter locked grid-following. This script produces the second one on the
% 160 s schedule of scenario sg_fault_cycle160
% (scripts/reporting/run_ieee14_scenario_suite.m rows(5)):
%
%     sg_trip 20 -> fault_on 60 -> fault_clear 60.15 -> sg_on 100 -> 160 s
%
% The oscillation the figure shows is SIMULATED, not drawn: with the machine gone
% and all four converters locked grid-following, the island has no voltage-forming
% source, every PLL is chasing a voltage that only the PLLs themselves produce, and
% the trajectory swings hard. Nothing is added to the data to make it swing.
%
% WHY THE PRODUCTION RUN CANNOT PRODUCE THIS. The delivered locked_gfl arm
% (run_ieee14_gfm_lock_comparison.m arms(5)) FAILS CLOSED at the SG trip with
% noVoltageFormingSource: per_island_vf_check refuses an energised island holding
% no SG and no GFM. That refusal is the production contract and is untouched here.
% This script re-runs the same arm with three opt-in diagnostic settings, each
% copied verbatim from the delivered 250 s diagnostic
% (scripts/diagnostics/run_locked_gfl_diag_250s.m), so the two are one family:
%
%   opt.allow_no_vf_island = true   suspends that refusal for this run only
%   opt.angle_gauge_bus = 1         pins imag(V_1)=0 after the trip. With no
%     absolute angle reference the coupled Newton Jacobian is rank-deficient by
%     exactly one -- the rotation gauge -- and Newton diverges at any step size.
%     The pin selects the gauge member the delivered reference bus already used;
%     |V|, P, Q and frequency are gauge-invariant.
%   ibr_factory_override -> ibr.eecon49_dual_mode_ideal_dc   the comparison-only
%     clone whose DC closure reverts to the retired ideal law
%     dVdc/dt = (Vdc0-Vdc)/Tdc, Tdc = 0.10 s -- the model the EECON49 paper's
%     Fixed-GFL figure used. It keeps Vdc away from the Pac/Vdc singularity
%     during long violent oscillations. Production builds are untouched: the
%     override reaches the device factory only through
%     scenario_opt.ibr_factory_override, which no production caller sets.
%
% Classification: ASSUMED_DIAGNOSTIC. Presentation/comparison only. It is not a
% readiness claim and no acceptance gate is relaxed by it -- the arm exists to
% show what the policy this project rejects actually does.
%
% Output: output/diagnostics/ieee14_locked_gfl_diag/locked_gfl_diag_160s.mat

pf_init_paths();

ip = inputParser;
ip.addParameter('TEnd',160);
ip.addParameter('Dt',0.02);
ip.addParameter('OutFile','locked_gfl_diag_160s.mat');
% Stepper. FIXED by default, and that is a measurement, not a preference: the
% adaptive controller was tried first on this arm and did not finish. It stretches
% dt to 0.5 s on a quiet island and subdivides toward dt/2^12 on a violent one, so
% on a trajectory that rings at ~1-15 Hz it spends the whole run rejecting steps --
% 74 min of CPU on the (0.20, 220.00) pair without reaching t_end. The ripple sweep
% (scripts/diagnostics/sweep_fixed_gfl_ripple.m) ran the SAME six pairs to 50 s on a
% fixed 0.02 s grid and every one converged, so the fixed grid is the setting this
% arm is known to complete on. It also has to be fixed for a second reason: a ring
% cannot be measured on a grid that the ring itself is allowed to stretch.
ip.addParameter('Stepper','fixed');
% Diagnostic PLL gains, applied to the resource table only (see below).
% Defaults are the delivered pair; the ripple sweep
% (scripts/diagnostics/sweep_fixed_gfl_ripple.m) measured (0.20, 220.00) as
% the strongest oscillating pair (V9 peak-to-peak 1.47 pu over the island
% window), and that is what the comparison figure is drawn from. The GFL
% equations, limiter, anti-windup, DC closure, solver and every acceptance
% gate are unchanged -- only these two gains move.
ip.addParameter('KpPll',0.20);
ip.addParameter('KiPll',220.00);
ip.parse(varargin{:});

sys = ibr.build_ieee14_switch_system(index_mode='agsi_pp', ...
    case_profile='eecon49_figure4',sg_H=2.5,sg_D=1.0, ...
    T_d_on=0.10,T_d_off=1.0);

scenario = cases.scenario_ieee14_1sg_4ibr( ...
    struct('case_profile','eecon49_figure4'));

% The diagnostic gain override. +cases/scenario_ieee14_1sg_4ibr.m and every
% production path are untouched: this edits the built resource table of this
% arm only, and the values are recorded in the provenance below.
for k = 1:numel(scenario.resources)
    rk = scenario.resources(k);
    if ~strcmpi(char(rk.resource_type),'ibr'), continue; end
    scenario.resources(k).dynamic_params.gfl_eecon49.kpPLL = ip.Results.KpPll;
    scenario.resources(k).dynamic_params.gfl_eecon49.kiPLL = ip.Results.KiPll;
end

selector_table = stability.ibr_selector_table(scenario.case_data, ...
    scenario.resources,scenario,struct());

% The schedule of sg_fault_cycle160, field for field. 'sg_fault_cycle' arms
% fault + sg_trip + sg_reclose + sync_controller and requires
% sg_trip < fault_on < fault_clear < sg_on <= t_end.
events = struct('enabled',true,'event_profile','sg_fault_cycle', ...
    'sg_trip',20,'fault_on',60,'fault_clear',60.15, ...
    'fault_bus',9,'Zf',0.01+0.01i,'sg_on',100, ...
    'coordinated_handback',false, ...
    'delays_overrides',struct('timeout_s',20,'dwell_s',0.5));

opt = struct( ...
    't_end',ip.Results.TEnd,'dt',ip.Results.Dt,'verbose',false, ...
    'plot_results',false, ...
    'max_step_subdivisions',12,'state_predictor','linear_kcl', ...
    'severity_gamma_on',0.65,'severity_gamma_off',0.35, ...
    'severity_T_d_on',0.10,'severity_T_d_off',1.00, ...
    'healthy_pf_V',sys.pf.bus_voltage(:).', ...
    'healthy_pf_bus_ids',sys.pf.external_bus_ids(:).', ...
    'stepper',ip.Results.Stepper,'reject_limit',20, ...
    'support_transition_certificate',true, ...
    'handback_efd_timescale','control', ...
    'agsi_reference',true, ...
    'anti_windup_blend',1e-3, ...
    'selector_table',selector_table);

% --- the locked_gfl arm overrides (run_ieee14_gfm_lock_comparison arms(5)) --
events.automatic_gfm_switching = false;
opt.automatic_support_supervision = true;

% --- the three diagnostic additions ---------------------------------------
opt.allow_no_vf_island = true;
opt.angle_gauge_bus = 1;
opt.angle_gauge_after = events.sg_trip + 0.25;
opt.ibr_events = events;

scenario.scenario_opt.ibr_factory_override = struct();
scenario.scenario_opt.ibr_factory_override.IBR2 = @ibr.eecon49_dual_mode_ideal_dc;
scenario.scenario_opt.ibr_factory_override.IBR3 = @ibr.eecon49_dual_mode_ideal_dc;
scenario.scenario_opt.ibr_factory_override.IBR6 = @ibr.eecon49_dual_mode_ideal_dc;
scenario.scenario_opt.ibr_factory_override.IBR8 = @ibr.eecon49_dual_mode_ideal_dc;

fprintf('running locked_gfl 160 s diagnostic arm ...\n');
t0 = tic;
r = stability.run_hybrid_case(scenario,opt);
elapsed = toc(t0);

outdir = fullfile('output','diagnostics','ieee14_locked_gfl_diag');
if ~isfolder(outdir), mkdir(outdir); end
S = struct( ...
    'result',r, ...
    'elapsed',elapsed, ...
    'classification','ASSUMED_DIAGNOSTIC', ...
    'schedule','sg_fault_cycle: sg_trip 20, fault_on 60, fault_clear 60.15, sg_on 100, t_end 160', ...
    'note',['Fixed-GFL comparison arm for scenario sg_fault_cycle160. ' ...
            'locked_gfl arm re-run with allow_no_vf_island=true, ' ...
            'angle_gauge_bus=1 after sg_trip+0.25 s, and the four IBRs built ' ...
            'by the comparison-only clone ibr.eecon49_dual_mode_ideal_dc. ' ...
            'The production noVoltageFormingSource refusal is unchanged.'], ...
    'option',['events.automatic_gfm_switching=false; ' ...
              'opt.automatic_support_supervision=true; ' ...
              'opt.allow_no_vf_island=true; opt.angle_gauge_bus=1; ' ...
              'opt.stepper=' ip.Results.Stepper '; ' ...
              'scenario_opt.ibr_factory_override=@ibr.eecon49_dual_mode_ideal_dc ' ...
              'for IBR2/3/6/8; every other option identical to ' ...
              'run_ieee14_scenario_suite base_request(dt=0.05,t_end=160)'], ...
    'pll_gains',[ip.Results.KpPll ip.Results.KiPll], ...
    'generated',char(datetime('now')));
cache = fullfile(outdir,ip.Results.OutFile);
save(cache,'-struct','S','-v7.3');
fprintf(['DONE elapsed=%.1f s  converged=%d  t_end=%.6f  samples=%d  ' ...
         'failure=%s\nwrote %s\n'],elapsed,logical(r.converged),r.t(end), ...
         numel(r.t),char(string(r.failure_id)),cache);
out = struct('result',r,'cache',cache,'elapsed',elapsed);
end
