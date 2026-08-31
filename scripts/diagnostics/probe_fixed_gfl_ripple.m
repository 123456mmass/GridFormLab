function probe_fixed_gfl_ripple()
%PROBE_FIXED_GFL_RIPPLE  Measure whether the fixed all-GFL diagnostic arm
% actually oscillates, or whether the accepted grid is simply too coarse to
% show it.  Read-only probe; writes nothing.
pf_init_paths();
f = fullfile('output','diagnostics','ieee14_locked_gfl_diag', ...
    'locked_gfl_diag_gauge_250s.mat');
S = load(f);
r = S.result;
t = r.t(:);
b9 = find(r.bus_ids(:)'==9,1);
V9 = abs(complex(r.y_traj(2*b9-1,:),r.y_traj(2*b9,:))).';

dt = diff(t);
fprintf('samples          %d  over %.4f s\n',numel(t),t(end));
fprintf('dt  min/med/max  %.6f / %.6f / %.6f s\n',min(dt),median(dt),max(dt));
isl = t>=20 & t<=145;
fprintf('island samples   %d   dt med %.6f\n',sum(isl),median(diff(t(isl))));

% Sample-to-sample ripple inside the settled island window.
w = t>=100 & t<=109;
fprintf('window 100-109 s : n=%d  V9 %.6f..%.6f  ptp %.3e  std %.3e\n', ...
    sum(w),min(V9(w)),max(V9(w)),max(V9(w))-min(V9(w)),std(V9(w)));
w2 = t>=25 & t<=45;
fprintf('window  25-45  s : n=%d  V9 %.6f..%.6f  ptp %.3e  std %.3e\n', ...
    sum(w2),min(V9(w2)),max(V9(w2)),max(V9(w2))-min(V9(w2)),std(V9(w2)));

% Frequency the converters measure, sign of any ringing.
devs = r.equilibrium.devices;
nx = [devs.nx]; nu = [devs.nu];
xo = cumsum([0 nx(1:end-1)]); uo = cumsum([0 nu(1:end-1)]);
cv = find(r.device_bus_ids(:)' ~= 1);
fcv = nan(numel(t),numel(cv));
for j = 1:numel(t)
    ec = r.event_context_history{j};
    for m = 1:numel(cv)
        k = cv(m);
        o = devs(k).reconstruct(t(j),r.x_traj(xo(k)+(1:nx(k)),j), ...
            r.y_traj(:,j),r.u_history(uo(k)+(1:nu(k)),j),ec);
        if isfield(o,'gfm'), fcv(j,m) = 60*(1+o.gfm.omega_m);
        elseif isfield(o,'gfl'), fcv(j,m) = 60*o.gfl.omega_PLL_pu; end
    end
end
fprintf('f_conv island    %.6f .. %.6f Hz   ptp in 100-109 s %.3e\n', ...
    min(fcv(isl,:),[],'all'),max(fcv(isl,:),[],'all'), ...
    max(fcv(w,:),[],'all')-min(fcv(w,:),[],'all'));

% Rejected steps tell us whether the stepper was fighting anything.
if isfield(r,'rejected_steps')
    fprintf('rejected steps   %d\n',numel(r.rejected_steps));
end
if isfield(r,'n_rejected'), fprintf('n_rejected       %d\n',r.n_rejected); end
fprintf('converged %d  failure %s\n',logical(r.converged), ...
    char(string(r.failure_id)));
end
