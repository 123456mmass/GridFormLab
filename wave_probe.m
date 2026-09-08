pf_init_paths();
S = load(fullfile('output','diagnostics','ieee14_locked_gfl_diag','ripple_sweep.mat'));
fprintf('rows=%d\n', numel(S.out));
for k = 1:numel(S.out)
  o = S.out(k);
  fprintf('kp=%.3f ki=%.1f conv=%d n=%d ptp=%.4f std=%.4f ring=%.3f cross=%d fail=%s\n', ...
    o.kpPLL, o.kiPLL, o.converged, o.n, o.V9_ptp, o.V9_std, o.f_ring_Hz, o.n_crossings, o.failure_id);
end
