function c = ieee14_arm_common_window(rA,rB,t_split,opts)
%IEEE14_ARM_COMMON_WINDOW  Pairwise comparison over the window both arms possess.
%
%   c = ieee14_arm_common_window(rA, rB, t_split)
%
% Compares two arms ONLY on [0, t_split), the interval before the event where
% their control policies first differ. This is the block that carries the
% scientific weight of the whole study: if the two trajectories agree to
% numerical tolerance right up to the branch point, then the entire observed
% difference afterwards is attributable to the policy and to nothing else -- same
% power flow, same equilibrium, same integrator, same events, same states.
% Without this check the study is two runs that differ in unknown ways.
%
% Nothing outside the common window is compared. Whole-run extrema, integrals and
% switch counts are deliberately absent: an arm ending at t = 20 s and an arm
% ending at t = 250 s are exposed to different disturbances, so comparing them
% measures horizon length, not control performance.
%
% Duplicate sample times (an event publishes a left and a right limit at the same
% instant) are resolved to the committed right limit, exactly as
% generate_ieee14_handback_comparison.m:122-134 does. No interpolation, smoothing
% or resampling anywhere.
%
% Classification: ASSUMED_DIAGNOSTIC comparison metric.

arguments
    rA struct
    rB struct
    t_split (1,1) double
    opts.label_a (1,1) string = "A"
    opts.label_b (1,1) string = "B"
end

c = struct( ...
    'label_a',char(opts.label_a),'label_b',char(opts.label_b), ...
    'split_time_s',t_split,'n_common',0, ...
    'max_abs_x',NaN,'max_abs_y',NaN,'max_abs_u',NaN, ...
    'max_abs_P',NaN,'max_abs_Q',NaN,'max_abs_I',NaN, ...
    'comparison_tolerance',NaN,'identical_to_tolerance',false, ...
    'bit_identical',false, ...
    'min_V_a',NaN,'min_V_b',NaN, ...
    'max_abs_df_a',NaN,'max_abs_df_b',NaN, ...
    'window',[0 t_split], ...
    'classification','ASSUMED_DIAGNOSTIC', ...
    'note','');

if ~isfinite(t_split)
    c.note = 'split time is not finite; no common window defined';
    return;
end

[ta,ka] = right_continuous(rA);
[tb,kb] = right_continuous(rB);
if isempty(ta) || isempty(tb)
    c.note = 'one arm published no samples';
    return;
end
common = intersect(ta(ta < t_split),tb(tb < t_split),'stable');
c.n_common = numel(common);
if isempty(common)
    c.note = 'no shared sample time below the split';
    return;
end
[~,ia] = ismember(common,ta); ia = ka(ia);
[~,ib] = ismember(common,tb); ib = kb(ib);

c.max_abs_x = pair_max(rA,rB,'x_traj',ia,ib);
c.max_abs_y = pair_max(rA,rB,'y_traj',ia,ib);
c.max_abs_u = pair_max(rA,rB,'u_history',ia,ib);
c.max_abs_P = pair_max(rA,rB,'device_P_pu',ia,ib);
c.max_abs_Q = pair_max(rA,rB,'device_Q_pu',ia,ib);
c.max_abs_I = pair_max(rA,rB,'device_currents',ia,ib);

ra = max_finite_residual(rA); rb = max_finite_residual(rB);
scale = 1;
if isfield(rA,'x_traj') && isfield(rB,'x_traj')
    scale = max(1,max(abs([rA.x_traj(:);rB.x_traj(:)])));
end
c.comparison_tolerance = max([100*eps(scale),10*ra,10*rb]);

d = [c.max_abs_x c.max_abs_y c.max_abs_u c.max_abs_P c.max_abs_Q c.max_abs_I];
d = d(isfinite(d));
c.identical_to_tolerance = ~isempty(d) && all(d <= c.comparison_tolerance);
c.bit_identical = ~isempty(d) && all(d == 0);

c.min_V_a = window_min_V(rA,ia);
c.min_V_b = window_min_V(rB,ib);
c.max_abs_df_a = window_max_df(rA,ia);
c.max_abs_df_b = window_max_df(rB,ib);
end

% ==========================================================================
function [t,keep] = right_continuous(r)
%RIGHT_CONTINUOUS  At a duplicate event time keep the committed right limit.
t = []; keep = [];
if ~isfield(r,'t') || isempty(r.t), return; end
t0 = r.t(:);
if isfield(r,'sample_side') && numel(r.sample_side) == numel(t0)
    side = string(r.sample_side(:));
else
    side = repmat("left",numel(t0),1);
end
[ut,~,grp] = unique(t0,'stable');
keep = zeros(numel(ut),1);
for k = 1:numel(ut)
    q = find(grp == k);
    qr = q(side(q) == "right");
    if isempty(qr), keep(k) = q(end); else, keep(k) = qr(end); end
end
t = t0(keep);
end

function v = pair_max(a,b,name,ia,ib)
v = NaN;
if ~isfield(a,name) || ~isfield(b,name), return; end
A = a.(name); B = b.(name);
if isempty(A) || isempty(B), return; end
if size(A,1) ~= size(B,1), return; end
if max(ia) > size(A,2) || max(ib) > size(B,2), return; end
v = max(abs(A(:,ia)-B(:,ib)),[],'all');
end

function v = max_finite_residual(r)
v = 0;
if isfield(r,'accepted_residual_per_step')
    z = r.accepted_residual_per_step;
    z = z(isfinite(z));
    if ~isempty(z), v = max(z); end
end
end

function v = window_min_V(r,idx)
v = NaN;
if ~isfield(r,'bus_voltage_magnitude') || isempty(r.bus_voltage_magnitude), return; end
V = r.bus_voltage_magnitude;
if max(idx) > size(V,2), return; end
W = V(:,idx); W = W(isfinite(W));
if ~isempty(W), v = min(W); end
end

function v = window_max_df(r,idx)
v = NaN;
if ~isfield(r,'coi_frequency_Hz') || isempty(r.coi_frequency_Hz), return; end
f = r.coi_frequency_Hz(:);
if max(idx) > numel(f), return; end
w = f(idx); w = w(isfinite(w));
if ~isempty(w), v = max(abs(w-60)); end
end
