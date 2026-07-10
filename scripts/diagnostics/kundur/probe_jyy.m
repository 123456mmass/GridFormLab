function probe_jyy()
%PROBE_JYY Inspect Jyy conditioning and the spurious -299 mode.
pf_init_paths;
case_data = cases.case_kundur_two_area_classical();
pf_opts = struct('plot_results', false, 'verbose', false, 'max_iter', 50, ...
    'tolerance', 1e-8, 'enforce_q_limits', false);
pf = pfsolver.powerflow_newton_raphson(case_data, pf_opts);
opts = struct('load_model','cc_p_cz_q');
ssa = stability.kundur_ex126_sauer_pai_ssa('pf', pf, 'options', opts);
init = ssa.init;
Jyy = ssa.Jyy; Jyx = ssa.Jyx; Jxy = ssa.Jxy; Jxx = ssa.Jxx;
free_y = ssa.free_y;
names = init.algebraic_names;
fprintf('Jyy size %dx%d, cond(Jyy) = %.4e, rcond = %.4e\n', size(Jyy,1), size(Jyy,2), cond(Jyy), rcond(Jyy));
fprintf('cond(Jyy(free,free)) = %.4e, rcond = %.4e\n', cond(Jyy(free_y,free_y)), rcond(Jyy(free_y,free_y)));
sv = svd(Jyy(free_y,free_y));
fprintf('Smallest 6 singular values of Jyy(free,free):\n');
for k=1:6; fprintf('  %12.4e\n', sv(end-k+1)); end
% Right singular vector of smallest sv
[U,~,V] = svd(Jyy(free_y,free_y));
v_small = V(:,end);
fprintf('\nRight singular vector of smallest sv (|v|>0.1):\n');
for k=1:numel(v_small)
    if abs(v_small(k)) > 0.1
        fprintf('  %s : %+8.4f\n', names{free_y(k)}, v_small(k));
    end
end
% Left singular vector (which equation is degenerate)
u_small = U(:,end);
fprintf('\nLeft singular vector of smallest sv (|u|>0.1) -> degenerate equation:\n');
for k=1:numel(u_small)
    if abs(u_small(k)) > 0.1
        fprintf('  eq for %s : %+8.4f\n', names{free_y(k)}, u_small(k));
    end
end
% Ared and the -299 mode
Ared_full = Jxx - Jxy(:,free_y) * (Jyy(free_y,free_y) \ Jyx(free_y,:));
lam = eig(Ared_full);
[~,idx]=sort(real(lam));
fprintf('\nAred_full eigenvalues (most negative real first, first 6):\n');
for k=1:6
    fprintf('  %+10.4f %+10.4fj\n', real(lam(idx(k))), imag(lam(idx(k))));
end
% Compare: pseudo-inverse vs backslash
Ared_pinv = Jxx - Jxy(:,free_y) * (pinv(Jyy(free_y,free_y)) * Jyx(free_y,:));
lam2 = eig(Ared_pinv);
[~,idx2]=sort(real(lam2));
fprintf('\nWith pinv(Jyy) instead of backslash (first 6 most negative):\n');
for k=1:6
    fprintf('  %+10.4f %+10.4fj\n', real(lam2(idx2(k))), imag(lam2(idx2(k))));
end
end
