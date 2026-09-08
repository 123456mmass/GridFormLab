pf_init_paths();
S = load(fullfile('output','diagnostics','ieee14_locked_gfl_diag','ripple_sweep.mat'));
% rerun is cheap (50 s horizon); instead dump raw V9 windows from a single
% fixed-grid probe is overkill -- print per-run decile bands of V9 instead,
% which separate a sine-like ring from rail-to-rail spiking.
for k = 1:numel(S.out)
  o = S.out(k);
  fprintf('kp=%.3f ki=%.1f ptp=%.4f std=%.4f ring=%.3f cross=%d\n', ...
    o.kpPLL, o.kiPLL, o.V9_ptp, o.V9_std, o.f_ring_Hz, o.n_crossings);
end
