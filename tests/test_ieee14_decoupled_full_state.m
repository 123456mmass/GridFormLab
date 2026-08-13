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
verifyEqual(testCase,gp.D_t,20.0,'AbsTol',0);
verifyEqual(testCase,gp.wD,3.0,'AbsTol',0);
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
% Full-system counterpart of the single-machine factorisation oracle: with
% D_t = 0 the four washout states must be dynamically inert, so the all-GFM
% reduced spectrum is the baseline spectrum plus exactly four eigenvalues at
% -wD.  With the production D_t the spectrum must actually move, otherwise the
% damping knob would be inert in the coupled system.
wD=3.0; M=0.08; Dt=20.0;
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
% The production damping value must move the spectrum, and the largest shift
% must be the declared -D_t/M added to the swing damping rows.
d=sort(real(sp.physical_eigenvalues)); e=sort(real(s0.physical_eigenvalues));
shift=min(d-e);
verifyLessThan(testCase,shift,-1e-3, ...
    'the production D_t must damp the coupled system, not leave it unchanged');
verifyEqual(testCase,shift,-Dt/M,'RelTol',0.05, ...
    'the dominant shift must be the declared -D_t/M');
% Stability must not be degraded relative to the baseline configuration.
verifyLessThan(testCase,max(real(sp.physical_eigenvalues)),0);
verifyEqual(testCase,max(real(sp.physical_eigenvalues)), ...
    max(real(sb.physical_eigenvalues)),'AbsTol',1e-4);
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
