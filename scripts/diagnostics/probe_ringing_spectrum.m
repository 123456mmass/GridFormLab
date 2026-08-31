function probe_ringing_spectrum()
%PROBE_RINGING_SPECTRUM  Is the fixed-GFL island's motion a real damped mode,
% and does the accepted grid resolve it?
%
% Read-only.  The SSSA table for the SG-offline configuration puts the PLL
% modes at -0.5668 +/- j2.1321 s^-1, i.e. f = 0.339 Hz with zeta = 0.257 and a
% 1/|sigma| = 1.76 s decay.  If that is what the island shows, then a grid whose
% accepted spacing reaches 0.5 s is sampling a 0.34 Hz signal at barely twice
% Nyquist and cannot draw it, while a 0.05 s grid resolves it about 60x over.
% This probe measures the ringing directly on both grids rather than inferring
% it.
pf_init_paths();
d = fullfile('output','diagnostics','ieee14_locked_gfl_diag');
sets = { ...
  'adaptive dt<=0.50', fullfile(d,'locked_gfl_diag_gauge_thevenin_250s.mat'); ...
  'fixed    dt =0.05', fullfile(d,'locked_gfl_diag_gauge_thevenin_fine_250s.mat')};

for i = 1:size(sets,1)
    if ~isfile(sets{i,2}), fprintf('%s (absent)\n',sets{i,1}); continue; end
    S = load(sets{i,2}); r = S.result; t = r.t(:);
    b9 = find(r.bus_ids(:)'==9,1);
    V9 = abs(complex(r.y_traj(2*b9-1,:),r.y_traj(2*b9,:))).';
    fprintf('\n=== %s  (n=%d) ===\n',sets{i,1},numel(t));

    % Post-event ringing windows: each starts just after a disturbance and is
    % long enough to hold several cycles of a 0.34 Hz mode.
    for W = {[20.5 35],[50.2 62],[85.3 97],[110.2 122],[145.2 157]}
        a = W{1};
        w = t>=a(1) & t<=a(2);
        if sum(w) < 8, continue; end
        tw = t(w); vw = V9(w);
        % Detrend against the window's own settling level, then count zero
        % crossings of the residual: the crossing rate IS the mode frequency
        % when one mode dominates, and needs no transform or window function.
        base = vw(end);
        e = vw - base;
        zc = sum(e(1:end-1).*e(2:end) < 0);
        span = tw(end)-tw(1);
        fest = zc/(2*span);
        % Envelope decay: peak |e| in the first and last thirds.
        n = numel(e); i1 = 1:round(n/3); i3 = round(2*n/3):n;
        fprintf('  [%6.2f %6.2f] n=%4d  |e|max %.3e -> %.3e  zc=%2d  f~%.3f Hz  dt med %.4f\n', ...
            a(1),a(2),sum(w),max(abs(e(i1))),max(abs(e(i3))),zc,fest, ...
            median(diff(tw)));
    end
end
fprintf(['\nSSSA reference for this configuration: PLL pair -0.5668 +/- j2.1321 ' ...
         's^-1\n  => f = 0.3393 Hz, zeta = 0.2569, decay 1/|sigma| = %.2f s\n'], ...
        1/0.5668);
end
