function compare_fixed_gfl_arms()
%COMPARE_FIXED_GFL_ARMS  Ideal-DC against delivered-Thevenin all-GFL arm.
% Read-only.  Answers one question: does either arm carry real oscillation
% content in the islanded window, or is the accepted grid too coarse to show
% any that exists?
pf_init_paths();
files = { ...
  'ideal   ', fullfile('output','diagnostics','ieee14_locked_gfl_diag','locked_gfl_diag_gauge_250s.mat'); ...
  'thevenin', fullfile('output','diagnostics','ieee14_locked_gfl_diag','locked_gfl_diag_gauge_thevenin_250s.mat')};
for i = 1:size(files,1)
    S = load(files{i,2});
    r = S.result; t = r.t(:);
    b9 = find(r.bus_ids(:)'==9,1);
    V9 = abs(complex(r.y_traj(2*b9-1,:),r.y_traj(2*b9,:))).';
    dt = diff(t);
    isl = t>=20 & t<=145;
    w1 = t>=25  & t<=45;
    w2 = t>=100 & t<=109;
    fprintf('%s  n=%4d  dt med %.4f max %.4f\n',files{i,1},numel(t),median(dt),max(dt));
    fprintf('          island V9 %.6f..%.6f\n',min(V9(isl)),max(V9(isl)));
    fprintf('          25-45  ptp %.4e   100-109 ptp %.4e\n', ...
        max(V9(w1))-min(V9(w1)),max(V9(w2))-min(V9(w2)));
    % Vdc excursion tells us whether the DC closure is being worked.
    devs = r.equilibrium.devices;
    nx = [devs.nx]; xo = cumsum([0 nx(1:end-1)]);
    cv = find(r.device_bus_ids(:)' ~= 1);
    vdc = r.x_traj(xo(cv(1))+3,:);
    fprintf('          IBR2 Vdc %.6f..%.6f  (island %.6f..%.6f)\n', ...
        min(vdc),max(vdc),min(vdc(isl)),max(vdc(isl)));
end
end
