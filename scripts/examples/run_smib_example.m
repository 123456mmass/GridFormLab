function results = run_smib_example(options)
%RUN_SMIB_EXAMPLE Standalone SMIB small-signal stability demonstration.
%   RESULTS = RUN_SMIB_EXAMPLE(OPTIONS) runs the complete small-signal
%   stability analysis of the single-machine infinite-bus (SMIB) system for
%   all four model levels of Kundur Chapter 12, prints each result against
%   the textbook golden values, and generates the four presentation plots.
%
%   Models:
%     A - classical                 (Kundur Example 12.2)
%     B - + field circuit           (Kundur Example 12.3, K derived from d-q)
%     C - + exciter / AVR           (Kundur Section 12.4, Table 12.1)
%     D - + power system stabilizer (Kundur Example 12.6)
%
%   OPTIONS (struct, optional):
%     plot_results - generate the four figures (default true)
%     save_plots   - export figures to PNG (default false)
%     plots_dir    - output directory for PNGs (default 'smib_plots')
%     visible      - figure visibility 'on' (default) / 'off' (headless)
%     verbose      - print comparison tables (default true)
%
%   RESULTS struct collects the per-model analysis outputs and a pass/fail
%   summary versus the golden references.
%
%   Reference: P. Kundur, "Power System Stability and Control", Chapter 12.

pf_init_paths();
if nargin < 1 || isempty(options); options = struct(); end
plot_results = get_opt(options, 'plot_results', true);
save_plots   = get_opt(options, 'save_plots', false);
plots_dir    = get_opt(options, 'plots_dir', 'smib_plots');
visible      = get_opt(options, 'visible', 'on');
verbose      = get_opt(options, 'verbose', true);

if save_plots && ~exist(plots_dir, 'dir'); mkdir(plots_dir); end

results = struct();
checks = {};   % {label, value, golden, tol, kind}

hdr('SMIB SMALL-SIGNAL STABILITY ANALYSIS (Kundur Chapter 12)');

% ===================== Model A - classical (Ex 12.2) =====================
hdr('Model A - Classical (Example 12.2)');
cA  = cases.case_kundur_smib_classical();
opA = smib.smib_classical_init(cA.machine, cA.network, cA.operating);
w0A = 2 * pi * cA.base_values.frequency_Hz;
gA  = cA.reference_solution;

if verbose
    fprintf('  Operating point:\n');
    rowf('delta0 (deg)', opA.delta0_deg, gA.delta0_deg);
    rowf('|E''| (pu)',    opA.Ep_mag,     gA.Ep_mag);
    rowf('XT (pu)',      opA.XT,         gA.XT);
    rowf('Ks',           opA.Ks,         gA.Ks);
end
checks(end+1,:) = {'A delta0', opA.delta0_deg, gA.delta0_deg, 0.01, 'rel'};
checks(end+1,:) = {'A Ks',     opA.Ks,         gA.Ks,         0.01, 'rel'};

KD_sweep = [0, 10, -10];
golden_eig = {gA.eig_KD0, gA.eig_KD10, gA.eig_KDneg10};
rA = struct();
if verbose; fprintf('\n  Eigenvalues vs damping coefficient K_D:\n'); end
for i = 1:numel(KD_sweep)
    s = smib.smib_build_state_matrix('A', struct('H', cA.machine.H, ...
        'KD', KD_sweep(i), 'Ks', opA.Ks, 'w0', w0A));
    r = smib.smib_analyze(s);
    rA.(sprintf('KD%d', i)) = r;
    lam = r.eigenvalues(imag(r.eigenvalues) >= 0); lam = lam(1);
    g = golden_eig{i}; g = g(imag(g) >= 0); g = g(1);
    if verbose
        fprintf('    KD=%+3d: lambda = %7.4f %+7.4fj  (golden %7.4f %+7.4fj)  stable=%d\n', ...
            KD_sweep(i), real(lam), imag(lam), real(g), imag(g), r.is_stable);
    end
    checks(end+1,:) = {sprintf('A eig(KD=%d) Re', KD_sweep(i)), real(lam), real(g), 0.02, 'abs'}; %#ok<*AGROW>
    checks(end+1,:) = {sprintf('A eig(KD=%d) Im', KD_sweep(i)), imag(lam), imag(g), 0.05, 'abs'};
end
results.A = struct('op', opA, 'analyze', rA);

% ================== Model B - field circuit (Ex 12.3) ====================
hdr('Model B - Field Circuit (Example 12.3, K derived from d-q params)');
cB  = cases.case_kundur_smib_detailed();
opB = smib.smib_dq_init(cB.machine, cB.network, cB.operating);
w0B = 2 * pi * cB.base_values.frequency_Hz;
KB  = smib.smib_k_constants(cB.machine, cB.network, opB, w0B);
gB  = cB.reference_solution;

if verbose
    fprintf('  Operating point & K-constants (derived):\n');
    rowf('delta0 (deg)', opB.delta0_deg, gB.delta0_deg);
    rowf('Efd0 (pu)',    opB.Efd0,       gB.Efd0);
    rowf('K1', KB.K1, gB.K1);  rowf('K2', KB.K2, gB.K2);
    rowf('K4', KB.K4, gB.K4);  rowf('T3', KB.T3, gB.T3);
end
checks(end+1,:) = {'B delta0', opB.delta0_deg, gB.delta0_deg, 0.01, 'rel'};
checks(end+1,:) = {'B K1', KB.K1, gB.K1, 0.01, 'rel'};
checks(end+1,:) = {'B K2', KB.K2, gB.K2, 0.01, 'rel'};
checks(end+1,:) = {'B K4', KB.K4, gB.K4, 0.01, 'rel'};

sysB = smib.smib_build_state_matrix('B', struct('H', cB.machine.H, ...
    'KD', cB.machine.KD, 'w0', w0B, 'K1', KB.K1, 'K2', KB.K2, ...
    'a32', KB.a32, 'a33', KB.a33, 'b3', KB.b3));
rB = smib.smib_analyze(sysB);
osc = rB.eigenvalues(imag(rB.eigenvalues) > 1e-3);
gosc = gB.eig_osc(imag(gB.eig_osc) > 0);
if verbose
    fprintf('\n  Eigenvalues:\n');
    fprintf('    swing: %7.4f %+7.4fj  (golden %7.4f %+7.4fj)\n', ...
        real(osc(1)), imag(osc(1)), real(gosc(1)), imag(gosc(1)));
    realmode = rB.eigenvalues(abs(imag(rB.eigenvalues)) <= 1e-3);
    fprintf('    field: %7.4f            (golden %7.4f)\n', ...
        min(real(realmode)), gB.eig_real);
    fprintf('    stable=%d\n', rB.is_stable);
end
checks(end+1,:) = {'B swing Re', real(osc(1)), real(gosc(1)), 0.02, 'abs'};
checks(end+1,:) = {'B swing Im', imag(osc(1)), imag(gosc(1)), 0.05, 'abs'};
results.B = struct('op', opB, 'K', KB, 'analyze', rB);

% ================== Model C - exciter / AVR (Table 12.1) =================
hdr('Model C - Exciter / AVR (Section 12.4, Table 12.1)');
cC  = cases.case_kundur_smib_avr();
w0C = 2 * pi * cC.base_values.frequency_Hz;
gC  = cC.reference_solution;
if verbose
    fprintf('  Torque components vs AVR gain K_A (omega=%.3g rad/s):\n', gC.omega_eval);
    fprintf('    %4s | %10s %10s | %10s %10s\n', 'KA', 'Ks(dpsi)', 'golden', 'KD(dpsi)', 'golden');
end
tdC = cell(numel(gC.KA_list), 1);
for i = 1:numel(gC.KA_list)
    ex = struct('KA', gC.KA_list(i), 'TR', cC.exciter.TR);
    td = smib.smib_torque_components(cC.k_constants, ex, cC.machine.H, w0C, gC.omega_eval);
    tdC{i} = td;
    if verbose
        fprintf('    %4d | %10.4f %10.4f | %10.3f %10.3f\n', gC.KA_list(i), ...
            td.Ks_dpsifd, gC.Ks_dpsifd_list(i), td.KD_dpsifd, gC.KD_dpsifd_list(i));
    end
    checks(end+1,:) = {sprintf('C Ks(KA=%d)', gC.KA_list(i)), td.Ks_dpsifd, gC.Ks_dpsifd_list(i), 0.005, 'abs'};
    checks(end+1,:) = {sprintf('C KD(KA=%d)', gC.KA_list(i)), td.KD_dpsifd, gC.KD_dpsifd_list(i), 0.02, 'abs'};
end
results.C = struct('torque', {tdC});

% ================== Model D - AVR + PSS (Example 12.6) ===================
hdr('Model D - AVR + PSS (Example 12.6)');
cD  = cases.case_kundur_smib_pss();
w0D = 2 * pi * cD.base_values.frequency_Hz;
K = cD.k_constants; ex = cD.exciter; pss = cD.pss; gD = cD.reference_solution;

% AVR only (no PSS) -> unstable swing mode
sysC = smib.smib_build_state_matrix('C', struct('H', cD.machine.H, ...
    'KD', cD.machine.KD, 'w0', w0D, 'K1', K.K1, 'K2', K.K2, 'K3', K.K3, ...
    'K4', K.K4, 'K5', K.K5, 'K6', K.K6, 'T3', K.T3, 'TR', ex.TR, 'KA', ex.KA));
rC = smib.smib_analyze(sysC);
oscC = rC.eigenvalues(imag(rC.eigenvalues) > 1e-3);

% AVR + PSS -> stabilized
sysD = smib.smib_build_state_matrix('D', struct('H', cD.machine.H, ...
    'KD', cD.machine.KD, 'w0', w0D, 'K1', K.K1, 'K2', K.K2, 'K3', K.K3, ...
    'K4', K.K4, 'K5', K.K5, 'K6', K.K6, 'T3', K.T3, 'TR', ex.TR, 'KA', ex.KA, ...
    'KSTAB', pss.KSTAB, 'Tw', pss.Tw, 'T1', pss.T1, 'T2', pss.T2));
rD = smib.smib_analyze(sysD);
oscD = rD.eigenvalues(imag(rD.eigenvalues) > 1e-3);
[~, idx] = min(abs(imag(oscD) - imag(gD.pss_eig_swing(1))));
swing = oscD(idx);
sw_zeta = -real(swing) / abs(swing);

if verbose
    fprintf('  AVR only (KA=%d, K5<0): swing = %7.4f %+7.4fj  (golden %7.4f %+7.4fj)  stable=%d\n', ...
        ex.KA, real(oscC(1)), imag(oscC(1)), ...
        real(gD.avr_only_eig_osc(1)), imag(gD.avr_only_eig_osc(1)), rC.is_stable);
    fprintf('  AVR + PSS:             swing = %7.4f %+7.4fj  (golden %7.4f %+7.4fj)  zeta=%.3f (golden %.3f)  stable=%d\n', ...
        real(swing), imag(swing), real(gD.pss_eig_swing(1)), imag(gD.pss_eig_swing(1)), ...
        sw_zeta, gD.pss_swing_zeta, rD.is_stable);
end
checks(end+1,:) = {'D AVR-only Re', real(oscC(1)), real(gD.avr_only_eig_osc(1)), 0.02, 'abs'};
checks(end+1,:) = {'D AVR-only Im', imag(oscC(1)), imag(gD.avr_only_eig_osc(1)), 0.05, 'abs'};
checks(end+1,:) = {'D PSS swing Re', real(swing), real(gD.pss_eig_swing(1)), 0.05, 'abs'};
checks(end+1,:) = {'D PSS swing zeta', sw_zeta, gD.pss_swing_zeta, 0.02, 'abs'};
results.D = struct('avr_only', rC, 'pss', rD, 'swing', swing);

% ============================ Plots ======================================
if plot_results
    hdr('Generating plots');
    vis = struct('visible', visible);

    % 1. Root locus: sweep KD on Model A
    KDvals = -10:2:20; eigc = cell(numel(KDvals), 1);
    for i = 1:numel(KDvals)
        s = smib.smib_build_state_matrix('A', struct('H', cA.machine.H, ...
            'KD', KDvals(i), 'Ks', opA.Ks, 'w0', w0A));
        eigc{i} = eig(s.A);
    end
    sweep = struct('values', KDvals, 'eigenvalues', {eigc}, ...
        'param_name', 'K_D', 'title', 'SMIB classical: eigenvalues vs K_D');
    o1 = merge_opt(vis, save_plots, plots_dir, '01_root_locus.png');
    o1.mark_points = struct('value', {-10, 0, 10}, ...
        'label', {'K_D=-10', 'K_D=0', 'K_D=10'});
    results.fig_root_locus = smib_plot_root_locus(sweep, o1);

    % 2. Step response of Model A (KD=10)
    sysA10 = smib.smib_build_state_matrix('A', struct('H', cA.machine.H, ...
        'KD', 10, 'Ks', opA.Ks, 'w0', w0A));
    o2 = merge_opt(vis, save_plots, plots_dir, '02_step_response.png');
    results.fig_step = smib_plot_step_response(sysA10, o2);

    % 3. Mode shape of Model B swing mode
    o3 = merge_opt(vis, save_plots, plots_dir, '03_mode_shape.png');
    results.fig_mode = smib_plot_mode_shape(rB, o3);

    % 4. Torque components vs KA (Model C)
    o4 = merge_opt(vis, save_plots, plots_dir, '04_torque_vs_ka.png');
    o4.omega_eval = gC.omega_eval;
    results.fig_torque = smib_plot_torque_vs_ka(cC.k_constants, cC.exciter, ...
        cC.machine.H, w0C, o4);

    % 5. Electrical power response of Model A (KD=10): dPe ~= Ks*ddelta
    o5 = merge_opt(vis, save_plots, plots_dir, '05_power_response.png');
    results.fig_power = smib_plot_power_response(sysA10, o5);

    % 6. Eigenvalue comparison: AVR-only (RHP) vs AVR+PSS (LHP)
    setAVR = struct('eigenvalues', rC.eigenvalues, 'name', 'AVR only (K_A=200)', ...
        'color', [0.83 0.20 0.15], 'marker', 'o');
    setPSS = struct('eigenvalues', rD.eigenvalues, 'name', 'AVR + PSS', ...
        'color', [0.05 0.36 0.60], 'marker', 's');
    o6 = merge_opt(vis, save_plots, plots_dir, '06_eig_comparison.png');
    results.fig_eigcmp = smib_plot_eig_comparison([setAVR, setPSS], o6);

    if save_plots
        fprintf('  Saved 6 figures to %s\n', plots_dir);
    end
end

% ============================ Summary ====================================
hdr('Golden-reference verification summary');
npass = 0; nfail = 0;
for i = 1:size(checks, 1)
    [lbl, val, gold, tol, kind] = checks{i, :};
    if strcmp(kind, 'rel')
        ok = abs(val - gold) <= tol * abs(gold);
    else
        ok = abs(val - gold) <= tol;
    end
    if ok; npass = npass + 1; else; nfail = nfail + 1; end
    if verbose || ~ok
        fprintf('  [%s] %-18s computed=%9.4f golden=%9.4f\n', ...
            tern(ok, 'PASS', 'FAIL'), lbl, val, gold);
    end
end
fprintf('\n  RESULT: %d passed, %d failed (of %d checks)\n', npass, nfail, npass + nfail);
results.summary = struct('passed', npass, 'failed', nfail, 'total', npass + nfail);
end

% ------------------------------------------------------------------------
function v = get_opt(o, n, d)
if isstruct(o) && isfield(o, n) && ~isempty(o.(n)); v = o.(n); else; v = d; end
end
function o = merge_opt(base, save_plots, plots_dir, fname)
o = base;
if save_plots; o.save_path = fullfile(plots_dir, fname); end
end
function hdr(txt)
fprintf('\n============================================================\n');
fprintf('%s\n', txt);
fprintf('============================================================\n');
end
function rowf(name, val, gold)
fprintf('    %-14s %10.4f   (golden %10.4f)\n', name, val, gold);
end
function s = tern(cond, a, b)
if cond; s = a; else; s = b; end
end
