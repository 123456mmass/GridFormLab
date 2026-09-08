function out = verify_mode_switch_algebra(opts)
%VERIFY_MODE_SWITCH_ALGEBRA  Check the report's mode-transfer derivation in code.
%
%   out = verify_mode_switch_algebra()
%
% The report's section on mode switching argues the transfer ALGEBRAICALLY:
% not "the jump is small", but "the jump is zero by construction, and the gate
% only guards the implementation". This script tests each step of that argument
% against the production closures, so no claim reaches the report unchecked.
%
% STEPS TESTED
%   A. The AC-current rows reduce to the inner PI alone. Substituting the
%      decoupling feed-forward
%          v_cd = v_d + R_f i_d - w L_f i_q + k_pI e_d + k_iI xi_Id
%      into
%          di_d/dt = (v_cd - v_d - R_f i_d + w L_f i_q)/(L_f/w_b)
%      must cancel the plant terms exactly, leaving
%          di_d/dt = w_b (k_pI e_d + k_iI xi_Id)/L_f,
%      and likewise on q. If this holds, the ONLY route by which the mode
%      reaches the plant is the current reference i* -- which is the report's
%      claim about what a mode change IS.
%
%   B. Both branch initialisers map one port (V,P,Q) to the SAME dq pair and
%      the SAME frame angle:
%          i_d^+ = kappa P/|V|,  i_q^+ = -kappa Q/|V|,  delta^+ = angle(V).
%      GFL writes this directly; GFM writes I_sys = conj(S/V) then rotates.
%      They must agree to machine precision, in both directions.
%
%   C. Therefore I^+ = I^- exactly: with S = V conj(I^-), the reconstructed
%      current is conj(S/V) = I^-. The continuity gate eps_I is then a guard on
%      arithmetic, not the source of the continuity.
%
%   D. At the GFM anchor the voltage-loop errors vanish: delta^+ = angle(V)
%      gives v_d = |V|, v_q = 0, and E^+ = |V|, so e_Vd = e_Vq = 0. With
%      xi_Vd = i_d/k_iV and xi_Vq = i_q/k_iV the clipped reference equals the
%      flowing current, so e_d = e_q = 0 and the AC rows are stationary AT THE
%      TRANSFER VOLTAGE. (Whether they stay stationary depends on what the
%      network does next, which is a separate question.)
%
%   E. The frequency carry inverts the PLL's own steady state. In GFL,
%          d(delta_PLL)/dt = k_pPLL v_q + k_iPLL xi_PLL,  omega_pu = 1 + .../w_b,
%      so at v_q = 0, omega_pu = 1 + k_iPLL xi_PLL/w_b. Solving for xi_PLL at a
%      given omega gives exactly the GFM->GFL carry the code applies,
%          xi_PLL^+ = w_b (omega_VSG^- - 1)/k_iPLL.
%
% Every tolerance below is an ARITHMETIC tolerance on an identity that holds
% exactly in real arithmetic; none of them is a modelling allowance.
%
% Run with:
%   pf_init_paths; verify_mode_switch_algebra()

arguments
    opts.tol (1,1) double {mustBePositive} = 1e-12
    opts.cache (1,1) string = ...
        fullfile('output','diagnostics','ieee14_scenario_suite', ...
                 'sg_fault_cycle160.mat')
    opts.verbose (1,1) logical = true
end

pf_init_paths();
tol = opts.tol;
rep = struct('name',{},'value',{},'tol',{},'pass',{});

% --- a device, at the case's own operating point ---------------------------
% Built through the SAME resource table the simulator builds from, so every
% gain below is the production value and none is written here.
sys = ibr.build_ieee14_switch_system(index_mode='agsi_pp', ...
    case_profile='eecon49_figure4',sg_H=2.5,sg_D=1.0,T_d_on=0.10,T_d_off=1.0);
scen = cases.scenario_ieee14_1sg_4ibr( ...
    struct('case_profile','eecon49_figure4'));
[prm,P_ref,Q_ref,bus_id,bp,V0,bus_ids] = build_probe(scen,sys,'IBR2');

gfl = ibr.gfl_eecon49_full_model('IBR2',bus_id,bp,bus_ids,V0,prm,P_ref,Q_ref);
gfm = ibr.gfm_eecon49_full_model('IBR2',bus_id,bp,bus_ids,V0,prm,P_ref,Q_ref, ...
    abs(V0));
p = gfl.provenance.params;
kappa = p.kappa; wb = p.omega_b; Lf = p.Lf; Rf = p.Rf;
kpI = p.kpI; kiI = p.kiI; kiP = p.kiP; kiQ = p.kiQ; kiPLL = p.kiPLL;
pm = gfm.provenance.params;
kiV = pm.kiV; kpV = pm.kpV;

y = zeros(2*numel(bus_ids),1);
for q = 1:numel(bus_ids)
    y(2*q-1) = real(sys.pf.bus_voltage(q));
    y(2*q)   = imag(sys.pf.bus_voltage(q));
end
ec = struct();
V = complex(y(2*bp-1),y(2*bp));

% =========================================================================
% A. the AC-current rows are the inner PI alone
% =========================================================================
% Perturb every state so the test is not accidentally run at an equilibrium
% where both sides happen to vanish.
rng(7);
xg = gfl.x0(:); xg(1:9) = xg(1:9).*(1+0.35*randn(9,1)) + 0.05*randn(9,1);
dg = gfl.f(0,xg,y,[P_ref;Q_ref],ec);
pp = p; pp.Pref_probe = P_ref; pp.Qref_probe = Q_ref;
[edg,eqg] = gfl_inner_errors(xg,y,bp,pp);
rep = addcheck(rep,'A1 GFL di_d/dt = w_b(k_pI e_d + k_iI xi_Id)/L_f', ...
    abs(dg(1) - wb*(kpI*edg + kiI*xg(8))/Lf),tol);
rep = addcheck(rep,'A2 GFL di_q/dt = w_b(k_pI e_q + k_iI xi_Iq)/L_f', ...
    abs(dg(2) - wb*(kpI*eqg + kiI*xg(9))/Lf),tol);

xm = gfm.x0(:); xm(1:10) = xm(1:10).*(1+0.35*randn(10,1)) + 0.05*randn(10,1);
dm = gfm.f(0,xm,y,[P_ref;Q_ref;abs(V0)],ec);
[edm,eqm] = gfm_inner_errors(xm,y,bp,pm);
rep = addcheck(rep,'A3 GFM di_d/dt = w_b(k_pI e_d + k_iI xi_Id)/L_f', ...
    abs(dm(1) - wb*(kpI*edm + kiI*xm(9))/Lf),tol);
rep = addcheck(rep,'A4 GFM di_q/dt = w_b(k_pI e_q + k_iI xi_Iq)/L_f', ...
    abs(dm(2) - wb*(kpI*eqm + kiI*xm(10))/Lf),tol);

% =========================================================================
% B. one port, one dq pair, one frame angle -- from BOTH initialisers
% =========================================================================
% The transfer measures (V, P^-, Q^-) at the departing branch and hands that
% triple to the arriving branch's own equilibrium_initialize. If the two
% initialisers did not agree on the dq pair, the terminal current would jump
% and no tolerance could fix it, so this is the structural step.
Pm = 0.61; Qm = -0.23;                   % an arbitrary measured port
gx = gfl.equilibrium_initialize(V,Pm,Qm,ec);
mx = gfm.equilibrium_initialize(V,Pm,Qm,ec);
id_expect = kappa*Pm/abs(V);
iq_expect = -kappa*Qm/abs(V);
rep = addcheck(rep,'B1 GFL i_d^+ = kappa P/|V|',abs(gx(1)-id_expect),tol);
rep = addcheck(rep,'B2 GFL i_q^+ = -kappa Q/|V|',abs(gx(2)-iq_expect),tol);
rep = addcheck(rep,'B3 GFM i_d^+ equals the GFL value',abs(mx(1)-gx(1)),tol);
rep = addcheck(rep,'B4 GFM i_q^+ equals the GFL value',abs(mx(2)-gx(2)),tol);
rep = addcheck(rep,'B5 both frames anchor at angle(V)', ...
    max(abs(gx(4)-angle(V)),abs(mx(4)-angle(V))),tol);

% =========================================================================
% C. therefore the injected current is unchanged, in BOTH directions
% =========================================================================
% Start from an arbitrary perturbed state in one branch, read its port, hand
% that port to the other branch, and compare the currents the two branches
% inject. This is the report's claim that continuity is a property of the map,
% with eps_I guarding arithmetic only.
[dI_l2m,I_left1] = port_roundtrip(gfl,gfm,xg,y,[P_ref;Q_ref],[P_ref;Q_ref;abs(V0)],ec,bp);
[dI_m2l,I_left2] = port_roundtrip(gfm,gfl,xm,y,[P_ref;Q_ref;abs(V0)],[P_ref;Q_ref],ec,bp);
rep = addcheck(rep,'C1 GFL->GFM |I^+ - I^-|',dI_l2m,tol);
rep = addcheck(rep,'C2 GFM->GFL |I^+ - I^-|',dI_m2l,tol);
fprintf('  (ports probed: |I| = %.12f and %.12f pu)\n',abs(I_left1),abs(I_left2));

% =========================================================================
% D. at the GFM anchor both voltage-loop errors and both current errors vanish
% =========================================================================
% delta^+ = angle(V) puts the whole terminal voltage on the d axis, and
% E^+ = |V| makes the voltage reference equal to it, so e_Vd = e_Vq = 0.
% xi_Vd = i_d/k_iV, xi_Vq = i_q/k_iV then make the voltage loop's OUTPUT equal
% the current already flowing, so the inner errors vanish too and the AC rows
% are stationary at the transfer voltage.
Vdq_m = V*exp(-1i*mx(4));
rep = addcheck(rep,'D1 GFM anchor puts v_q = 0',abs(imag(Vdq_m)),tol);
rep = addcheck(rep,'D2 GFM anchor sets E = |V| = v_d', ...
    max(abs(mx(6)-abs(V)),abs(mx(6)-real(Vdq_m))),tol);
rep = addcheck(rep,'D3 GFM anchor gives e_Vd = e_Vq = 0', ...
    max(abs(mx(6)-real(Vdq_m)),abs(0-imag(Vdq_m))),tol);
rep = addcheck(rep,'D4 GFM anchor: i*_d = i_d and i*_q = i_q', ...
    max(abs(kiV*mx(7)-mx(1)),abs(kiV*mx(8)-mx(2))),tol);
dm0 = gfm.f(0,mx,y,[Pm;Qm;abs(V)],ec);
rep = addcheck(rep,'D5 GFM anchor: the two AC rows are stationary', ...
    max(abs(dm0(1)),abs(dm0(2))),1e-9);
% The same statement for the GFL anchor: xi_P = i_d/k_iP, xi_Q = -i_q/k_iQ.
rep = addcheck(rep,'D6 GFL anchor: i*_d = i_d and i*_q = i_q', ...
    max(abs(kiP*gx(6)-gx(1)),abs(-kiQ*gx(7)-gx(2))),tol);
dg0 = gfl.f(0,gx,y,[Pm;Qm],ec);
rep = addcheck(rep,'D7 GFL anchor: the two AC rows are stationary', ...
    max(abs(dg0(1)),abs(dg0(2))),1e-9);

% =========================================================================
% E. the frequency carry inverts the PLL's own steady state
% =========================================================================
% In GFL, omega_pu = 1 + (k_pPLL v_q + k_iPLL xi_PLL)/w_b. At the anchor
% v_q = 0, so demanding omega_pu = omega^- gives xi_PLL exactly as the code
% writes it. Verified by substituting the carried value back into the branch
% and reading the frequency the branch itself reports.
om_target = 0.994;
xi_carry = wb*(om_target-1)/kiPLL;
xt = gx; xt(5) = xi_carry;
rec = gfl.reconstruct(0,xt,y,[Pm;Qm],ec);
rep = addcheck(rep,'E1 carried xi_PLL reproduces omega_VSG^-', ...
    abs(rec.omega_PLL_pu-om_target),tol);
% And the other direction: GFM carries omega_VSG := omega_PLL, so the VSG
% speed state IS the frequency the PLL was reporting.
xm2 = mx; xm2(5) = rec.omega_PLL_pu;
recm = gfm.reconstruct(0,xm2,y,[Pm;Qm;abs(V)],ec);
rep = addcheck(rep,'E2 carried omega_VSG reproduces omega_PLL^-', ...
    abs(recm.omega_pu-om_target),tol);

% =========================================================================
% F. the same identities AT THE TWO COMMITS THE DELIVERED ARM EXECUTED
% =========================================================================
% Steps A-E prove the algebra on the production closures. This step checks the
% delivered trajectory itself, so the report's section can cite the identities
% AND the run in which they held. Reading the cache is optional: the algebra
% above stands on its own, so a missing cache skips this block rather than
% failing it.
if isfile(opts.cache)
    [rep,commits] = check_delivered(rep,opts.cache,tol,opts.verbose);
else
    commits = struct([]);
    fprintf('\n(cache %s absent: step F skipped)\n',opts.cache);
end

out = struct('report',{rep},'all_pass',all([rep.pass]),'commits',commits);
if opts.verbose, print_report(rep); end
end

% =========================================================================
function [rep,commits] = check_delivered(rep,cfile,tol,verbose)
%CHECK_DELIVERED  The identities, evaluated at the real commits of one arm.
%
% For each mode change the arm executed, this recomputes from the cache:
%   the terminal-current jump the gate constrains,
%   the dormant controller block's jump (must be exactly zero),
%   the active-set dimension either side,
%   and the FIELD GAP: both branch fields at the SAME right-limit state, which
%   is the quantity the report names as the source of the post-switch transient.
S = load(cfile);
r = S.result;
devs = r.equilibrium.devices;
nx = [devs.nx]; nu = [devs.nu];
xo = cumsum([0 nx(1:end-1)]); uo = cumsum([0 nu(1:end-1)]);
t = r.t(:);
COM = [1 2 3 17]; GFL = 4:9; GFM = 10:16;
commits = struct('device',{},'t',{},'from',{},'to',{}, ...
    'dI',{},'dormant_jump',{},'n_left',{},'n_right',{},'field_gap',{});
for k = 1:numel(devs)
    if nx(k) ~= 17, continue; end
    md = string(r.device_modes_history(k,:));
    for j = find(md(2:end) ~= md(1:end-1)) + 1
        xR = r.x_traj(xo(k)+(1:17),j);
        xL = r.x_traj(xo(k)+(1:17),j-1);
        y  = r.y_traj(:,j);
        u  = r.u_history(uo(k)+(1:nu(k)),j);
        ecL = r.event_context_history{j-1};
        ecR = r.event_context_history{j};
        dI = abs(r.device_currents(k,j)-r.device_currents(k,j-1));
        % Whichever block is dormant on the RIGHT is the one the switch stops
        % integrating; its coordinates must be carried, not re-initialised.
        if strcmpi(md(j),'GFM'), dorm = GFL; else, dorm = GFM; end
        dj = max(abs(xR(dorm)-xL(dorm)));
        fL = devs(k).f(t(j),xR,y,u,ecL);
        fR = devs(k).f(t(j),xR,y,u,ecR);
        nL = numel(devs(k).active_state_indices_for_context(ecL));
        nR = numel(devs(k).active_state_indices_for_context(ecR));
        commits(end+1) = struct('device',char(string(r.device_ids{k})), ...
            't',t(j),'from',char(md(j-1)),'to',char(md(j)), ...
            'dI',dI,'dormant_jump',dj,'n_left',nL,'n_right',nR, ...
            'field_gap',norm(fR-fL)); %#ok<AGROW>
        nm = sprintf('F %s %s->%s @%.4f s',char(string(r.device_ids{k})), ...
            char(md(j-1)),char(md(j)),t(j));
        rep = addcheck(rep,[nm ': |I^+-I^-|'],dI,tol);
        rep = addcheck(rep,[nm ': dormant block jump'],dj,tol);
        % The field gap must be NONZERO: a switch that changed nothing would
        % make the whole mechanism vacuous. Written as a check on its
        % reciprocal so it reads in the same table as the others.
        rep = addcheck(rep,[nm ': field gap is nonzero (1/gap)'], ...
            1/max(norm(fR-fL),realmin),1e3);
    end
end
if verbose
    fprintf('\ncommits found in %s:\n',cfile);
    for c = commits
        fprintf(['  %-5s %s->%-4s t=%10.6f s  n_act %2d->%2d  ' ...
            '|dI|=%.2e  dormant jump=%.2e  ||df||=%.4g\n'], ...
            c.device,c.from,c.to,c.t,c.n_left,c.n_right,c.dI, ...
            c.dormant_jump,c.field_gap);
    end
end
end

% =========================================================================
function [prm,P_ref,Q_ref,bus_id,bp,V0,bus_ids] = build_probe(scen,sys,rid)
%BUILD_PROBE  The production parameters and dispatch of one resource.
%   Read out of the built scenario table, so every gain and every reference is
%   the value the simulator uses; nothing is written here.
res = scen.resources;
k = find(strcmp(string({res.resource_id}),string(rid)),1);
assert(~isempty(k),'verify_mode_switch_algebra:noResource', ...
    'The scenario table carries no resource "%s".',rid);
r = res(k);
assert(strcmp(char(string(r.model_id)),'eecon49_dual'), ...
    'verify_mode_switch_algebra:wrongModel', ...
    ['Resource %s is built by "%s"; this check is about the EECON49 ' ...
     'dual-mode model, so the scenario must select eecon49_figure4.'], ...
    rid,char(string(r.model_id)));
bus_ids = sys.pf.external_bus_ids(:)';
bus_id = double(r.bus_id);
bp = find(bus_ids==bus_id,1);
assert(~isempty(bp),'verify_mode_switch_algebra:noBus', ...
    'Resource %s sits at bus %d, which the PF bus list does not carry.', ...
    rid,bus_id);
V0 = sys.pf.bus_voltage(bp);
prm = r.dynamic_params;
if ~isfield(prm,'Mbase') && isfield(r,'ratings') && isfield(r.ratings,'Mbase')
    prm.Mbase = r.ratings.Mbase;
end
Sbase = 100.0;
if isfield(prm,'Sbase'), Sbase = prm.Sbase; end
P_ref = 0.0;
if isfield(r.ratings,'default_P_MW') && ~isempty(r.ratings.default_P_MW)
    P_ref = double(r.ratings.default_P_MW)/Sbase;
end
Q_ref = 0.0;
if isfield(r.ratings,'default_Q_MVAr') && ~isempty(r.ratings.default_Q_MVAr)
    Q_ref = double(r.ratings.default_Q_MVAr)/Sbase;
end
end

% =========================================================================
function [ed,eq] = gfl_inner_errors(x,y,bp,p)
%GFL_INNER_ERRORS  The inner-loop current errors, recomputed independently.
%   Written from the source equations rather than read out of the branch, so
%   step A compares two independent evaluations instead of one with itself.
%   P.Pref_probe / P.Qref_probe carry the same reference pair the caller passes
%   into the branch as u.
V = complex(y(2*bp-1),y(2*bp));
id = x(1); iq = x(2); th = x(4);
I = complex(id,iq)*exp(1i*th)/p.kappa;
S = V*conj(I);
eP = p.kappa*p.Pref_probe - p.kappa*real(S);
eQ = p.kappa*p.Qref_probe - p.kappa*imag(S);
idref_raw = p.kpP*eP + p.kiP*x(6);
iqref_raw = -(p.kpQ*eQ + p.kiQ*x(7));
[idref,iqref] = clip_circ(idref_raw,iqref_raw,p.Imax);
ed = idref - id;
eq = iqref - iq;
end

% =========================================================================
function [ed,eq] = gfm_inner_errors(x,y,bp,pm)
%GFM_INNER_ERRORS  The GFM inner-loop current errors, recomputed independently.
V = complex(y(2*bp-1),y(2*bp));
id = x(1); iq = x(2); th = x(4); E = x(6);
Vdq = V*exp(-1i*th); vd = real(Vdq); vq = imag(Vdq);
idref_raw = pm.kpV*(E-vd) + pm.kiV*x(7);
iqref_raw = pm.kpV*(0-vq) + pm.kiV*x(8);
[idref,iqref] = clip_circ(idref_raw,iqref_raw,pm.Imax);
ed = idref - id;
eq = iqref - iq;
end

% =========================================================================
function [a,b] = clip_circ(a,b,m)
%CLIP_CIRC  The circular limiter Pi_I, as both branches apply it.
r = hypot(a,b);
if r > m, a = a*m/r; b = b*m/r; end
end

% =========================================================================
function [dI,I_left] = port_roundtrip(src,dst,x_src,y,u_src,u_dst,ec,bp)
%PORT_ROUNDTRIP  Measure one branch's port, re-anchor the other, compare I.
V = complex(y(2*bp-1),y(2*bp));
I_left = src.current_injection(0,x_src,y,u_src,ec);
S = V*conj(I_left);
x_dst = dst.equilibrium_initialize(V,real(S),imag(S),ec);
I_right = dst.current_injection(0,x_dst,y,u_dst,ec);
dI = abs(I_right-I_left);
end

% =========================================================================
function rep = addcheck(rep,name,value,tol)
rep(end+1) = struct('name',name,'value',value,'tol',tol,'pass',value<=tol); %#ok<AGROW>
end

% =========================================================================
function print_report(rep)
fprintf('\n%-58s %12s %10s %s\n','check','residual','tol','');
for k = 1:numel(rep)
    fprintf('%-58s %12.3e %10.0e %s\n',rep(k).name,rep(k).value, ...
        rep(k).tol,iif(rep(k).pass,'PASS','FAIL'));
end
n = sum([rep.pass]);
fprintf('\n%d of %d checks pass.\n',n,numel(rep));
assert(n==numel(rep),'verify_mode_switch_algebra:failed', ...
    '%d algebraic identity check(s) failed; the derivation and the code disagree.', ...
    numel(rep)-n);
end

% =========================================================================
function s = iif(c,a,b)
if c, s = a; else, s = b; end
end
