function tests = test_sssa_contract()
%TEST_SSSA_CONTRACT Cross-model SSSA contract tests.
%   Verifies the production SSSA paths (Padiyar manual, Padiyar AVR, EMF6) from
%   their equations, NOT from published/literature acceptance targets. Tolerances
%   are declared up front from numerical precision and integration order -- they
%   are NOT relaxed after seeing a result.
%
%   Contracts:
%     1. Equilibrium residual + state count (manual=16, AVR=20, EMF6=6*ng)
%     2. SSSA and TS share the same DAE (same residual on same input, incl. perturbed)
%     3. Schur complement contract (Afull = Jxx - Jxy*(Jyy\Jyx); dimensions; finite)
%     4. No inv(Jyy) in production +stability/
%     5. Eigenvalue structure (finite, conjugate pairs)
%     6. Reference-angle structure (angle_shift_residual; zero mode Afull*shift~0)
%     7. Modal metrics present and finite (frequency, damping, time constant)

tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function ssa = padiyar_avr_fixture()
c = cases.case_padiyar_two_area_4m_avr();
ssa = stability.padiyar_model11_ssa(c, struct('excitation','avr','fd_eps',1e-6));
end

function ssa = padiyar_manual_fixture()
c = cases.case_padiyar_two_area_4m_avr();
ssa = stability.padiyar_model11_ssa(c, struct('excitation','manual','fd_eps',1e-6));
end

function ssa = emf6_fixture()
c = cases.kundur_ex126_book_case();
ssa = stability.synchronous_emf6_ssa(c, struct('load_model','cc_p_cz_q'));
end

function test_1a_padiyar_manual_equilibrium_and_count(testCase)
ssa = padiyar_manual_fixture();
f0 = norm(ssa.dae.dae_f(ssa.dae.x0, ssa.dae.y0), inf);
g0 = norm(ssa.dae.dae_g(ssa.dae.x0, ssa.dae.y0, ssa.dae.Ynet), inf);
testCase.verifyLessThan(f0, 1e-10, 'Padiyar manual max|f| at equilibrium');
testCase.verifyLessThan(g0, 1e-10, 'Padiyar manual max|g| at equilibrium');
testCase.verifyEqual(numel(ssa.dae.x0), 16, 'Padiyar manual = 4 states x 4 machines');
testCase.verifyEqual(ssa.dae.ns, 4, 'Padiyar manual states per machine');
testCase.verifyTrue(all(isfinite(ssa.dae.x0)) && all(isfinite(ssa.dae.y0)), 'all states finite');
end

function test_1b_padiyar_avr_equilibrium_and_count(testCase)
ssa = padiyar_avr_fixture();
f0 = norm(ssa.dae.dae_f(ssa.dae.x0, ssa.dae.y0), inf);
g0 = norm(ssa.dae.dae_g(ssa.dae.x0, ssa.dae.y0, ssa.dae.Ynet), inf);
testCase.verifyLessThan(f0, 1e-10, 'Padiyar AVR max|f| at equilibrium');
testCase.verifyLessThan(g0, 1e-10, 'Padiyar AVR max|g| at equilibrium');
testCase.verifyEqual(numel(ssa.dae.x0), 20, 'Padiyar AVR = 5 states x 4 machines');
testCase.verifyEqual(ssa.dae.ns, 5, 'Padiyar AVR states per machine');
testCase.verifyTrue(all(isfinite(ssa.dae.x0)) && all(isfinite(ssa.dae.y0)), 'all states finite');
end

function test_1c_emf6_equilibrium_and_count(testCase)
ssa = emf6_fixture();
f0 = norm(ssa.dae_f(ssa.init.x0, ssa.init.y0), inf);
g0 = norm(ssa.dae_g(ssa.init.x0, ssa.init.y0, ssa.Ynet), inf);
testCase.verifyLessThan(f0, 1e-10, 'EMF6 max|f| at equilibrium');
testCase.verifyLessThan(g0, 1e-10, 'EMF6 max|g| at equilibrium');
ng = ssa.init.ng;
testCase.verifyEqual(numel(ssa.init.x0), ng*6, 'EMF6 = 6 states x ng machines');
testCase.verifyTrue(all(isfinite(ssa.init.x0)) && all(isfinite(ssa.init.y0)), 'all states finite');
end

function test_2a_padiyar_sssa_ts_shared_dae(testCase)
% SSSA's DAE and a fresh DAE built the way TS builds it must give the SAME
% residual on the SAME (x, y) -- equilibrium and perturbed. This proves the
% equations (not just the equilibrium) are one function.
c = cases.case_padiyar_two_area_4m_avr();
ssa = stability.padiyar_model11_ssa(c, struct('excitation','avr','fd_eps',1e-6));
dae_ts = stability.padiyar_model11_dae(c, struct('excitation','avr'));
rf_s = norm(ssa.dae.dae_f(ssa.dae.x0, ssa.dae.y0), inf);
rf_d = norm(dae_ts.dae_f(dae_ts.x0, dae_ts.y0), inf);
testCase.verifyEqual(rf_s, rf_d, 'AbsTol', 1e-12, ...
    'Padiyar SSSA vs TS dae_f equilibrium residual');
rng(0,'twister');
xp = ssa.dae.x0 + 1e-3*randn(numel(ssa.dae.x0),1);
yp = ssa.dae.y0 + 1e-3*randn(numel(ssa.dae.y0),1);
testCase.verifyEqual(norm(ssa.dae.dae_f(xp,yp) - dae_ts.dae_f(xp,yp), inf), 0, ...
    'AbsTol', 1e-12, 'Padiyar SSSA vs TS dae_f on perturbed state');
testCase.verifyEqual( ...
    norm(ssa.dae.dae_g(xp,yp,ssa.dae.Ynet) - dae_ts.dae_g(xp,yp,dae_ts.Ynet), inf), 0, ...
    'AbsTol', 1e-12, 'Padiyar SSSA vs TS dae_g on perturbed state');
combined = norm([ssa.dae.dae_f(ssa.dae.x0, ssa.dae.y0); ...
                 ssa.dae.dae_g(ssa.dae.x0, ssa.dae.y0, ssa.dae.Ynet)], inf);
testCase.verifyEqual(dae_ts.initial_residual, combined, 'AbsTol', 1e-12, ...
    'Padiyar TS initial_dae_residual == shared DAE residual');
end

function test_2b_emf6_sssa_ts_shared_dae(testCase)
% EMF6: synchronous_emf6_ssa and emf6_dae (the TS-facing adapter) share the
% same equations. Compare residuals on the equilibrium and a perturbed state.
ssa = emf6_fixture();
c = ssa.case_data;
dae_ts = stability.emf6_dae(c, struct('load_model','cc_p_cz_q'));
rf_s = norm(ssa.dae_f(ssa.init.x0, ssa.init.y0), inf);
rf_d = norm(dae_ts.dae_f(dae_ts.init.x0, dae_ts.init.y0), inf);
testCase.verifyEqual(rf_s, rf_d, 'AbsTol', 1e-12, ...
    'EMF6 SSSA vs TS dae_f equilibrium residual');
rng(0,'twister');
xp = ssa.init.x0 + 1e-3*randn(numel(ssa.init.x0),1);
yp = ssa.init.y0 + 1e-3*randn(numel(ssa.init.y0),1);
testCase.verifyEqual(norm(ssa.dae_f(xp,yp) - dae_ts.dae_f(xp,yp), inf), 0, ...
    'AbsTol', 1e-12, 'EMF6 SSSA vs TS dae_f on perturbed state');
testCase.verifyEqual( ...
    norm(ssa.dae_g(xp,yp,ssa.Ynet) - dae_ts.dae_g(xp,yp,dae_ts.Ynet), inf), 0, ...
    'AbsTol', 1e-12, 'EMF6 SSSA vs TS dae_g on perturbed state');
end

function test_3_schur_complement_contract(testCase)
% Afull must equal Jxx - Jxy(:,free_y)*(Jyy(free_y,free_y)\Jyx(free_y,:))
% (backslash, NOT inv). Dimensions must be consistent. All blocks finite.
m1 = struct('name','Padiyar manual','ssa',padiyar_manual_fixture());
m2 = struct('name','Padiyar AVR','ssa',padiyar_avr_fixture());
m3 = struct('name','EMF6','ssa',emf6_fixture());
models = {m1, m2, m3};
for k = 1:numel(models)
    ssa = models{k}.ssa;
    Jxx = ssa.Jxx; Jxy = ssa.Jxy; Jyx = ssa.Jyx; Jyy = ssa.Jyy;
    fy = ssa.free_y;
    nx = size(Jxx,1); ny = size(Jyy,1);
    testCase.verifyEqual(size(Jxx,1), size(Jxx,2), ...
        sprintf('%s: Jxx square', models{k}.name));
    testCase.verifyEqual([size(Jxy,1), size(Jxy,2)], [nx, ny], ...
        sprintf('%s: Jxy is nx-by-ny', models{k}.name));
    testCase.verifyEqual([size(Jyx,1), size(Jyx,2)], [ny, nx], ...
        sprintf('%s: Jyx is ny-by-nx', models{k}.name));
    testCase.verifyEqual([size(Jyy,1), size(Jyy,2)], [ny, ny], ...
        sprintf('%s: Jyy square ny-by-ny', models{k}.name));
    testCase.verifyEqual([size(ssa.Afull,1), size(ssa.Afull,2)], [nx, nx], ...
        sprintf('%s: Afull is nx-by-nx', models{k}.name));
    testCase.verifyTrue(all(isfinite(Jxx(:))) && all(isfinite(Jxy(:))) && ...
        all(isfinite(Jyx(:))) && all(isfinite(Jyy(:))) && all(isfinite(ssa.Afull(:))), ...
        sprintf('%s: all Jacobian blocks + Afull finite', models{k}.name));
    A_recon = Jxx - Jxy(:,fy) * (Jyy(fy,fy) \ Jyx(fy,:));
    testCase.verifyLessThan(max(abs(ssa.Afull - A_recon),[],'all'), 1e-12, ...
        sprintf('%s: Afull == Jxx - Jxy*(Jyy\\Jyx) (Schur, backslash)', models{k}.name));
    rc = rcond(Jyy);
    testCase.verifyTrue(isfinite(rc) && rc > 0, ...
        sprintf('%s: rcond(Jyy) finite and positive (%.3e)', models{k}.name, rc));
end
end

function test_4_no_inv_jyy_in_production(testCase)
% Grep guard: production +stability/ must not contain inv(Jyy) or inv(J_yy).
% (pinv(T) for the COI reduction matrix is allowed -- it is not an algebraic
% elimination.)
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
stabdir = fullfile(root, '+stability');
files = dir(fullfile(stabdir, '*.m'));
violations = {};
for k = 1:numel(files)
    fid = fopen(fullfile(stabdir, files(k).name), 'r');
    txt = fread(fid, '*char')'; fclose(fid);
    lines = splitlines(txt);
    code = '';
    for j = 1:numel(lines)
        ln = strtrim(lines{j});
        cm = strfind(ln, '%');
        if ~isempty(cm), ln = ln(1:cm(1)-1); end
        code = [code, ln, sprintf('\n')]; %#ok<AGROW>
    end
    if ~isempty(regexpi(code, 'inv\s*\(\s*J_?yy'))
        violations{end+1} = files(k).name; %#ok<AGROW>
    end
end
testCase.verifyTrue(isempty(violations), ...
    sprintf('inv(Jyy) found in +stability/: %s', strjoin(violations, ', ')));
end

function test_5_eigenvalue_structure(testCase)
m1 = struct('name','Padiyar manual','ssa',padiyar_manual_fixture());
m2 = struct('name','Padiyar AVR','ssa',padiyar_avr_fixture());
m3 = struct('name','EMF6','ssa',emf6_fixture());
models = {m1, m2, m3};
for k = 1:numel(models)
    ssa = models{k}.ssa;
    lam = ssa.eigenvalues;
    testCase.verifyTrue(all(isfinite(lam)), ...
        sprintf('%s: all eigenvalues finite', models{k}.name));
    cmplx = lam(abs(imag(lam)) > 1e-9);
    if ~isempty(cmplx)
        matched = false(size(cmplx));
        for j = 1:numel(cmplx)
            d = abs(cmplx - conj(cmplx(j)));
            [dmin,idx] = min(d);
            if dmin < 1e-9 * (1 + abs(cmplx(j))), matched(j) = true; end
        end
        testCase.verifyTrue(all(matched), ...
            sprintf('%s: complex eigenvalues in conjugate pairs', models{k}.name));
    end
end
end

function test_6_reference_angle_structure(testCase)
% A common rotation of all rotor angles is a symmetry of the autonomous DAE:
% Afull*angle_shift ~ 0 (the reference-angle zero mode). This must hold for
% all three models. Tolerance 1e-5 covers central-FD Jacobian noise at h=1e-6
% (Padiyar path uses multimachine_ssa's FD Jacobian; angle_shift_residual ~1e-6
% is FD truncation, not a structural failure of the zero mode).
m1 = struct('name','Padiyar manual','ssa',padiyar_manual_fixture(),'sp',4);
m2 = struct('name','Padiyar AVR','ssa',padiyar_avr_fixture(),'sp',5);
m3 = struct('name','EMF6','ssa',emf6_fixture(),'sp',6);
models = {m1, m2, m3};
for k = 1:numel(models)
    ssa = models{k}.ssa; sp = models{k}.sp;
    testCase.verifyLessThan(ssa.angle_shift_residual, 1e-5, ...
        sprintf('%s: angle_shift_residual < 1e-5', models{k}.name));
    A = ssa.Afull;
    shift = zeros(size(A,1),1);
    shift(1:sp:end) = 1;
    testCase.verifyLessThan(norm(A*shift, inf), 1e-5, ...
        sprintf('%s: Afull*angle_shift ~ 0 (zero mode)', models{k}.name));
end
end

function test_7_modal_metrics(testCase)
% frequency_Hz, damping_ratio must be present and finite; time_constant is
% reported from the real part (finite where Re != 0).
m1 = struct('name','Padiyar manual','ssa',padiyar_manual_fixture());
m2 = struct('name','Padiyar AVR','ssa',padiyar_avr_fixture());
m3 = struct('name','EMF6','ssa',emf6_fixture());
models = {m1, m2, m3};
for k = 1:numel(models)
    ssa = models{k}.ssa;
    lam = ssa.eigenvalues;
    testCase.verifyTrue(isfield(ssa,'frequency_Hz') && all(isfinite(ssa.frequency_Hz)), ...
        sprintf('%s: frequency_Hz present and finite', models{k}.name));
    testCase.verifyTrue(isfield(ssa,'damping_ratio') && all(isfinite(ssa.damping_ratio)), ...
        sprintf('%s: damping_ratio present and finite', models{k}.name));
    re = real(lam);
    tau = -1 ./ re;
    nz = abs(re) > 1e-12;
    testCase.verifyTrue(all(isfinite(tau(nz))), ...
        sprintf('%s: time_constant finite for non-zero real parts', models{k}.name));
end
end
