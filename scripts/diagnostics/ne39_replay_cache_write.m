function note = ne39_replay_cache_write(folder, result, request, elapsed)
%NE39_REPLAY_CACHE_WRITE Compact presentation view of a completed NE39 run.
%
%   NOTE = ne39_replay_cache_write(FOLDER, RESULT, REQUEST, ELAPSED)
%
% Writes <FOLDER>/replay_cache.mat holding only the traces and scalars a
% presentation replay needs from a stability.run_hybrid_case result.
%
% Why it exists
% -------------
% A finished NE39 chronology writes raw.mat of ~1-2 GB. On this host MATLAB
% needs ~390 s to load that file and ~760 s merely to list its variables
% (measured, MATLAB R2026b), because both walk the whole result struct. That is
% unusable when showing a result to an audience.
%
% This function is normally called by scripts/diagnostics/ne39_reclose_applied_probe.m
% immediately after raw.mat is saved, while the arrays are still decoded, so it
% costs one pass over data already in memory. It can also be called later on a
% stored raw.mat via scripts/diagnostics/ne39_reclose_build_cache.m.
%
% It computes nothing and decides nothing: every value is copied from RESULT and
% REQUEST. It relaxes no gate and re-runs no simulation, and raw.mat remains the
% authoritative artifact beside it.
%
% See also ne39_reclose_demo_cached, ne39_reclose_build_cache.

traces = struct();
traces.t = result.t(:).';
if isfield(result,'coi_frequency_Hz')
    traces.coi_frequency_Hz = result.coi_frequency_Hz(:).';
end
if isfield(result,'sg_freq') && numel(result.sg_freq)==numel(result.t)
    traces.sg_freq = result.sg_freq(:).';
end
traces.v_min_pu = min(result.bus_voltage_magnitude,[],1);
traces.v_max_pu = max(result.bus_voltage_magnitude,[],1);
nd = numel(result.device_ids); nt = numel(result.t);
lv = zeros(nd,nt);
for k = 1:nd
    for j = 1:nt
        lv(k,j) = mode_level(result.device_modes_history{k,j}, ...
            result.device_online_history(k,j));
    end
end
traces.mode_level = lv;
traces.device_ids = result.device_ids;
traces.sample_count = nt;

ev = struct('type',{},'t',{},'transaction_id',{},'pre_kcl_norm',{}, ...
    'right_kcl_norm',{},'selected_gfm_indices',{},'dV',{},'dV_max',{}, ...
    'df',{},'df_max',{},'dtheta',{},'dtheta_max',{});
for k = 1:numel(result.event_log)
    e = result.event_log(k);
    if ~logical(e.applied), continue; end
    dv=NaN; dvmax=NaN; df=NaN; dfmax=NaN; dth=NaN; dthmax=NaN;
    if isfield(e,'guard') && isstruct(e.guard) && ~isempty(fieldnames(e.guard))
        g = e.guard;
        if isfield(g,'dV'),        dv    = g.dV;       end
        if isfield(g,'dV_max'),    dvmax = g.dV_max;   end
        if isfield(g,'df'),        df    = g.df;       end
        if isfield(g,'df_max'),    dfmax = g.df_max;   end
        if isfield(g,'dtheta'),    dth   = g.dtheta;   end
        if isfield(g,'dtheta_max'),dthmax= g.dtheta_max;end
    end
    sel = [];
    if isfield(e,'selected_gfm_indices') && ~isempty(e.selected_gfm_indices)
        sel = e.selected_gfm_indices;
    end
    ev(end+1) = struct('type',char(string(e.type)),'t',e.t, ...
        'transaction_id',e.transaction_id,'pre_kcl_norm',e.pre_kcl_norm, ...
        'right_kcl_norm',e.right_kcl_norm,'selected_gfm_indices',sel, ...
        'dV',dv,'dV_max',dvmax,'df',df,'df_max',dfmax, ...
        'dtheta',dth,'dtheta_max',dthmax); %#ok<AGROW>
end

head = struct();
head.converged = result.converged;
head.horizon_reached_s = traces.t(end);
head.t_end_requested_s = request.options.t_end;
head.accepted_samples = nt;
head.full_chronology = result.full_chronology;
head.production_certified = false;
head.classification = char(string(result.classification));
% Reclose/scalar fields are copied when present: a non-reclose chronology
% (fault_load_step runs no SG breaker event) publishes none of them, and the
% cache writer must not turn their absence into an audience-decode failure.
if isfield(result,'reclose_status'),    head.reclose_status = char(string(result.reclose_status)); end
if isfield(result,'actual_reclose_time'), head.actual_reclose_time = result.actual_reclose_time; end
if isfield(result,'t_sg_trip'),         head.t_sg_trip = result.t_sg_trip; end
if isfield(result,'rejected_steps'),    head.rejected_steps = result.rejected_steps; end
if isfield(result,'stepper'),           head.stepper = char(string(result.stepper)); end
if isfield(result,'reselection_status'), head.reselection_status = char(string(result.reselection_status)); end
if isfield(result,'actual_mode_reselection_time'), head.actual_mode_reselection_time = result.actual_mode_reselection_time; end
if isfield(result,'handback_status'),   head.handback_status = char(string(result.handback_status)); end
% Why a post-reclose release was refused, when one was refused. This is the
% kernel's own per-candidate audit (every evaluated one-step target with its
% refusal reason), copied verbatim so the demo can show the actual cause rather
% than only the aggregate status.
if isfield(result,'reselection_rejection_detail') && ~isempty(result.reselection_rejection_detail)
    head.reselection_rejection_detail = result.reselection_rejection_detail;
end
if isfield(result,'failure_id')
    head.failure_id = char(string(result.failure_id));
    head.failure_reason = char(string(result.failure_reason));
end

% Assignment (never the struct(...) constructor) so a cell-valued field such as
% sg_plant_state_names cannot turn the struct into a struct ARRAY.
cfg = struct();
cfg.events = request.events;
cfg.options = request.options;
cfg.declared_synchronism = request.declared_synchronism;
if isfield(request,'declared_minimum_off_s')
    cfg.declared_minimum_off_s = request.declared_minimum_off_s;
end
if isfield(request,'sg_plant_state_names')
    cfg.sg_plant_state_names = request.sg_plant_state_names;
end
if isfield(result,'selector_table_fingerprint')
    cfg.selector_table_fingerprint = char(string(result.selector_table_fingerprint));
end

info = struct();
info.source_raw = fullfile(folder,'raw.mat');
info.created_at = char(datetime('now','Format','yyyy-MM-dd HH:mm:ss'));
info.simulation_seconds = elapsed;
info.head = head;
info.config = cfg;
info.traces = traces;
info.events = ev;

cache_file = fullfile(folder,'replay_cache.mat');
save(cache_file,'info','-v7.3');
bytes = dir(cache_file).bytes;
raw_bytes = dir(fullfile(folder,'raw.mat')).bytes;
note = sprintf('%s (%.2f MB; raw is %.1f MB, %.0fx smaller)', ...
    cache_file,bytes/1e6,raw_bytes/1e6,raw_bytes/bytes);
end

function L = mode_level(m,online)
% 0 = breaker open, 1 = grid-following, 2 = voltage-forming (GFM or SG).
if ~online, L = 0; return; end
s = lower(char(string(m)));
if contains(s,'open'),    L = 0;
elseif strcmp(s,'gfl'),   L = 1;
else,                     L = 2;
end
end
