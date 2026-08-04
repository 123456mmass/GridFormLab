function result = et_fcs_bo_replay(candidates, bo)
%ET_FCS_BO_REPLAY  In-house offline BO baseline over a finite candidate table.
%   This function is ASSUMED_DIAGNOSTIC and OFFLINE ONLY. It sequentially
%   reveals precomputed prediction costs after the common hard screen, using a
%   zero-mean-adjusted Gaussian process with an RBF kernel and expected
%   improvement. It never feeds ET-FCSPS or production state.
%
%   No Optimization Toolbox or external solver is used; only base-MATLAB
%   arithmetic, CHOL, and backslash. Candidate truth is used only when its
%   ordinal is sampled or to report final offline regret.

arguments
    candidates struct
    bo struct
end

bo = validate_policy(bo);
result = blank_result();
if isempty(candidates), result.status = 'EMPTY_UNIVERSE'; return; end
required = {'ordinal','candidate_id','modes','owner_index','screen_pass', ...
    'metrics_pass','cost'};
for k = 1:numel(required)
    if ~isfield(candidates,required{k})
        error('stability:et_fcs_bo_replay:incompleteTable', ...
            'Candidate table is missing field "%s".',required{k});
    end
end

screen_idx = find([candidates.screen_pass]);
if isempty(screen_idx)
    result.status = 'NO_SCREEN_FEASIBLE'; return;
end
[~,o] = sort([candidates(screen_idx).ordinal]);
u = screen_idx(o);
X = candidate_features(candidates(u));
n = numel(u);
truth = bo.failure_penalty*ones(n,1);
dynamic_ok = false(n,1);
for j = 1:n
    c = candidates(u(j));
    dynamic_ok(j) = c.metrics_pass && isfinite(c.cost) && c.cost >= 0;
    if dynamic_ok(j), truth(j) = c.cost; end
end
if ~any(dynamic_ok)
    result.status = 'NO_DYNAMIC_FEASIBLE'; return;
end

budget = min(bo.budget,n);
ninit = min([bo.n_initial,budget,n]);
sampled = false(n,1);
sample_order = zeros(1,budget);
init = maxmin_initial(X,[candidates(u).ordinal],ninit);
sample_order(1:ninit) = init;
sampled(init) = true;
best_trace = NaN(1,budget);
for k = 1:ninit
    ids = sample_order(1:k);
    best_trace(k) = min(truth(ids));
end

for k = ninit+1:budget
    obs = find(sampled);
    uns = find(~sampled);
    [mu,sigma,ok] = gp_predict(X(obs,:),truth(obs),X(uns,:),bo);
    if ~ok
        result.status = 'GP_NUMERICAL_FAILURE';
        result.failure_id = 'stability:et_fcs_bo_replay:cholFailure';
        return;
    end
    best = min(truth(obs));
    improvement = best-mu;
    ei = zeros(size(mu));
    positive = sigma > 0;
    z = zeros(size(mu));
    z(positive) = improvement(positive)./sigma(positive);
    ei(positive) = improvement(positive).*normal_cdf(z(positive)) + ...
        sigma(positive).*normal_pdf(z(positive));
    ei(~positive) = max(improvement(~positive),0);
    max_ei = max(ei);
    tied = find(abs(ei-max_ei) <= bo.ei_tolerance);
    if isempty(tied), tied = 1; end
    if numel(tied) > 1
        ords = [candidates(u(uns(tied))).ordinal];
        [~,q] = min(ords); tied = tied(q);
    end
    chosen = uns(tied(1));
    sampled(chosen) = true;
    sample_order(k) = chosen;
    best_trace(k) = min(truth(sample_order(1:k)));
end

sampled_local = sample_order(1:budget);
sampled_feasible = sampled_local(dynamic_ok(sampled_local));
if isempty(sampled_feasible)
    result.status = 'NO_FEASIBLE_SAMPLED';
    result.failure_id = 'stability:et_fcs_bo_replay:budgetMissedFeasible';
else
    winner_local = deterministic_best(candidates,u,sampled_feasible);
    exhaustive_local = deterministic_best(candidates,u,find(dynamic_ok));
    winner_global = u(winner_local);
    exhaustive_global = u(exhaustive_local);
    result.status = 'COMPLETE';
    result.winner_index = winner_global;
    result.winner_candidate_id = candidates(winner_global).candidate_id;
    result.winner_cost = candidates(winner_global).cost;
    result.exhaustive_winner_index = exhaustive_global;
    result.exhaustive_winner_candidate_id = candidates(exhaustive_global).candidate_id;
    result.exhaustive_cost = candidates(exhaustive_global).cost;
    result.regret = result.winner_cost-result.exhaustive_cost;
    result.matches_exhaustive = winner_global == exhaustive_global;
end
result.evaluation_count = budget;
result.screen_feasible_count = n;
result.sampled_indices = reshape(u(sampled_local),1,[]);
result.sampled_candidate_ids = {candidates(result.sampled_indices).candidate_id};
result.best_observed_trace = best_trace;
result.classification = 'ASSUMED_DIAGNOSTIC_OFFLINE_REPLAY';
end

function bo = validate_policy(bo)
required = {'budget','n_initial','kernel_length','nugget','failure_penalty','ei_tolerance'};
for k = 1:numel(required)
    if ~isfield(bo,required{k}) || ~isnumeric(bo.(required{k})) || ...
            ~isscalar(bo.(required{k})) || ~isfinite(bo.(required{k}))
        error('stability:et_fcs_bo_replay:badPolicy', ...
            'Finite scalar BO field "%s" is mandatory.',required{k});
    end
end
if bo.budget < 1 || bo.budget ~= fix(bo.budget) || bo.n_initial < 1 || ...
        bo.n_initial ~= fix(bo.n_initial) || bo.n_initial > bo.budget || ...
        bo.kernel_length <= 0 || bo.nugget <= 0 || bo.failure_penalty <= 0 || ...
        bo.ei_tolerance < 0
    error('stability:et_fcs_bo_replay:badPolicy','BO policy values are inconsistent.');
end
end

function X = candidate_features(c)
n = numel(c); nr = numel(c(1).modes);
X = zeros(n,2*nr);
for i = 1:n
    if numel(c(i).modes) ~= nr || c(i).owner_index < 1 || c(i).owner_index > nr
        error('stability:et_fcs_bo_replay:badCandidate','Candidate mode/owner dimensions drift.');
    end
    X(i,1:nr) = cellfun(@(m) strcmpi(m,'gfm'),c(i).modes);
    X(i,nr+c(i).owner_index) = 1;
end
end

function selected = maxmin_initial(X,ordinals,ninit)
n = size(X,1); selected = zeros(1,ninit);
[~,selected(1)] = min(ordinals);
if ninit == 1, return; end
[~,selected(2)] = max(ordinals);
for k = 3:ninit
    remain = setdiff(1:n,selected(1:k-1),'stable');
    dmin = Inf(size(remain));
    for j = 1:numel(remain)
        d = sum((X(selected(1:k-1),:)-X(remain(j),:)).^2,2);
        dmin(j) = min(d);
    end
    best = max(dmin);
    tied = remain(dmin == best);
    [~,q] = min(ordinals(tied));
    selected(k) = tied(q);
end
end

function [mu,sigma,ok] = gp_predict(X,y,Xs,bo)
ok = true; mu = []; sigma = [];
K = rbf_kernel(X,X,bo.kernel_length) + bo.nugget*eye(size(X,1));
[L,p] = chol(K,'lower');
if p ~= 0, ok = false; return; end
mean_y = mean(y);
alpha = L'\(L\(y-mean_y));
Ks = rbf_kernel(X,Xs,bo.kernel_length);
mu = mean_y + Ks'*alpha;
v = L\Ks;
variance = 1-sum(v.^2,1)';
variance(variance < 0 & variance > -1e-12) = 0;
if any(variance < 0) || any(~isfinite(variance))
    ok = false; return;
end
sigma = sqrt(variance);
end

function K = rbf_kernel(A,B,ell)
aa = sum(A.^2,2); bb = sum(B.^2,2)';
d2 = max(0,aa+bb-2*(A*B'));
K = exp(-0.5*d2/(ell^2));
end

function p = normal_pdf(z)
p = exp(-0.5*z.^2)/sqrt(2*pi);
end

function p = normal_cdf(z)
p = 0.5*erfc(-z/sqrt(2));
end

function local = deterministic_best(c,u,eligible_local)
M = zeros(numel(eligible_local),4);
for k = 1:numel(eligible_local)
    j = eligible_local(k); x = c(u(j));
    M(k,:) = [x.cost,x.n_switch,x.n_gfm,x.ordinal];
end
[~,o] = sortrows(M,1:4);
local = eligible_local(o(1));
end

function r = blank_result()
r = struct('status','UNINITIALIZED','failure_id','','winner_index',[], ...
    'winner_candidate_id','','winner_cost',NaN,'exhaustive_winner_index',[], ...
    'exhaustive_winner_candidate_id','','exhaustive_cost',NaN,'regret',NaN, ...
    'matches_exhaustive',false,'evaluation_count',0,'screen_feasible_count',0, ...
    'sampled_indices',[],'sampled_candidate_ids',{{}},'best_observed_trace',[], ...
    'classification','ASSUMED_DIAGNOSTIC_OFFLINE_REPLAY');
end
