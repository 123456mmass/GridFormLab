function best = optimize_agsi_weights(opts)
%OPTIMIZE_AGSI_WEIGHTS  In-house OFFLINE search for the AGSI++ weights
%   [w_V w_f w_R w_P w_SCR w_lock] (>=0, sum=1) and thresholds Gamma_on/Gamma_off
%   that minimise a switching objective on the IEEE 14-bus 1-SG + 4-IBR system.
%
%   This is a DESIGN-TIME tuning tool (guided by the EECON49-P4 Bayesian-
%   Optimization concept), implemented with project-owned base-MATLAB only:
%   a uniform-simplex random search followed by a coordinate local refine.
%   NO external nonlinear/optimization solver is used, and this script is NOT on
%   any production runtime path (NUMERICAL_METHOD: random search + coordinate
%   descent). The tuned values it prints are then FROZEN as documented study
%   parameters; they are not read back into production at run time.
%
%   Objective (minimise), evaluated on the SG-trip + reclose scenario:
%     J = a*volt_dev + b*chatter + c*max_AGSI  (+ large penalty on collapse)
%   where volt_dev = mean_t |1 - Vmin(t)|, chatter = total mode switches,
%   max_AGSI = peak composite index. A collapse (divergence / non-convergence)
%   is penalised heavily so the optimiser prefers configurations that ride
%   through and switch cleanly without chattering.
%
%   best = optimize_agsi_weights(Name=Value): n_random, n_refine, T, dt, seed,
%   a, b, c. Returns struct best with .w (1x6), .gon, .goff, .J, .baseline_J.

arguments
    opts.n_random (1,1) double = 45
    opts.n_refine (1,1) double = 6
    opts.T (1,1) double = 6.0
    opts.dt (1,1) double = 2e-3
    opts.seed (1,1) double = 1
    opts.a (1,1) double = 12.0    % voltage-deviation weight
    opts.b (1,1) double = 0.6     % per-switch chatter weight
    opts.c (1,1) double = 0.05    % index-magnitude weight
end
pf_init_paths(); rng(opts.seed);

sys = ibr.build_ieee14_switch_system(index_mode="agsi_pp");   % build ONCE; reset per candidate
scen = struct('sg_trip_time',1.0,'sg_reclose_time',4.0,'T',opts.T,'dt',opts.dt);
J = @(w,gon,goff) obj_eval(sys, w, gon, goff, scen, opts.a, opts.b, opts.c);

% --- random search over the weight simplex + thresholds --------------------
best = struct('J',inf,'w',[.25 .25 .15 .10 .15 .10],'gon',0.65,'goff',0.35);
for k = 1:opts.n_random
    w = -log(rand(1,6)); w = w/sum(w);        % uniform Dirichlet(1) on the 6-simplex
    gon = 0.50 + 0.40*rand;                    % Gamma_on in [0.50, 0.90]
    goff = max(0.15, min(gon-0.10, 0.15 + (gon-0.20)*rand));
    Jk = J(w,gon,goff);
    if Jk < best.J, best.J=Jk; best.w=w; best.gon=gon; best.goff=goff; end
end

% --- coordinate local refine ----------------------------------------------
step = 0.06;
for it = 1:opts.n_refine
    improved = false;
    for i = 1:6
        for s = [-1 1]
            w2 = best.w; w2(i) = max(0, w2(i)+s*step); w2 = w2/sum(w2);
            Jk = J(w2,best.gon,best.goff);
            if Jk < best.J-1e-9, best.J=Jk; best.w=w2; improved=true; end
        end
    end
    for dg = [-step step]
        g2 = min(0.90, max(0.50, best.gon+dg));
        Jk = J(best.w,g2,best.goff); if Jk<best.J-1e-9, best.J=Jk; best.gon=g2; improved=true; end
        g2 = min(best.gon-0.10, max(0.15, best.goff+dg));
        Jk = J(best.w,best.gon,g2); if Jk<best.J-1e-9, best.J=Jk; best.goff=g2; improved=true; end
    end
    if ~improved, step = step/2; if step < 0.012, break; end; end
end

best.baseline_J = J([.25 .25 .15 .10 .15 .10], 0.65, 0.35);
lbl = {'w_V','w_f','w_R','w_P','w_SCR','w_lock'};
fprintf('\n==== OPTIMIZED AGSI++ (IEEE14 SG-trip+reclose objective) ====\n');
for i=1:6, fprintf('  %-6s = %.3f\n', lbl{i}, best.w(i)); end
fprintf('  Gamma_on  = %.3f\n  Gamma_off = %.3f\n', best.gon, best.goff);
fprintf('  J(optimized) = %.4f   vs   J(hand-set baseline) = %.4f   (%.1f%% lower)\n', ...
    best.J, best.baseline_J, 100*(best.baseline_J-best.J)/max(best.baseline_J,eps));
end

% =========================================================================
function Jval = obj_eval(sys, w, gon, goff, scen, a, b, c)
for j = 1:numel(sys.devs)
    d = sys.devs{j}; d.reset();
    d.w_V=w(1); d.w_f=w(2); d.w_R=w(3); d.w_P=w(4); d.w_SCR=w(5); d.w_lock=w(6);
    d.AGSI_up = gon; d.AGSI_down = goff;
end
try
    out = ibr.padiyar_switch_tds(sys, T=scen.T, dt=scen.dt, ...
        sg_trip_time=scen.sg_trip_time, sg_reclose_time=scen.sg_reclose_time);
catch
    Jval = 1e6; return;
end
if out.diverged || ~out.newton_all_converged
    Jval = 1e5 + 1e3*max(0, scen.T - out.tgrid(end));   % collapse / early truncation
    return;
end
volt_dev = mean(abs(1 - out.Vmin));
chatter  = sum(out.dev_n_switch);
max_agsi = max(out.index(:));
Jval = a*volt_dev + b*chatter + c*max_agsi;
end
