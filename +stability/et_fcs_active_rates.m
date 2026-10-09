function out = et_fcs_active_rates(t, theta_rad, Vmag_pu, active_mask, opt)
%ET_FCS_ACTIVE_RATES  Causal rates for the ACTIVE PLL/GFM/SG angle columns.
%   OUT = ET_FCS_ACTIVE_RATES(T,THETA_RAD,VMAG_PU,ACTIVE_MASK,OPT) applies the
%   accepted-step causal estimator et_fcs_causal_rates column by column, over
%   one column per online angle-bearing resource:
%     * an SG column carries the rotor angle (or its speed-derived angle),
%     * a GFM column carries the VSG virtual angle,
%     * a GFL column carries the PLL angle.
%   The estimator is identical for all three; what makes it a "PLL rate" or an
%   "SG rate" is only WHICH column is being differenced. Columns marked
%   inactive are left all-NaN with valid=false (an offline resource has no
%   connected-grid frequency to rate).
%
%   T is n-by-1; THETA_RAD and VMAG_PU are n-by-m; ACTIVE_MASK is 1-by-m (or
%   m-by-1) logical. OPT is forwarded to et_fcs_causal_rates (nominal_hz,
%   warmup_s, min_dt, dup_tol).
%
%   Returns n-by-m matrices F_HZ, ROCOF_HZ_S, ROCOV_PU_S, VALID plus
%   FIRST_VALID_INDEX (1-by-m) and the shared method/classification metadata.
%   Duplicate event instants and rejected rollbacks are handled identically to
%   the scalar estimator (non-advancing dt -> NaN + invalid), so a caller that
%   feeds accepted samples gets causally correct active-device rates.

arguments
    t (:,1) double
    theta_rad double
    Vmag_pu double
    active_mask
    opt struct = struct()
end

n = numel(t);
if size(theta_rad,1) ~= n || size(Vmag_pu,1) ~= n
    error('stability:et_fcs_active_rates:lengthMismatch', ...
        'T must have one row per sample; THETA_RAD and VMAG_PU must be n-by-m.');
end
if size(theta_rad,2) ~= size(Vmag_pu,2)
    error('stability:et_fcs_active_rates:sizeMismatch', ...
        'THETA_RAD and VMAG_PU must have the same number of columns.');
end
m = size(theta_rad,2);
active = reshape(logical(active_mask),1,[]);
if numel(active) ~= m
    error('stability:et_fcs_active_rates:maskMismatch', ...
        'ACTIVE_MASK must have one entry per angle column.');
end

f_hz = nan(n,m); rocof = nan(n,m); rocov = nan(n,m); valid = false(n,m);
first_valid = nan(1,m);
for c = 1:m
    if ~active(c), continue; end
    r = stability.et_fcs_causal_rates(t, theta_rad(:,c), Vmag_pu(:,c), opt);
    f_hz(:,c) = r.f_hz; rocof(:,c) = r.rocof_hz_s; rocov(:,c) = r.rocov_pu_s;
    valid(:,c) = r.valid; first_valid(c) = r.first_valid_index;
end

out = struct('f_hz',f_hz,'rocof_hz_s',rocof,'rocov_pu_s',rocov,'valid',valid, ...
    'first_valid_index',first_valid,'active_mask',active,'t',t(:), ...
    'n_samples',n,'n_columns',m, ...
    'method','causal_backward_accepted_steps','classification','PROJECT_DERIVED', ...
    'causal',true);
end
