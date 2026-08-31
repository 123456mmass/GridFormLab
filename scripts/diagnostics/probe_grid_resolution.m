function probe_grid_resolution()
%PROBE_GRID_RESOLUTION  How much oscillation does each accepted grid resolve?
%
% Compares the delivered adaptive-grid fixed-GFL cache against the uniform
% dt=0.05 s re-integration of the SAME equations.  The question is whether the
% flat-looking islanded window is physically flat or merely under-sampled by
% the error controller.
pf_init_paths();
d = fullfile('output','diagnostics','ieee14_locked_gfl_diag');
sets = { ...
  'adaptive/ideal ', fullfile(d,'locked_gfl_diag_gauge_250s.mat'); ...
  'adaptive/thev  ', fullfile(d,'locked_gfl_diag_gauge_thevenin_250s.mat'); ...
  'fixed/thev     ', fullfile(d,'locked_gfl_diag_gauge_thevenin_fine_250s.mat')};
wins = {[20 50],[50 85],[85.15 110],[110 145],[100 109]};

for i = 1:size(sets,1)
    if ~isfile(sets{i,2}), fprintf('%s  (absent)\n',sets{i,1}); continue; end
    S = load(sets{i,2}); r = S.result; t = r.t(:);
    b9 = find(r.bus_ids(:)'==9,1);
    V9 = abs(complex(r.y_traj(2*b9-1,:),r.y_traj(2*b9,:))).';
    dt = diff(t);
    fprintf('%s n=%5d  dt med %.4f max %.4f\n',sets{i,1},numel(t), ...
        median(dt),max(dt));
    for k = 1:numel(wins)
        a = wins{k}; w = t>=a(1) & t<=a(2);
        vv = V9(w); dvv = diff(vv); s = sign(dvv); s(s==0)=1;
        fprintf('    [%6.2f %6.2f] n=%4d  ptp %.4e  turns %3d  std %.3e\n', ...
            a(1),a(2),sum(w),max(vv)-min(vv),sum(diff(s)~=0),std(vv));
    end
end
end
