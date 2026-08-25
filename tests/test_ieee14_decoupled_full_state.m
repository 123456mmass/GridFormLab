function tests=test_ieee14_decoupled_full_state
tests=functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function testProfileBuildsSeventeenStateDevicesWithResolvedContract(testCase)
% The decoupled profile must reach the production builder and resolve its own
% contract.  ibr.device_contract_metadata dispatches on an exact
% (device_type, nx, nu, state_names, input_names) match and fails closed
% otherwise, so this simultaneously proves the registry entry exists and that
% the scenario builds the intended model rather than the baseline.
s=cases.scenario_ieee14_1sg_4ibr(struct('case_profile','decoupled_figure4'));
verifyEqual(testCase,s.scenario_id,'ieee14_decoupled_1sg_4ibr');
verifyEqual(testCase,char(s.resources(2).model_id),'decoupled_dual');
[devices,~]=stability.build_mixed_resource_devices(s.case_data,s.resources, ...
    s.scenario_opt);
verifyEqual(testCase,[devices(2:end).nx],[17 17 17 17]);
for k=2:numel(devices)
    verifyEqual(testCase,char(devices(k).device_type),'ibr_decoupled_dual');
    md=ibr.device_contract_metadata(devices(k));
    verifyEqual(testCase,md.contract_id,'decoupled_dual');
    verifyEqual(testCase,numel(md.state_metadata),17);
    verifyEqual(testCase,md.state_metadata(17).state_name,'gfm_omega_f');
end
% The production swing parameters must be the derived design values, and the
% baseline profile must be untouched by this profile existing.  The shared
% builder normalizes every device provenance to the uniform 4-field struct
% (build_mixed_resource_devices, "Uniform provenance"), so the model-specific
% omega_f_index is asserted on the factory output instead.
V0=complex(1.02,0);
dfac=ibr.decoupled_dual_mode_model('IBR_TEST',2,1,[2 3],V0, ...
    s.resources(2).dynamic_params,0.4,0.1,1.02,"GFM");
verifyEqual(testCase,dfac.provenance.omega_f_index,17);
verifyEqual(testCase,dfac.nx,17);
pr=devices(2).provenance;
verifyEqual(testCase,char(pr.model),'decoupled_dual');
verifyTrue(testCase,contains(string(pr.classification),'PROJECT_DERIVED'));
verifyTrue(testCase,contains(string(pr.details),'17-state'));
verifyTrue(testCase,contains(string(pr.details),'omega_f'));
% Every derived swing coefficient must reach the resource dynamic parameters.
gp=s.resources(2).dynamic_params.gfm_decoupled;
verifyEqual(testCase,gp.R_droop,0.05,'AbsTol',0);
verifyEqual(testCase,gp.D_t,0.0,'AbsTol',0);
verifyEqual(testCase,gp.wD,50.0,'AbsTol',0);
verifyEqual(testCase,gp.M,0.08,'AbsTol',0);
verifyFalse(testCase,isfield(s.resources(2).dynamic_params,'gfm_eecon49'), ...
    'the decoupled profile must not also ship the baseline GFM parameters');
sb=cases.scenario_ieee14_1sg_4ibr(struct('case_profile','eecon49_figure4'));
verifyEqual(testCase,char(sb.resources(2).model_id),'eecon49_dual');
verifyTrue(testCase,isfield(sb.resources(2).dynamic_params,'gfm_eecon49'));
verifyFalse(testCase,isfield(sb.resources(2).dynamic_params,'gfm_decoupled'));
% The baseline family carries the Thevenin DC-source STATE (source_state=true,
% NUM-2026-08-20-01 owner-approved), so its superset is the 17-vector with
% I_dc at index 17. The earlier expectation of 16 here predates that extension
% and was correct only for the pre-DC-link tree; the decoupled profile above
% keeps source_state=false and therefore the same 17-vector layout with an
% algebraic source current instead. Both families now share ONE superset
% length, which is exactly what lets the spectrum-equality tests below compare
% them coordinate by coordinate.
[bdev,~]=stability.build_mixed_resource_devices(sb.case_data,sb.resources, ...
    sb.scenario_opt);
verifyEqual(testCase,[bdev(2:end).nx],[17 17 17 17]);
verifyEqual(testCase,char(bdev(2).device_type),'ibr_eecon49_dual');
verifyTrue(testCase,sb.resources(2).dynamic_params.dc_source.source_state, ...
    'the EECON49 family must carry the Thevenin source state');
verifyFalse(testCase,s.resources(2).dynamic_params.dc_source.source_state, ...
    'the decoupled family must keep the algebraic source current');
end

function testScrProfileAndReducedInitializerAcceptTheFamily(testCase)
% Two silent-hazard registrations: a family missing from ibr_scr_metrics
% becomes SCR-eligible (a different gate), and a family missing from
% mixed_ibr_reduced_initialize loses the SG-off warm start.  Neither throws, so
% both are asserted behaviourally against the baseline family.
s=cases.scenario_ieee14_1sg_4ibr(struct('case_profile','decoupled_figure4'));
sb=cases.scenario_ieee14_1sg_4ibr(struct('case_profile','eecon49_figure4'));
scr=stability.ibr_scr_metrics(s.case_data,s.resources,struct());
scrb=stability.ibr_scr_metrics(sb.case_data,sb.resources,struct());
n=numel(scr.per_resource);
is_ibr=false(1,n);
for k=1:n
    is_ibr(k)=isfield(s.resources(k),'resource_type') && ...
        strcmpi(char(s.resources(k).resource_type),'ibr');
end
prof=unique(string({scr.per_resource(is_ibr).scr_profile}));
profb=unique(string({scrb.per_resource(is_ibr).scr_profile}));
verifyEqual(testCase,numel(prof),1);
verifyEqual(testCase,prof,profb);
verifyEqual(testCase,char(prof(1)),'not_applicable_full_state_source_model');
verifyFalse(testCase,any([scr.per_resource(is_ibr).eligible_for_scr]));
% Reduced SG-off initializer: applicable for this homogeneous P/Q-reference
% island, exactly as for the baseline family.
[devices,~]=stability.build_mixed_resource_devices(s.case_data,s.resources, ...
    s.scenario_opt);
dae=stability.composite_dae(s.case_data,devices);
hs=stability.ts_hybrid_state_init(devices);
key=matlab.lang.makeValidName(devices(1).device_id);
hs.device_online.(key)=false;
for k=2:numel(devices)
    hs.device_modes.(matlab.lang.makeValidName(devices(k).device_id))='GFM';
end
init=stability.mixed_ibr_reduced_initialize(dae, ...
    struct('hybrid_state',hs),2,struct('verbose',false));
verifyTrue(testCase,init.applicable, ...
    sprintf('reduced initializer must accept the decoupled island (%s)', ...
    init.failure_id));
verifyNotEqual(testCase,char(init.failure_id), ...
    'mixed_ibr_reduced_initialize:notPureIBRIsland');
end

function testModeAwareSourceDispatchIsSelectedForTheFamily(testCase)
% Silent-hazard registration in ibr_candidate_evaluate: if the family is not
% recognised as a project full-state model, the SG-off candidate evaluation
% silently falls back to a different dispatch and therefore a different
% operating point.  Deterministic oracle: mode_aware_source_dispatch FAILS
% CLOSED with a stable identifier when the case lacks the required dispatch
% contract, so stripping that contract must produce that identifier -- which
% can only happen if the family entered the mode-aware branch.
s=cases.scenario_ieee14_1sg_4ibr(struct('case_profile','decoupled_figure4'));
cd_stripped=s.case_data;
cd_stripped.dispatch_contract=struct('pre_fault',struct());
resources=s.resources;
for k=2:5, resources(k).modes={'GFM'}; end
cand=struct('selected_gfm_indices',2:5,'reference_resource_index',2, ...
    'n_gfm_required',4,'resource_ids',{{resources.resource_id}}, ...
    'modes',{{'breaker_open','GFM','GFM','GFM','GFM'}}, ...
    'online',[false true true true true], ...
    'resource_type',{{resources.resource_type}}, ...
    'n_mode_changes',4,'tie_break',0,'ordering_key',1);
out=@()stability.ibr_candidate_evaluate(cd_stripped,resources,cand,struct(), ...
    0.1,struct('sg_online_context',false));
verifyError(testCase,out, ...
    'stability:ibr_candidate_evaluate:missingModeAwareDispatch', ...
    'the decoupled family must use the mode-aware source dispatch');
% Control: the baseline family must reach the same branch, so the assertion is
% about family recognition and not about some other property of this case.
sb=cases.scenario_ieee14_1sg_4ibr(struct('case_profile','eecon49_figure4'));
cdb=sb.case_data; cdb.dispatch_contract=struct('pre_fault',struct());
rb=sb.resources; for k=2:5, rb(k).modes={'GFM'}; end
candb=cand; candb.resource_ids={rb.resource_id};
verifyError(testCase,@()stability.ibr_candidate_evaluate(cdb,rb,candb, ...
    struct(),0.1,struct('sg_online_context',false)), ...
    'stability:ibr_candidate_evaluate:missingModeAwareDispatch');
end

function testAllGflEquilibriumAndSpectrumMatchBaselineExactly(testCase)
% In all-GFL the whole GFM branch is inactive on BOTH families, so the two
% profiles must be physically indistinguishable: same plant, same GFL
% controller, same network solution. The two supersets are NOT coordinate-wise
% identical -- the decoupled family's index 17 is its own washout state
% gfm_omega_f (frozen in all-GFL), while the baseline family's index 17 is the
% Thevenin source current I_dc (a state there, algebraic here) -- so equality
% is asserted on the coordinates the two families actually share: the plant
% and GFL block 1:9 per device, and the full algebraic vector. The reduced
% spectra must still agree, because the frozen washout rows are eliminated
% before eig and the baseline's I_dc row is dynamically decoupled from the AC
% states (the one-way DC coupling measured in NUM-2026-08-20-01), so neither
% family's extra coordinate can move an AC mode. Any difference WOULD mean a
% leak between the families' shared GFL path.
[eqd,sssad,devd]=solve_profile('decoupled_figure4',[],[]);
[eqb,sssab,devb]=solve_profile('eecon49_figure4',[],[]);
verifyTrue(testCase,eqd.converged==1);
verifyTrue(testCase,eqb.converged==1);
verifyLessThan(testCase,eqd.residual_norm,1e-8);
% Both families build the same 17-vector superset per IBR and the same 74-vector
% system vector (measured, not assumed: SG 6 + 4x17).
verifyEqual(testCase,[devd(2:end).nx],[17 17 17 17]);
verifyEqual(testCase,[devb(2:end).nx],[17 17 17 17]);
verifyEqual(testCase,numel(eqd.x0),74);
verifyEqual(testCase,numel(eqb.x0),74);
% The families differ ONLY in which per-device coordinates are frozen in
% all-GFL (measured partitions): the decoupled family freezes its 7 GFM states
% PLUS its washout state 17 (9 active), while the baseline freezes its 7 GFM
% states and keeps I_dc=17 ACTIVE (10 active). The shared coordinates -- per
% device 1:9, plant + GFL controller, identical layout in both supersets --
% must match bit-for-bit; the frozen washouts must sit at their initial 1.
wf=washout_global_indices(devd);
% The washout state is FROZEN in all-GFL (measured partition: the decoupled
% family freezes its 7 GFM states plus the washout, 9 active per device), so
% the four washout coordinates are frozen in the equilibrium: none of them may
% appear in the active set, and each must sit at its initial value 1.
verifyEqual(testCase,numel(wf),4);
verifyEqual(testCase,numel(ismember(wf,eqd.active_state_indices)),4);
verifyFalse(testCase,any(ismember(wf,eqd.active_state_indices)), ...
    'no washout coordinate may be active in all-GFL');
verifyEqual(testCase,eqd.x0(wf),ones(4,1),'AbsTol',0, ...
    'frozen washouts sit at their initial value 1');
% Device offsets over the FULL device vector (SG1 first), matching the global
% state layout; device k's block starts at off(k-1)+1 with off(1)=0.
off_d=[0 cumsum([devd(1:end-1).nx])];
off_b=[0 cumsum([devb(1:end-1).nx])];
for k=2:numel(devd)
    gd=off_d(k)+(1:9); gb=off_b(k)+(1:9);
    verifyEqual(testCase,eqd.x0(gd),eqb.x0(gb),'AbsTol',0, ...
        sprintf('device %d shared plant+GFL block must match bit-for-bit',k));
end
verifyEqual(testCase,eqd.x0(wf),ones(4,1),'AbsTol',0);
verifyEqual(testCase,eqd.y0,eqb.y0,'AbsTol',0, ...
    'the network solution must be identical');
% Reduced spectra (measured on this tree, all-GFL): the baseline carries the
% Thevenin source current as a STATE, giving 8 DC-family roots (4 conjugate
% pairs near -96..-99 s^-1); the decoupled family's algebraic source gives 4
% real DC roots near -95..-98 s^-1. The AC roots agree to FD accuracy because
% both DC families are one-way-coupled FROM the AC states
% (NUM-2026-08-20-01). The oracle therefore asserts: same root COUNT minus the
% 4-coordinate difference, every AC root of one family present in the other,
% and the DC families each within their predicted band.
lam_d=sort(real(sssad.physical_eigenvalues));
lam_b=sort(real(sssab.physical_eigenvalues));
verifyEqual(testCase,numel(lam_d),numel(lam_b)-4);
% AC agreement: every root slower than -50 s^-1 must match one-for-one.
ac_d=lam_d(lam_d>-50); ac_b=lam_b(lam_b>-50);
verifyEqual(testCase,numel(ac_d),numel(ac_b), ...
    'the AC root count must be identical');
verifyEqual(testCase,ac_d,ac_b,'AbsTol',1e-8, ...
    'the AC spectrum must be family-independent (one-way DC coupling)');
% DC difference by ROOT MATCHING (the same oracle the measured probe used):
% a root of one family is "matched" if the other family has a root within
% 1e-6. Every AC root matches; the UNMATCHED roots are exactly the DC family
% of each side -- 4 real roots for the algebraic source, 8 roots (4 conjugate
% pairs) for the state source. This is stronger and cleaner than a band count,
% which would also sweep in the unrelated fast roots near -100..-2000 s^-1.
tol=1e-6;
matched_d=false(size(lam_d)); matched_b=false(size(lam_b));
for a=1:numel(lam_d)
    hit=find(abs(lam_b-lam_d(a))<=tol & ~matched_b,1);
    if ~isempty(hit), matched_d(a)=true; matched_b(hit)=true; end
end
unmatched_d=lam_d(~matched_d); unmatched_b=lam_b(~matched_b);
verifyEqual(testCase,numel(unmatched_d),4, ...
    'the algebraic source contributes exactly 4 unmatched DC roots');
verifyEqual(testCase,numel(unmatched_b),8, ...
    'the state source contributes exactly 8 unmatched DC roots');
verifyTrue(testCase,all(unmatched_d<-50),'decoupled DC roots are fast');
verifyTrue(testCase,all(unmatched_b<-50),'baseline DC roots are fast');
% And the AC roots that DID match must agree tightly (already asserted above
% through the -50 cut; the matching tolerance here is the same 1e-6).
end

function testAllGfmSpectrumAddsExactlyFourWashoutModesAtZeroDamping(testCase)
% Full-system counterpart of the single-machine factorisation oracle: at the
% production D_t = 0 the four washout states must be dynamically inert, so the
% SG-online all-GFM reduced spectrum is the baseline spectrum plus exactly four
% eigenvalues at -wD. A deliberately non-default D_t must then move the swing
% rows by exactly -D_t/M, which is what proves the knob is wired to the equation
% it claims -- while max Re stays put, which is the measured reason the knob has
% no beneficial setting on this network (contract section 7a).
wD=50.0; M=0.08; Dt=20.0;
[eq0,s0,~]=solve_profile('decoupled_figure4',2:5,0.0);
[eqb,sb,~]=solve_profile('eecon49_figure4',2:5,[]);
[eqp,sp,~]=solve_profile('decoupled_figure4',2:5,Dt);
verifyTrue(testCase,eq0.converged==1 && eqb.converged==1 && eqp.converged==1);
% Measured partitions (GATE-2026-08-25-02 correction): in all-GFM BOTH families
% activate 11 states per converter -- the decoupled family's 11th is its
% washout state, the baseline's is its Thevenin source current I_dc -- so the
% active COUNTS are equal, and the spectra differ in WHERE the extra DC
% coordinate puts its poles, not in how many roots exist.
verifyEqual(testCase,s0.nx_active,sb.nx_active);
verifyEqual(testCase,sp.nx_active,s0.nx_active);
lam0=s0.physical_eigenvalues(:);
% The washout pole sits at -wD analytically, but the spectrum comes from an
% FD-linearised matrix, so the pole carries a small imaginary residue; the
% window is therefore placed on the REAL part and sized to FD accuracy
% (measured: all four poles land within 1e-5 of -50 in real part).
at_wD=abs(real(lam0)-(-wD))<1e-3;
verifyEqual(testCase,sum(at_wD),4, ...
    'exactly four washout eigenvalues must sit at -wD when D_t=0');
% The remaining decoupled roots must match the baseline one-for-one except the
% baseline's four I_dc conjugate pairs, which the algebraic source replaces
% with four real -1/T_dc roots (both unmatched sets measured).
rest=lam0(~at_wD);
tol=1e-6;
mb=false(size(sb.physical_eigenvalues));
for a=1:numel(rest)
    hit=find(abs(sb.physical_eigenvalues-rest(a))<=tol & ~mb,1);
    if ~isempty(hit), mb(hit)=true; end
end
un=sb.physical_eigenvalues(~mb);
verifyEqual(testCase,numel(un),8, ...
    'the baseline differs exactly by its four I_dc conjugate pairs');
verifyTrue(testCase,all(real(un)<-50),'those roots must be the fast DC family');
md=false(size(lam0));
for a=1:numel(sb.physical_eigenvalues)
    hit=find(abs(lam0-sb.physical_eigenvalues(a))<=tol & ~md,1);
    if ~isempty(hit), md(hit)=true; end
end
und=sort(real(lam0(~md)));
verifyEqual(testCase,numel(und),8, ...
    'the decoupled family differs exactly by its eight own DC/washout roots');
verifyEqual(testCase,und(1:4),-50.0*ones(4,1),'AbsTol',1e-3, ...
    'the washout poles sit at -wD (sorted first: -50 < -10)');
verifyEqual(testCase,und(5:8),-10.0*ones(4,1),'AbsTol',1e-3, ...
    'the algebraic-source roots sit at -1/T_dc');
% A nonzero D_t must move the spectrum by exactly what the equation declares.
% The invariant to use is the SUM of real parts, not the shift of any single
% mode: D_t enters only the diagonal entry d(dom_i)/d(om_i) = -(1/R+D_t)/M of
% each of the four devices, and it does not touch the algebraic block, so the
% Schur-reduced trace must move by exactly -4*D_t/M. Individual modes share that
% total differently depending on how close the washout pole sits to them, which
% is precisely the sensitivity that made wD placement matter.
d=sort(real(sp.physical_eigenvalues)); e=sort(real(s0.physical_eigenvalues));
verifyEqual(testCase,sum(d)-sum(e),-4*Dt/M,'RelTol',1e-6, ...
    'the trace must move by exactly -4*D_t/M (four devices)');
verifyLessThan(testCase,min(d-e),-1e-3, ...
    'at least one mode must actually move');
% Measured property of THIS network, and the reason the production D_t is 0:
% the modes D_t owns are far from the dominant one, so the SG-online margin does
% not improve. If a future change makes D_t improve this margin, that is a real
% finding and this assertion should be revisited with evidence -- not deleted.
verifyLessThan(testCase,max(real(sp.physical_eigenvalues)),0);
verifyEqual(testCase,max(real(sp.physical_eigenvalues)), ...
    max(real(sb.physical_eigenvalues)),'AbsTol',1e-4, ...
    'D_t must not move the SG-online dominant mode on this network');
end

function testIslandSpectrumEqualsBaselineAtProductionDefaults(testCase)
% System-level oracle for the production configuration, added 2026-08-13 after
% the measured island surface forced D_t back to 0.
%
% Two facts are pinned, both through the PRODUCTION candidate path
% (stability.ibr_candidate_evaluate with the frozen gamma_req = 0.1), because
% that is what the SG-trip transaction actually consults before committing:
%   1. at the production defaults the authenticated all-four ISLAND must be
%      certified and must match the coupled baseline's margin -- if a future
%      edit reintroduces a positive default D_t, or changes wD in a way that
%      moves the island margin, this fails;
%   2. the withdrawn (wD=3.0, D_t=20) pair must still be REFUSED, so the
%      recorded failure mode cannot be quietly re-enabled and forgotten.
base=island_candidate('eecon49_figure4',[]);
prod=island_candidate('decoupled_figure4',[]);
verifyTrue(testCase,base.ready_to_commit, ...
    'the coupled baseline island must remain certified (control)');
verifyTrue(testCase,prod.ready_to_commit, ...
    'the decoupled island must be certified at the production defaults');
verifyEqual(testCase,prod.omega,base.omega,'AbsTol',1e-7, ...
    ['at D_t=0 the island margin must equal the coupled baseline: the swing ' ...
     'block reduces to it exactly']);
% The gate criterion is the declared damping-ratio floor (GATE-2026-08-25-01),
% not the absolute rate: assert the certified margin through the same quantity
% the gate itself consumes, and keep the old rate bound as a weaker sanity
% statement. The island's omega is a real negative root, so its ratio is 1 and
% the ratio floor is satisfied by construction; the meaningful check here is
% that the margin is comfortably stable and unchanged from the baseline.
verifyLessThan(testCase,prod.omega,-0.1);
verifyTrue(testCase,prod.zeta_worst >= prod.zeta_min, ...
    'the certified island must pass the declared damping-ratio criterion');
% The documented failure mode: wD on the island swing mode with a large D_t.
bad=island_candidate('decoupled_figure4',struct('D_t',20.0,'wD',3.0));
verifyFalse(testCase,bad.ready_to_commit, ...
    'the withdrawn (wD=3.0, D_t=20) pair must stay refused');
verifyGreaterThan(testCase,bad.omega,0, ...
    'that pair puts the island in the right half plane; keep the record honest');
end

function c=island_candidate(prof,override)
s=cases.scenario_ieee14_1sg_4ibr(struct('case_profile',prof));
resources=s.resources;
if ~isempty(override)
    for k=2:numel(resources)
        if isfield(resources(k).dynamic_params,'gfm_decoupled')
            for f=fieldnames(override).'
                resources(k).dynamic_params.gfm_decoupled.(f{1})=override.(f{1});
            end
        end
    end
end
scr=stability.ibr_scr_metrics(s.case_data,resources,struct());
cand=struct('selected_gfm_indices',2:5,'reference_resource_index',2, ...
    'n_gfm_required',4,'resource_ids',{{resources.resource_id}}, ...
    'modes',{{'breaker_open','GFM','GFM','GFM','GFM'}}, ...
    'online',[false true true true true], ...
    'resource_type',{{resources.resource_type}}, ...
    'n_mode_changes',4,'tie_break',0,'ordering_key',1);
c=stability.ibr_candidate_evaluate(s.case_data,resources,cand,scr,0.1, ...
    struct('sg_online_context',false));
end

% -------------------------------------------------------------------------
function idx=washout_global_indices(devices)
off=[0 cumsum([devices(1:end-1).nx])];
idx=[];
for k=1:numel(devices)
    nm=cellstr(string(devices(k).state_names));
    j=find(strcmp(nm,'gfm_omega_f'),1);
    if ~isempty(j), idx(end+1,1)=off(k)+j; end %#ok<AGROW>
end
end

function [eq,sssa,devices]=solve_profile(prof,gfm_sel,Dt_override)
s=cases.scenario_ieee14_1sg_4ibr(struct('case_profile',prof));
resources=s.resources;
for k=2:numel(resources)
    if ~isempty(gfm_sel) && any(gfm_sel==k)
        resources(k).initial_mode='GFM';
    end
    if ~isempty(Dt_override) && isfield(resources(k),'dynamic_params') && ...
            isfield(resources(k).dynamic_params,'gfm_decoupled')
        resources(k).dynamic_params.gfm_decoupled.D_t=Dt_override;
    end
end
[devices,~]=stability.build_mixed_resource_devices(s.case_data,resources, ...
    s.scenario_opt);
cfg=struct('devices',devices);
% The reference owner of an SG-off island is the committed grid-forming
% converter (resource 2), exactly as the production candidate path
% (island_candidate below) and the delivered chronology use. The earlier
% ref=1 named the TRIPPED synchronous machine as the angle reference, which
% is not a defensible gauge for an island it no longer energises, and the
% resulting gauge quotient displaced the washout poles from -wD (measured:
% zero poles at -wD with ref=1, exactly four with ref=2).
ref=2;
if ~isempty(gfm_sel)
    hs=stability.ts_hybrid_state_init(devices);
    hs.selected_gfm_indices=gfm_sel;
    hs.n_gfm_required=numel(gfm_sel);
    hs.reference_resource_index=ref;
    hs.committed_selection=struct('selected_gfm_indices',gfm_sel, ...
        'n_gfm_required',numel(gfm_sel),'reference_resource_index',ref);
    cfg.hybrid_state=hs;
    cfg.selected_gfm_indices=gfm_sel;
    cfg.n_gfm_required=numel(gfm_sel);
    cfg.reference_resource_index=ref;
    cfg.resource_ids={devices.device_id};
end
eq=stability.mixed_equilibrium_solve(s.case_data,cfg,struct('verbose',false, ...
    'tolerance',1e-8,'max_iter',300,'load_model','cz_p_cz_q'));
o=struct('full_kcl',true,'u_eq',eq.u_eq,'event_context',eq.equilibrium_context, ...
    'active_state_indices',eq.active_state_indices,'reference_device_index',ref);
if isfield(eq,'active_bound_regime_history') && ~isempty(eq.active_bound_regime_history)
    o.active_bound_regimes=eq.active_bound_regime_history{end};
end
sssa=stability.composite_sssa_model(devices,eq.x0,eq.y0,s.case_data,o);
end
