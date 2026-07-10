function diag_kundur_ssa(varargin)
%DIAG_KUNDUR_SSA Diagnostic harness for the Kundur Ex12.6 6th-order SSSA.
%   Runs stability.kundur_ex126_sauer_pai_ssa and prints:
%     - DAE equilibrium residual norm
%     - Afull / Ared sizes
%     - all 24 eigenvalues sorted by real part
%     - matched 3 key swing modes vs Kundur Table E12.3 targets
%     - absolute errors in Re, Im, frequency, damping
%   Usage (from project root):
%     diag_kundur_ssa            % plain text
%     diag_kundur_ssa('json')    % one-line JSON-ish summary for quick diff

json = (nargin >= 1 && strcmpi(varargin{1}, 'json'));
load_model = 'cc_p_cz_q';
use_sat = false;
if nargin >= 1 && ~strcmpi(varargin{1}, 'json'); load_model = varargin{1}; end
if nargin >= 2 && strcmpi(varargin{2}, 'sat'); use_sat = true; end

pf_init_paths;
case_data = cases.case_kundur_two_area_classical();
pf_opts = struct('plot_results', false, 'verbose', false, 'max_iter', 50, ...
    'tolerance', 1e-8, 'enforce_q_limits', false);
pf = pfsolver.powerflow_newton_raphson(case_data, pf_opts);
ssa_opts = struct('load_model', load_model, 'use_saturation', use_sat);
ssa = stability.kundur_ex126_sauer_pai_ssa('pf', pf, 'options', ssa_opts);

% Kundur Table E12.3 targets (3 key swing modes).
targets = [ ...
    -0.111 + 1i*3.43;   % interarea
    -0.492 + 1i*6.82;   % area 1 local
    -0.506 + 1i*7.02];  % area 2 local
target_names = {'interarea', 'area1 local', 'area2 local'};

lam = ssa.eigenvalues(:);
[~, idx] = sort(real(lam), 'descend');
lam = lam(idx);

% Match by nearest oscillation frequency among oscillatory modes.
osc = lam(imag(lam) > 1e-3);
osc_freq = abs(imag(osc)) / (2*pi);
matched = zeros(3, 1);
used = false(numel(osc), 1);
for k = 1:3
    ref_freq = abs(imag(targets(k))) / (2*pi);
    d = abs(osc_freq - ref_freq);
    d(used) = inf;
    [~, j] = min(d);
    matched(k) = osc(j);
    used(j) = true;
end

if json
    fprintf('JSON{');
    fprintf('"resid":%.4e,', ssa.newton_residual);
    fprintf('"Afull":[%d,%d],', size(ssa.Afull,1), size(ssa.Afull,2));
    fprintf('"Ared":[%d,%d],', size(ssa.Ared,1), size(ssa.Ared,2));
    fprintf('"modes":[');
    for k = 1:3
        fprintf('{"name":"%s","re":%.6f,"im":%.6f,"f":%.4f,"zeta":%.4f,', ...
            target_names{k}, real(matched(k)), imag(matched(k)), ...
            abs(imag(matched(k)))/(2*pi), -real(matched(k))/abs(matched(k)));
        fprintf('"dRe":%.4f,"dIm":%.4f,"df":%.4f,"dzeta":%.4f}%s', ...
            real(matched(k))-real(targets(k)), ...
            abs(imag(matched(k)))-abs(imag(targets(k))), ...
            abs(imag(matched(k)))/(2*pi)-abs(imag(targets(k)))/(2*pi), ...
            (-real(matched(k))/abs(matched(k))) - (-real(targets(k))/abs(targets(k))), ...
            ternary(k<3, ',', ''));
    end
    fprintf(']}');
    fprintf('\n');
    return;
end

fprintf('============================================================\n');
fprintf('  Kundur Ex12.6 6th-order Sauer-Pai SSSA -- diagnostics\n');
fprintf('============================================================\n');
fprintf('DAE equilibrium residual ||[f;g]||_2 = %.4e\n', ssa.newton_residual);
fprintf('Afull = %dx%d, Ared = %dx%d\n', size(ssa.Afull,1), size(ssa.Afull,2), ...
    size(ssa.Ared,1), size(ssa.Ared,2));
fprintf('newton iterations = %d, refine passes = %d\n', ...
    ssa.newton_iterations, ssa.init.refine_passes);
fprintf('\nFull 24 eigenvalues (sorted by real part, descending):\n');
fprintf('  No.        Real           Imag          f(Hz)      zeta\n');
for k = 1:numel(lam)
    fprintf('%4d  %12.6f  %+12.6f  %9.4f  %8.4f\n', k, real(lam(k)), ...
        imag(lam(k)), abs(imag(lam(k)))/(2*pi), -real(lam(k))/(abs(lam(k))+eps));
end

fprintf('\nMatched key swing modes vs Kundur Table E12.3:\n');
fprintf('  %-14s %18s %18s %8s %8s %8s %8s\n', ...
    'mode', 'ours (re+-jim)', 'Kundur', 'dRe', 'dIm', 'df(Hz)', 'dzeta');
for k = 1:3
    f_ours = abs(imag(matched(k)))/(2*pi);
    f_kun  = abs(imag(targets(k)))/(2*pi);
    z_ours = -real(matched(k))/abs(matched(k));
    z_kun  = -real(targets(k))/abs(targets(k));
    fprintf('  %-14s %8.4f+-%.4f %8.4f+-%.4f %+8.4f %+8.4f %+8.4f %+8.4f\n', ...
        target_names{k}, real(matched(k)), abs(imag(matched(k))), ...
        real(targets(k)), abs(imag(targets(k))), ...
        real(matched(k))-real(targets(k)), ...
        abs(imag(matched(k)))-abs(imag(targets(k))), f_ours-f_kun, z_ours-z_kun);
end

% Operating-point sanity dump (helps spot per-unit / sign issues).
init = ssa.init;
fprintf('\nOperating point (per machine):\n');
fprintf('  %-4s %9s %9s %9s %9s %9s %9s %9s %9s %9s\n', ...
    'gen','delta(deg)','Id','Iq','Vd','Vq','Eqp','Edp','Psipd','Psipq');
for k = 1:init.ng
    fprintf('  %-4s %9.3f %9.4f %9.4f %9.4f %9.4f %9.4f %9.4f %9.4f %9.4f\n', ...
        case_data.machines.units(k).gen_id, ...
        rad2deg(init.delta(k)), init.Id(k), init.Iq(k), init.Vd(k), init.Vq(k), ...
        init.Eqpi(k), init.Edpi(k), init.Psipd(k), init.Psipq(k));
end
fprintf('  Tm = '); fprintf('%.4f ', init.Tm); fprintf('\n');
fprintf('  Efd = '); fprintf('%.4f ', init.Efd); fprintf('\n');
fprintf('  H_sys = '); fprintf('%.4f ', init.H_sys); fprintf('\n');
fprintf('  zb_scale = %.6f\n', init.zb_scale);
end

function s = ternary(c, a, b)
if c; s = a; else; s = b; end
end
