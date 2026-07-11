function run_twoarea_smallsignal()
%RUN_TWOAREA_SMALLSIGNAL Run small-signal stability on the Kundur Two-Area
%   4-Machine (Example 12.6) system and print eigenvalues / damping /
%   comparison against Kundur Table E12.3.

pf_init_paths;
fprintf('=== Kundur Two-Area 4-Machine (Ex 12.6) Small-Signal Stability ===\n\n');

% 1) Steady-state power flow (operating point)
case_data = cases.case_kundur_two_area_classical();
opts = struct('plot_results', false, 'verbose', false, ...
    'max_iter', 50, 'tolerance', 1e-8, 'enforce_q_limits', false);
pf = pfsolver.powerflow_newton_raphson(case_data, opts);
fprintf('Power flow: converged=%d, iterations=%d, P_loss=%.4f pu, minV=%.4f, maxV=%.4f\n', ...
    pf.converged, pf.iterations, pf.P_loss_total, min(pf.bus_voltage), max(pf.bus_voltage));

% 2) 6th-order Sauer-Pai small-signal analysis (24 states)
fprintf('\nRunning 6th-order Sauer-Pai SSSA (24 states, 4 machines x 6) ...\n');
ssa6 = stability.kundur_ex126_sixth_order_ssa('pf', pf);

% 3) Print eigenvalues sorted by imaginary part
lam = ssa6.eigenvalues;
freq = ssa6.frequency_Hz;
zeta = ssa6.damping_ratio;
[~, idx] = sort(imag(lam), 'descend');

fprintf('\n%-6s %-26s %-12s %-10s %s\n', '#', 'Eigenvalue (1/s)', 'Freq (Hz)', 'Zeta', 'Stable');
fprintf('%s\n', repmat('-', 1, 70));
for k = 1:numel(idx)
    i = idx(k);
    stab = ternary(real(lam(i)) < -1e-9, 'YES', ternary(abs(real(lam(i)))<=1e-9,'~zero','NO'));
    fprintf('%-6d %-26s %-12.4f %-10.4f %s\n', k, eigstr(lam(i)), freq(i), zeta(i), stab);
end

fprintf('\nOverall system stable: %s\n', ternary(ssa6.stable, 'YES (all real parts < 0)', 'NO'));
fprintf('Newton refine iters: %d, residual: %.3e\n', ssa6.newton_iterations, ssa6.newton_residual);
fprintf('Total eigenvalues: %d\n', numel(lam));

% 4) Comparison vs Kundur Table E12.3 (book benchmark)
ref = ssa6.reference;
fprintf('\n--- Book benchmark modes (Kundur Table E12.3) ---\n');
fprintf('%-38s %-22s %-10s %-8s   %-22s %-10s %-8s\n', ...
    'Mode', 'Book eigenvalue', 'f(Hz)', 'zeta', 'Computed eigenvalue', 'f(Hz)', 'zeta');
fprintf('%s\n', repmat('-', 1, 120));
for m = 1:numel(ref.modes)
    mr = ref.modes(m);
    % find closest computed eigenvalue to this book mode
    [~, ci] = min(abs(lam - mr.lambda));
    cf = abs(imag(lam(ci)))/(2*pi);
    cz = -real(lam(ci))/(abs(lam(ci))+eps);
    fprintf('%-38s %-22s %-10.3f %-8.3f   %-22s %-10.3f %-8.3f\n', ...
        mr.mode, eigstr(mr.lambda), mr.computed_frequency_Hz, mr.computed_zeta, ...
        eigstr(lam(ci)), cf, cz);
end
end

function s = eigstr(z)
s = sprintf('%+.4g %+.4gi', real(z), imag(z));
end

function out = ternary(cond, a, b)
if cond, out = a; else, out = b; end
end
