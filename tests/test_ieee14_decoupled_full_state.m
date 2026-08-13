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
[bdev,~]=stability.build_mixed_resource_devices(sb.case_data,sb.resources, ...
    sb.scenario_opt);
verifyEqual(testCase,[bdev(2:end).nx],[16 16 16 16]);
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
% In all-GFL the whole GFM branch is inactive, so the decoupled profile must be
% numerically indistinguishable from the baseline profile: identical
% equilibrium on the shared states and an identical reduced spectrum.  Any
% difference would mean the appended state leaked into the GFL path.
[eqd,sssad,devd]=solve_profile('decoupled_figure4',[],[]);
[eqb,sssab,~]=solve_profile('eecon49_figure4',[],[]);
verifyTrue(testCase,eqd.converged==1);
verifyTrue(testCase,eqb.converged==1);
verifyLessThan(testCase,eqd.residual_norm,1e-8);
% Drop the appended washout entries and compare the rest bit-for-bit.
wf=washout_global_indices(devd);
verifyEqual(testCase,numel(wf),4);
shared=setdiff(1:numel(eqd.x0),wf);
verifyEqual(testCase,numel(shared),numel(eqb.x0));
verifyEqual(testCase,eqd.x0(shared),eqb.x0,'AbsTol',0);
verifyEqual(testCase,eqd.x0(wf),ones(4,1),'AbsTol',0);
verifyEqual(testCase,eqd.y0,eqb.y0,'AbsTol',0);
verifyEqual(testCase,sssad.nx_active,sssab.nx_active);
verifyEqual(testCase,sort(real(sssad.physical_eigenvalues)), ...
    sort(real(sssab.physical_eigenvalues)),'AbsTol',1e-12);
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
verifyEqual(testCase,s0.nx_active-sb.nx_active,4);
verifyEqual(testCase,sp.nx_active,s0.nx_active);
lam0=s0.physical_eigenvalues(:);
at_wD=abs(lam0-(-wD))<1e-8;
verifyEqual(testCase,sum(at_wD),4, ...
    'exactly four washout eigenvalues must sit at -wD when D_t=0');
rest=sort(real(lam0(~at_wD)));
verifyEqual(testCase,rest,sort(real(sb.physical_eigenvalues)),'AbsTol',1e-9);
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
verifyEqual(testCase,prod.omega,base.omega,'AbsTol',1e-9, ...
    ['at D_t=0 the island margin must equal the coupled baseline: the swing ' ...
     'block reduces to it exactly']);
verifyLessThan(testCase,prod.omega,-0.1);
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
ref=1;
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
