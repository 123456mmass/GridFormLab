function adaptive_ts_diagnostic()
%ADAPTIVE_TS_DIAGNOSTIC  Tracked adaptive-vs-fixed diagnostic (all 3 models).
%   Replaces the untracked /tmp/track_a_adaptive_xval.m. Runs the single
%   shared helper adaptive_ts_compare_fixed on Case14 (classical), Padiyar
%   two-area (padiyar_1_1_avr, 15 s long-horizon), and EMF6 Kundur
%   (case_kundur_two_area_classical). The helper ALONE owns ID mapping,
%   event-segmented interp_no_extrapolate, metrics, and structural checks.
%
%   Report-only: numerical diffs (delta/omega/Pe/Vbus COI & pairwise) are
%   DIAGNOSTICS, not acceptance gates. The only hard gates are STRUCTURAL
%   invariants (finite, coverage_valid, no extrapolation, no cross-event
%   interpolation, exact event landing, ID mapping, algebraic convergence).
%
%   Per the honesty-closure policy:
%     - 1.0 deg fixed-vs-adaptive threshold is NOT imposed here. It is kept
%       ONLY as a historical ASSUMED_DIAGNOSTIC regression guard inside
%       tests/test_ts_classical_adaptive.m.
%     - These adaptive results are diagnostic-only; held-out adaptive
%       VALIDATION = NOT_READY.
pf_init_paths;
addpath('scripts/validation');
fprintf('\n##########################################################\n');
fprintf('# TRACK A: ADAPTIVE-vs-FIXED DIAGNOSTIC (event-segmented) #\n');
fprintf('##########################################################\n');

% --- Case14 classical ------------------------------------------------------
rep14 = adaptive_ts_compare_fixed('case_matpower6_case14','classical', ...
    struct('t_end',5,'dt',0.01,'fault_bus',4,'t_fault',1.0,'t_clear',1.1,'Zf',1i*0.1));
m14 = rep14.metrics;
fprintf('Case14 classical: structural_pass=%d  accepted=%d rejected=%d\n', ...
    rep14.structural_pass, rep14.accepted_steps, rep14.rejected_steps);
fprintf('  delta_coi=%.4f deg  pairwise=%.4f deg  omega=%.3e pu  Pe=%.4f MW  Vbus=%.3e pu\n', ...
    m14.delta_coi_deg, m14.delta_pairwise_deg, m14.omega_pu, m14.Pe_MW, m14.Vbus_pu);

% --- Padiyar two-area 15 s long-horizon ------------------------------------
rep_pad = adaptive_ts_compare_fixed('case_padiyar_two_area_4m_avr','padiyar_1_1_avr', ...
    struct('t_end',15,'dt',0.01,'fault_bus',3,'t_fault',1.0,'t_clear',1.1,'Zf',1i*0.1));
mpad = rep_pad.metrics;
fprintf('Padiyar 15s:       structural_pass=%d  accepted=%d rejected=%d\n', ...
    rep_pad.structural_pass, rep_pad.accepted_steps, rep_pad.rejected_steps);
fprintf('  delta_coi=%.4f deg  pairwise=%.4f deg  omega=%.3e pu  Pe=%.4f MW  Vbus=%.3e pu\n', ...
    mpad.delta_coi_deg, mpad.delta_pairwise_deg, mpad.omega_pu, mpad.Pe_MW, mpad.Vbus_pu);

% --- EMF6 Kundur (vs fixed canonical; PSAT raw comparison is separate) ----
rep_emf = adaptive_ts_compare_fixed('case_kundur_two_area_classical','emf6', ...
    struct('t_end',5,'dt',1e-3,'fault_bus',8,'t_fault',1.0,'t_clear',1.05,'Zf',[]));
memf = rep_emf.metrics;
fprintf('EMF6 Kundur:       structural_pass=%d  accepted=%d rejected=%d\n', ...
    rep_emf.structural_pass, rep_emf.accepted_steps, rep_emf.rejected_steps);
fprintf('  delta_coi=%.4f deg  pairwise=%.4f deg  omega=%.3e pu  Pe=%.4f MW  Vbus=%.3e pu\n', ...
    memf.delta_coi_deg, memf.delta_pairwise_deg, memf.omega_pu, memf.Pe_MW, memf.Vbus_pu);

% --- EMF6 adaptive vs PSAT (Kundur 12.6, if saved raw data present) --------
fprintf('\n=== EMF6 adaptive vs PSAT (Kundur 12.6) ===\n');
projroot = '/home/birds/Documents/Power-flow-adaptive';
raw = fullfile(projroot,'docs','source','figures','kundur_ex126','psat_kundur6_ts_raw.mat');
if exist(raw,'file')
    S = load(raw); ps = S.ps_save;
    c = cases.case_kundur_two_area_classical();
    r_emf = stability.ts_simulate(c, struct('model','emf6','stepper','adaptive', ...
        't_end',min(ps.td_tend,6),'dt',1e-3,'fault_bus',8,'t_fault',1.0,'t_clear',1.05, ...
        'Zf',[],'load_model','cz','verbose',false));
    [~,oo] = sort(r_emf.gen_buses);
    do = rad2deg(r_emf.delta(:,oo)); tg = r_emf.t; H = r_emf.H(:).';
    dps = rad2deg(interp_no_extrapolate(ps.t, ps.delta, tg));
    [~,o] = sort(ps.delta_bus); dps = dps(:,o);
    drel_p = dps - sum(H.*dps,2)/sum(H); drel_o = do - sum(H.*do,2)/sum(H);
    fprintf('  nt=%d accepted=%d rejected=%d\n', numel(r_emf.t), r_emf.accepted_steps, r_emf.rejected_steps);
    fprintf('  max COI angle diff vs PSAT = %.4f deg (PSAT raw is SAVED data, not fresh execution)\n', ...
        max(abs(drel_p-drel_o),[],'all'));
else
    fprintf('  PSAT Kundur6 raw .mat not present; skipped (this is SAVED reference data, not fresh).\n');
end

fprintf('\n##########################################################\n');
fprintf('# DIAGNOSTIC COMPLETE (report-only; NOT acceptance gates) #\n');
fprintf('##########################################################\n');
end
