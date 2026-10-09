function [gates_out, dwell_out] = et_fcs_rate_gates(rates, gates, opt)
%ET_FCS_RATE_GATES  Independent SI/ROCOF/ROCOV gates + release dwell.
%   [G,D] = ET_FCS_RATE_GATES(RATES,GATES,OPT) evaluates the three frequency
%   protection quantities INDEPENDENTLY against their own limits. No quantity is
%   folded into another: a frequency excursion does not imply a RoCoF violation
%   and vice versa, so each gate is reported (and may fire) on its own evidence.
%
%   RATES is the struct returned by et_fcs_causal_rates: fields f_hz,
%   rocof_hz_s, rocov_pu_s, valid (per-sample logical), t is not carried, so the
%   caller passes the sample time vector through OPT.t (or via RATES.t if set).
%
%   GATES (CASE_DEFINED, mandatory scalars):
%     f_min, f_max      frequency band [Hz]
%     rocof_max         |RoCoF| ceiling [Hz/s]
%     rocov_max         |RoCoV| ceiling [pu/s]
%   OPT:
%     t        [required for dwell] sample time vector (same length as valid)
%     dwell_s  [0.20] continuous-assertion window before a release is proposed
%
%   Per-sample gate flags are ANDed with RATES.valid, so an unwarmed or
%   non-advancing sample can never assert a gate. The release (G.combined) is
%   only proposed once at least one gate has held continuously for dwell_s; a
%   single sample does not trigger a handback.

arguments
    rates struct
    gates struct
    opt struct = struct()
end

f = rates.f_hz(:); rocof = rates.rocof_hz_s(:); rocov = rates.rocov_pu_s(:);
valid = rates.valid(:);
n = numel(valid);

require_scalar(gates,'f_min'); require_scalar(gates,'f_max');
require_scalar(gates,'rocof_max'); require_scalar(gates,'rocov_max');

under = valid & (f < gates.f_min);
over  = valid & (f > gates.f_max);
freq_gate = under | over;
rocof_gate = valid & (abs(rocof) > gates.rocof_max);
rocov_gate = valid & (abs(rocov) > gates.rocov_max);
combined = freq_gate | rocof_gate | rocov_gate;

gates_out = struct('under_frequency',under,'over_frequency',over, ...
    'frequency_gate',freq_gate,'rocof_gate',rocof_gate,'rocov_gate',rocov_gate, ...
    'combined',combined,'valid',valid,'n_samples',n, ...
    'gates',gates,'classification','PROJECT_DERIVED');

dwell_s = 0.20;
if isfield(opt,'dwell_s') && ~isempty(opt.dwell_s), dwell_s = double(opt.dwell_s); end
if isfield(opt,'t') && ~isempty(opt.t)
    t = opt.t(:);
elseif isfield(rates,'t') && ~isempty(rates.t)
    t = rates.t(:);
else
    t = (0:n-1)';                            % index clock; dwell in sample units*dt unknown
    if n > 1, t = t * 0.05; end              % nominal fallback only when t absent
end

[proposal_index, released, held_s] = release_dwell(t, combined, dwell_s);
dwell_out = struct('proposal_index',proposal_index,'released',released, ...
    'held_s',held_s,'dwell_s',dwell_s,'triggered',any(combined), ...
    'classification','PROJECT_DERIVED');
end

function [idx, released, held_s] = release_dwell(t, assert_mask, dwell_s)
% First sample index by which ASSERT_MASK has held continuously for DWELL_S.
% Duplicate/non-advancing times do not reset an already-satisfied window (the
% assertion is about elapsed SIM time, not sample count). Returns []=none.
idx = []; released = false; held_s = 0;
n = numel(assert_mask);
if n == 0, return; end
run_start = NaN;
for k = 1:n
    if ~assert_mask(k)
        run_start = NaN;
        continue;
    end
    if isnan(run_start), run_start = k; end
    held_s = t(k) - t(run_start);
    if held_s >= dwell_s
        idx = k; released = true; return;
    end
end
end

function require_scalar(s,name)
if ~isfield(s,name) || ~isnumeric(s.(name)) || ~isscalar(s.(name)) || ~isfinite(s.(name))
    error('stability:et_fcs_rate_gates:missingGate', ...
        'CASE_DEFINED finite scalar gate "%s" is mandatory.',name);
end
end
