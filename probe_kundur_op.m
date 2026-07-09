function probe_kundur_op()
%PROBE_KUNDUR_OP Dump operating-point quantities to verify per-unit base
%consistency between the swing equation (H, Tm, Te) and the network.
pf_init_paths;
case_data = cases.case_kundur_two_area_classical();
pf_opts = struct('plot_results', false, 'verbose', false, 'max_iter', 50, ...
    'tolerance', 1e-8, 'enforce_q_limits', false);
pf = pfsolver.powerflow_newton_raphson(case_data, pf_opts);
% Use constant-impedance load (closest to Kundur frequencies).
ssa_opts = struct('load_model','cz');
ssa = stability.kundur_ex126_sauer_pai_ssa('pf', pf, 'options', ssa_opts);
init = ssa.init;

Sbase = case_data.base_values.S_base_MVA;   % 100
Sm = case_data.machines.base.S_MVA;          % 900
fprintf('Sbase=%g MVA, Sm=%g MVA, zb_scale=%g\n', Sbase, Sm, init.zb_scale);

% Power-flow generation (on 100 MVA base).
fprintf('\n%-4s %9s %9s %9s %9s %9s %9s\n', ...
    'gen','Pgen_pf','Qgen_pf','Te','Tm','Pgen*9','Te*Sm/Sb');
for k=1:init.ng
    bidx = init.bus_idx(k);
    Pgen = pf.P_generation(bidx);   % pu on 100 MVA
    Qgen = pf.Q_generation(bidx);
    fprintf('%-4s %9.4f %9.4f %9.4f %9.4f %9.4f %9.4f\n', ...
        case_data.machines.units(k).gen_id, Pgen, Qgen, ...
        init.Tm(k), init.Tm(k), Pgen*(Sm/Sbase), init.Tm(k)*(Sm/Sbase));
end

fprintf('\nIf Te is on 100 MVA base, then Te*9 should equal Pgen on 900 MVA base.\n');
fprintf('If Te is on 900 MVA base, then Te should equal Pgen*9.\n');

% Check the swing equation coefficient: 2H_sys with H_sys on 100 MVA base.
fprintf('\nH_sys (100 MVA base) = '); fprintf('%.3f ', init.H_sys); fprintf('\n');
fprintf('2*H_sys = '); fprintf('%.3f ', 2*init.H_sys); fprintf('\n');
fprintf('For the swing eqn (Tm-Te)/(2H) to give correct freq, Tm,Te must be on 100 MVA base.\n');

% Eigenvalues with cz load.
lam = ssa.eigenvalues(:);
[~,idx]=sort(real(lam),'descend'); lam=lam(idx);
fprintf('\nTop 12 eigenvalues (cz load):\n');
for k=1:12
    fprintf('  %12.6f %+12.6fj  f=%.4f zeta=%.4f\n', real(lam(k)), imag(lam(k)), ...
        abs(imag(lam(k)))/(2*pi), -real(lam(k))/(abs(lam(k))+eps));
end
end
