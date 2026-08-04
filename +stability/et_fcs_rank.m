function [candidates, ranking] = et_fcs_rank(snapshot, candidates, policy)
%ET_FCS_RANK  Deterministic cost and tie-break over hard-feasible candidates.
%   Hard-rejected candidates are retained in the evidence table but excluded
%   from the ranking. Weight and cost-quantization contracts are mandatory and
%   frozen by the caller before results are viewed.

arguments
    snapshot struct
    candidates struct
    policy struct
end

[w, tol] = validate_policy(policy);
metric_names = {'voltage','frequency','rocof','reserve_p','reserve_q', ...
    'current','handback','n_gfm','n_switch'};
feasible = false(numel(candidates),1);
for i = 1:numel(candidates)
    candidates(i).cost = Inf;
    candidates(i).cost_key = Inf;
    candidates(i).rank = NaN;
    candidates(i).order_key = '';
    if ~isfield(candidates(i),'metrics_pass') || ~candidates(i).metrics_pass
        continue;
    end
    cost = 0;
    for k = 1:numel(metric_names)
        f = metric_names{k};
        cost = cost + w.(f)*candidates(i).metrics.(f);
    end
    if ~isfinite(cost) || cost < 0, continue; end
    candidates(i).cost = cost;
    candidates(i).cost_key = round(cost/tol)*tol;
    feasible(i) = true;
end

idx = find(feasible);
if isempty(idx)
    ranking = struct('status','INFEASIBLE','winner_index',[], ...
        'winner_candidate_id','','order',[],'candidate_evidence_fingerprint','');
    canonical = canonical_order(candidates);
    [~,~,evfp] = compute_selector_table_fingerprint(struct('selector', ...
        struct('snapshot_fingerprint',snapshot.fingerprint)), ...
        struct('sg_off_configurations',canonical));
    ranking.candidate_evidence_fingerprint = ['et_fcs_evidence_v1:' evfp];
    return;
end

M = zeros(numel(idx),7);
for j = 1:numel(idx)
    c = candidates(idx(j));
    M(j,:) = [c.cost_key,c.n_switch,c.n_gfm,-c.metrics.reserve_margin, ...
        c.metrics.kcl_norm,c.ordinal,j];
end
[~,local_order] = sortrows(M,1:7);
order = idx(local_order);
for r = 1:numel(order)
    i = order(r);
    candidates(i).rank = r;
    candidates(i).order_key = sprintf( ...
        'Jq=%.12g|Nsw=%d|Ngfm=%d|R=%.12g|KCL=%.12g|ord=%d', ...
        candidates(i).cost_key,candidates(i).n_switch,candidates(i).n_gfm, ...
        candidates(i).metrics.reserve_margin,candidates(i).metrics.kcl_norm, ...
        candidates(i).ordinal);
end

canonical = canonical_order(candidates);
[~,~,evfp] = compute_selector_table_fingerprint(struct('selector', ...
    struct('snapshot_fingerprint',snapshot.fingerprint,'weights',w, ...
    'cost_quantization',tol)), struct('sg_off_configurations',canonical));
ranking = struct('status','FEASIBLE','winner_index',order(1), ...
    'winner_candidate_id',candidates(order(1)).candidate_id,'order',reshape(order,1,[]), ...
    'candidate_evidence_fingerprint',['et_fcs_evidence_v1:' evfp]);
end

function out = canonical_order(candidates)
if isempty(candidates), out = candidates; return; end
if ~isfield(candidates,'ordinal')
    error('stability:et_fcs_rank:missingOrdinal', ...
        'Every candidate must carry its canonical enumeration ordinal.');
end
[~,order] = sort([candidates.ordinal]);
out = candidates(order);
end

function [w,tol] = validate_policy(p)
if ~isfield(p,'weights') || ~isstruct(p.weights) || ...
        ~isfield(p,'cost_quantization')
    error('stability:et_fcs_rank:missingPolicy', ...
        'Frozen weights and cost_quantization are mandatory.');
end
w = p.weights;
names = {'voltage','frequency','rocof','reserve_p','reserve_q', ...
    'current','handback','n_gfm','n_switch'};
vals = zeros(1,numel(names));
for k = 1:numel(names)
    f = names{k};
    if ~isfield(w,f) || ~isnumeric(w.(f)) || ~isscalar(w.(f)) || ...
            ~isfinite(w.(f)) || w.(f) < 0
        error('stability:et_fcs_rank:badWeights', ...
            'Weight "%s" must be a finite nonnegative scalar.', f);
    end
    vals(k) = w.(f);
end
if abs(sum(vals)-1) > 1e-12
    error('stability:et_fcs_rank:badWeights', ...
        'ET-FCSPS weights must sum to one (received %.16g).', sum(vals));
end
tol = p.cost_quantization;
if ~isnumeric(tol) || ~isscalar(tol) || ~isfinite(tol) || tol <= 0
    error('stability:et_fcs_rank:badCostQuantization', ...
        'cost_quantization must be a positive finite scalar.');
end
end
