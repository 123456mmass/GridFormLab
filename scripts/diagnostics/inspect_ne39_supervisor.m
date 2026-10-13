function inspect_ne39_supervisor(folder)
%INSPECT_NE39_SUPERVISOR Read-only report of the post-reclose supervisor state.
% Prints the severity/rate decisions after the reclose so the reason the IBRs
% were (or were not) released to GFL is visible from the run's own evidence.
arguments
    folder (1,1) string
end
d = load(fullfile(folder,'raw.mat'));
r = d.result;
fprintf('reclose=%s at %.6f\n',char(string(r.reclose_status)),r.actual_reclose_time);
fprintf('reselection_status=%s\n',char(string(r.reselection_status)));
fprintf('handback_status=%s handback_start=%g duration=%g complete=%g\n', ...
    char(string(r.handback_status)),r.handback_start_time, ...
    r.handback_duration_s,r.handback_complete_time);
if isfield(r,'reselection_rejection_detail')
    fprintf('rejection_detail:\n');
    disp(r.reselection_rejection_detail);
end
dl = r.ne39_decision_log;
fprintf('ne39_decision_log entries=%d\n',numel(dl));
if isempty(dl), return; end
ts = cellfun(@(x)x.t,dl);
ix = find(ts>=r.actual_reclose_time);
fprintf('decisions at/after reclose=%d\n',numel(ix));
fprintf('%-10s %-6s %-34s %-7s %-7s %-8s %-9s %-9s\n', ...
    't','valid','reason','augm','rel','sev_max','rocof','rocov');
show = unique([ix(1:min(10,numel(ix))), ix(max(1,numel(ix)-5):numel(ix))]);
for k = unique(show).'
    q = dl{k};
    sev = NaN; rf = NaN; rv = NaN;
    if isfield(q,'sample')
        s = q.sample;
        if isfield(s,'severity') && ~isempty(s.severity),  sev = max(s.severity); end
        if isfield(s,'rocof_hz_s') && ~isempty(s.rocof_hz_s), rf = max(abs(s.rocof_hz_s)); end
        if isfield(s,'rocov_pu_s') && ~isempty(s.rocov_pu_s), rv = max(abs(s.rocov_pu_s)); end
    end
    fprintf('%-10.4f %-6d %-34s %-7d %-7d %-8.5f %-9.4f %-9.4f\n', ...
        q.t,q.valid,q.reason,q.augment,q.release,sev,rf,rv);
end
% Which condition blocked the release? Report the last decision's inputs
% against the policy ceilings, plus validity, without re-deriving any gate.
q = dl{end};
fprintf('\nLAST DECISION at t=%.4f\n',q.t);
fprintf('  valid=%d reason=%s augment=%d release=%d\n',q.valid,q.reason,q.augment,q.release);
if isfield(q,'sample')
    s = q.sample;
    fprintf('  n_online=%d\n',numel(s.severity));
    if isfield(s,'severity') && ~isempty(s.severity),    fprintf('  severity   = %s\n',mat2str(s.severity,4)); end
    if isfield(s,'rocof_hz_s') && ~isempty(s.rocof_hz_s),fprintf('  rocof_hz_s = %s\n',mat2str(s.rocof_hz_s,4)); end
    if isfield(s,'rocov_pu_s') && ~isempty(s.rocov_pu_s),fprintf('  rocov_pu_s = %s\n',mat2str(s.rocov_pu_s,4)); end
    if isfield(s,'v_pu') && ~isempty(s.v_pu),            fprintf('  v_pu       = %s\n',mat2str(s.v_pu,6)); end
    if isfield(s,'f_hz') && ~isempty(s.f_hz),            fprintf('  f_hz       = %s\n',mat2str(s.f_hz,6)); end
    if isfield(s,'valid') && ~isempty(s.valid),          fprintf('  per-dev valid = %s\n',mat2str(s.valid)); end
end
if isfield(r,'ne39_policy')
    p = r.ne39_policy;
    fprintf('\nPOLICY (kernel defaults unless overridden)\n');
    fprintf('  si_on=%g si_off=%g rocof_max=%g rocov_max=%g\n', ...
        p.si_on,p.si_off,p.rocof_max,p.rocov_max);
    fprintf('  v_min=%g v_max=%g f_min=%g f_max=%g horizon=%g on_dwell=%g off_dwell=%g\n', ...
        p.v_min,p.v_max,p.f_min,p.f_max,p.prediction_horizon,p.on_dwell,p.off_dwell);
end
% Count how the decisions were classified over the whole post-reclose window
reasons = cellfun(@(x)x.reason,dl(ix),'UniformOutput',false);
[u,~,ic] = unique(reasons);
fprintf('\nPOST-RECLOSE REASON HISTOGRAM\n');
for k=1:numel(u)
    fprintf('  %-34s %d\n',u{k},nnz(ic==k));
end
end
