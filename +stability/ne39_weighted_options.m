function resolved = ne39_weighted_options(opt)
%NE39_WEIGHTED_OPTIONS  Validate the opt-in weighted NE39 supervisor options.
%   RESOLVED = ne39_weighted_options(OPT) returns a struct describing whether
%   the weighted four-term severity is enabled and, if so, its validated
%   weights and bases.  OPT is the caller option struct (may be empty).
%
%   Omission contract: when opt.ne39_weighted_severity is absent or false,
%   RESOLVED.enabled is false and no weighted field is consulted. The legacy
%   two-term COI scalar then remains in force unchanged.
%
%   Opt-in keys (all optional except enabled):
%     ne39_weighted_severity  logical scalar, default false
%     ne39_severity_weights   1x4 [wV wf wrf wrv], must sum to 1
%     ne39_severity_bases     1x4 [V_pu f_Hz rocof_Hz_s rocov_pu_s]
%     ne39_severity_weights/bases default to the PROJECT_DERIVED study design
%     (unvalidated) when enabled but not supplied.
%
%   Threshold/dwell pairs are checked by ne39_resolve_threshold_pairs, which
%   errors on any conflicting explicit spelling instead of picking one.

arguments
    opt struct = struct()
end

resolved = struct('enabled',false,'weights',[],'bases',[], ...
    'classification','PROJECT_DERIVED_UNVALIDATED');
if ~isfield(opt,'ne39_weighted_severity') || isempty(opt.ne39_weighted_severity)
    return;
end
enabled = opt.ne39_weighted_severity;
if ~(islogical(enabled) || isnumeric(enabled)) || ~isscalar(enabled) || ...
        ~(enabled==0 || enabled==1)
    error('stability:ne39_weighted_options:badFlag', ...
        'ne39_weighted_severity must be a logical scalar.');
end
if ~logical(enabled)
    return;
end

weights = [.35 .35 .15 .15];
bases   = [.10 .50 1 1];
if isfield(opt,'ne39_severity_weights') && ~isempty(opt.ne39_severity_weights)
    weights = opt.ne39_severity_weights;
end
if isfield(opt,'ne39_severity_bases') && ~isempty(opt.ne39_severity_bases)
    bases = opt.ne39_severity_bases;
end
if ~isnumeric(weights) || ~isreal(weights) || ~isequal(size(weights),[1 4]) || ...
        any(~isfinite(weights)) || any(weights<0) || abs(sum(weights)-1)>1e-9
    error('stability:ne39_weighted_options:badWeights', ...
        'ne39_severity_weights must be a finite nonnegative 1x4 vector summing to 1.');
end
if ~isnumeric(bases) || ~isreal(bases) || ~isequal(size(bases),[1 4]) || ...
        any(~isfinite(bases)) || any(bases<=0)
    error('stability:ne39_weighted_options:badBases', ...
        'ne39_severity_bases must be a finite positive 1x4 vector.');
end

resolved.enabled = true;
resolved.weights = double(weights);
resolved.bases = double(bases);
end
