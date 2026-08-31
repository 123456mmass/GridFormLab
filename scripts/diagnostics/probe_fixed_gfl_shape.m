function probe_fixed_gfl_shape()
%PROBE_FIXED_GFL_SHAPE  What does the fixed all-GFL arm genuinely do in the
% islanded window?  Read-only; writes nothing.
pf_init_paths();
S = load(fullfile('output','diagnostics','ieee14_locked_gfl_diag', ...
    'locked_gfl_diag_gauge_250s.mat'));
r = S.result; t = r.t(:);
b9 = find(r.bus_ids(:)'==9,1);
V9 = abs(complex(r.y_traj(2*b9-1,:),r.y_traj(2*b9,:))).';

fprintf('--- V9 every ~1 s from 20 to 52 s ---\n');
for tt = 20:1:52
    [~,j] = min(abs(t-tt));
    fprintf('  t=%7.3f  V9=%.6f\n',t(j),V9(j));
end
fprintf('--- ringing character, window 21..50 ---\n');
w = t>=21 & t<=50;
tw = t(w); vw = V9(w);
dv = diff(vw);
sgn = sign(dv); sgn(sgn==0) = 1;
nturn = sum(diff(sgn)~=0);
fprintf('  n=%d  turning points=%d  ptp=%.4e  first=%.6f last=%.6f\n', ...
    numel(vw),nturn,max(vw)-min(vw),vw(1),vw(end));
fprintf('--- after fault clear (85.15..95) and after line trip (110..120) ---\n');
for rng = {[85.15 95],[110 120],[145 158]}
    a = rng{1};
    w2 = t>=a(1) & t<=a(2);
    vv = V9(w2);
    dvv = diff(vv); s2 = sign(dvv); s2(s2==0)=1;
    fprintf('  [%6.2f %6.2f] n=%3d ptp=%.4e turns=%d\n', ...
        a(1),a(2),sum(w2),max(vv)-min(vv),sum(diff(s2)~=0));
end
end
