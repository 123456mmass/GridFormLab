function tests = test_ibr_smib_tds_signals
%TEST_IBR_SMIB_TDS_SIGNALS Time-domain dq/P/Q reconstruction for both IBRs.
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function test_gfl_time_signals_follow_nonlinear_trajectory(tc)
r = run_case(cases.case_ibr_smib_gfl_rms10());
verify_signals(tc,r,'NATIVE_GFL_CURRENT_STATES');
end

function test_gfm_time_signals_follow_nonlinear_trajectory(tc)
r = run_case(cases.case_ibr_smib_gfm_no_pll());
verify_signals(tc,r,'PROJECT_DERIVED_DIAGNOSTIC_VSM_FRAME_TRANSFORM');
end

function test_four_separate_time_plot_files(tc)
expected = {'tds_id_vs_time','tds_iq_vs_time', ...
    'tds_active_power_vs_time','tds_reactive_power_vs_time'};
case_list = {cases.case_ibr_smib_gfl_rms10(), ...
    cases.case_ibr_smib_gfm_no_pll()};
for c = 1:numel(case_list)
    r = run_case(case_list{c});
    files = ibr.plot_smib_verification_case(r,'visible',false);
    for k = 1:numel(expected)
        tc.verifyTrue(any(contains(files,expected{k})), ...
            sprintf('Missing separate TDS plot %s.',expected{k}));
    end
end
tc.verifyEqual(numel(findall(groot,'Type','figure')),0);
end

function r = run_case(case_data)
r = ibr.run_smib_verification_case(case_data,struct( ...
    'ibr_analysis','ts','t_end',0.02,'dt',1e-3, ...
    'plot_results',false,'plot_visible',false));
end

function verify_signals(tc,r,expected_source)
q = r.ts;
s = q.signals_perturbed;
n = numel(q.tgrid);
tc.verifySize(q.y_perturbed,[2 n]);
tc.verifySize(s.i_d_pu_inverter,[n 1]);
tc.verifySize(s.i_q_pu_inverter,[n 1]);
tc.verifySize(s.P_MW,[n 1]);
tc.verifySize(s.Q_MVAr,[n 1]);
tc.verifyTrue(all(isfinite([s.i_d_pu_inverter; s.i_q_pu_inverter; ...
    s.P_MW; s.Q_MVAr])));
tc.verifyEqual(s.current_source,expected_source);
tc.verifyLessThanOrEqual(max(s.power_identity_error), ...
    s.power_identity_tolerance);
end
