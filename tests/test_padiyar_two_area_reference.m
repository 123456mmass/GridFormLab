function tests=test_padiyar_two_area_reference
tests=functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths;
end

function test_case_manifest(testCase)
c=cases.case_padiyar_two_area_4m_avr();
verifySize(testCase,c.bus_data,[10 12]); verifySize(testCase,c.line_data,[15 7]);
verifyEqual(testCase,[c.machines.units.bus],[1 2 11 12]);
verifyEqual(testCase,[c.machines.units.H],[54 54 63 63]);
verifyEqual(testCase,c.machines.reactances.Xl,0.022,'AbsTol',1e-14);
verifyEqual(testCase,c.machines.reactances.Ra,0.00028,'AbsTol',1e-14);
verifyEqual(testCase,c.machines.reactances.Xd,0.2,'AbsTol',1e-14);
verifyEqual(testCase,c.machines.reactances.Xdp,0.033,'AbsTol',1e-14);
verifyEqual(testCase,c.machines.reactances.Xq,0.19,'AbsTol',1e-14);
verifyEqual(testCase,c.machines.reactances.Xqp,0.061,'AbsTol',1e-14);
verifyEqual(testCase,c.machines.exciter.KA,200,'AbsTol',1e-14);
verifyEqual(testCase,c.machines.exciter.TA,0.02,'AbsTol',1e-14);
verifyFalse(testCase,isfield(c.machines.reactances,'Xdpp'), ...
    'The Padiyar source does not provide subtransient data.');
end

function test_power_flow_reproduces_table_9_2(testCase)
c=cases.case_padiyar_two_area_4m_avr();
r=pfsolver.powerflow_newton_raphson(c,struct('verbose',false,'plot_results',false, ...
    'enforce_q_limits',false,'tolerance',1e-11));
verifyTrue(testCase,r.converged); [ok,ix]=ismember(c.operating_point.printed_bus_ids,r.external_bus_ids);
verifyTrue(testCase,all(ok));
verifyLessThan(testCase,max(abs(r.bus_voltage(ix)-c.operating_point.printed_V)),1e-4);
verifyLessThan(testCase,max(abs(r.bus_angle_deg(ix)-c.operating_point.printed_angle_deg)),1e-4);
verifyLessThan(testCase,max(abs(r.P_generation(ix)-c.operating_point.printed_Pg)),1e-4);
verifyLessThan(testCase,max(abs(r.Q_generation(ix)-c.operating_point.printed_Qg)),1e-4);
end

function test_avr_dae_equilibrium_and_order(testCase)
d=stability.padiyar_model11_dae([],struct('excitation','avr'));
verifyEqual(testCase,d.ns,5); verifyEqual(testCase,numel(d.x0),20);
verifyLessThan(testCase,d.initial_residual_f,1e-10);
verifyLessThan(testCase,d.initial_residual_g,1e-10);
verifyEqual(testCase,d.electrical_power(d.x0,d.y0),d.init.Pm,'AbsTol',1e-10);
end

function test_manual_dae_equilibrium_and_order(testCase)
d=stability.padiyar_model11_dae([],struct('excitation','manual'));
verifyEqual(testCase,d.ns,4); verifyEqual(testCase,numel(d.x0),16);
verifyLessThan(testCase,d.initial_residual,1e-10);
end

function test_table_9_5_diagnostic_comparison(testCase)
% DIAGNOSTIC-ONLY: exercise the Table 9.5 comparison pipeline and verify the
% pipeline is well-formed (finite metrics, unique one-to-one matching, correct
% dimensions, declared reference provenance, no solver mutation). This test
% does NOT assert that computed eigenvalues are within any book tolerance.
% Padiyar Table 9.5 is an external published reference, a secondary
% cross-check only; required_for_acceptance is always false.
c=cases.case_padiyar_two_area_4m_avr();
r0=stability.padiyar_model11_ssa(c,struct('excitation','avr','fd_eps',1e-6));
% Snapshot the solver result BEFORE the comparison so we can prove the
% comparison helper did not mutate it.
Afull_before=r0.Afull;
eig_before=r0.eigenvalues(:);
ref=c.reference.table95_eigenvalues(:);
% The printed near-zero pair (|lambda|<=0.01) is explicitly attributed by
% Padiyar to load-flow/numerical error; exclude it by a pre-declared
% structural rule before matching the physical roots one-to-one.
ref=ref(abs(ref)>0.01); got=r0.eigenvalues(abs(r0.eigenvalues)>0.01);
verifyTrue(testCase,all(isfinite(ref)),'reference eigenvalues finite');
verifyTrue(testCase,all(isfinite(got)),'computed eigenvalues finite');
cmp=table95_comparison(got,ref);
% Pipeline integrity (NOT a proximity gate to the book):
verifyTrue(testCase,all(isfinite(cmp.absolute_errors)),'absolute_errors finite');
verifyTrue(testCase,all(isfinite(cmp.relative_errors)),'relative_errors finite');
verifyEqual(testCase,numel(cmp.matched_ref_idx),numel(cmp.matched_got_idx), ...
    'matched index vectors same length');
verifyTrue(testCase,all(cmp.matched_ref_idx>0) && all(cmp.matched_got_idx>0), ...
    'matched indices positive');
verifyEqual(testCase,numel(unique(cmp.matched_ref_idx)),numel(cmp.matched_ref_idx), ...
    'reference match indices unique (no duplicate)');
verifyEqual(testCase,numel(unique(cmp.matched_got_idx)),numel(cmp.matched_got_idx), ...
    'computed match indices unique (no duplicate)');
verifyEqual(testCase,numel(cmp.absolute_errors),min(numel(ref),numel(got)), ...
    'error vector length = min(#ref,#computed)');
verifyTrue(testCase,isfield(cmp,'required_for_acceptance') && ...
    cmp.required_for_acceptance==false, ...
    'Table 9.5 comparison is NOT required for acceptance');
verifyTrue(testCase,~isempty(cmp.reference_name),'reference_name present');
verifyTrue(testCase,~isempty(cmp.reference_source),'reference_source present');
verifyTrue(testCase,~isempty(cmp.matching_method),'matching_method present');
% The comparison must not mutate the solver result.
verifyEqual(testCase,r0.Afull,Afull_before,'AbsTol',0, ...
    'comparison does not mutate Afull');
verifyEqual(testCase,r0.eigenvalues(:),eig_before,'AbsTol',0, ...
    'comparison does not mutate eigenvalues');
% Report the observed maximum absolute difference (informational, not gated).
fprintf('  Table 9.5 diagnostic: max matched |delta|=%.3e, #matched=%d, #unmatched_ref=%d\n', ...
    max([0; cmp.absolute_errors]), numel(cmp.matched_ref_idx), numel(cmp.unmatched_reference));
end

function test_reference_eigenvalues_do_not_drive_sssa(testCase)
% Falsification test: corrupting the published comparison data must not alter
% the computed state matrix or eigenvalues.
c=cases.case_padiyar_two_area_4m_avr();
r1=stability.padiyar_model11_ssa(c,struct('excitation','avr','fd_eps',1e-6));
c.reference.table95_eigenvalues=(101:120).'+1i*(201:220).';
r2=stability.padiyar_model11_ssa(c,struct('excitation','avr','fd_eps',1e-6));
verifyEqual(testCase,r2.Afull,r1.Afull,'AbsTol',1e-12);
verifyEqual(testCase,sort(r2.eigenvalues),sort(r1.eigenvalues),'AbsTol',1e-12);
end

function test_printed_reference_data_does_not_drive_pf(testCase)
% Falsification test: corrupting the Padiyar Table 9.2 comparison copies
% (printed_V/angle/Pg/Qg) and the Table 9.5 eigenvalue reference must NOT
% alter the PF result. Only COMPARISON-ONLY fields are corrupted; physical
% inputs (bus_data, line_data) are untouched. A deterministic solver with
% unchanged inputs returns identical results to machine precision.
c=cases.case_padiyar_two_area_4m_avr();
opt=struct('verbose',false,'plot_results',false,'enforce_q_limits',false,'tolerance',1e-11);
r1=pfsolver.powerflow_newton_raphson(c,opt);
c2=c;
c2.operating_point.printed_V=(0.5:0.1:1.4).';
c2.operating_point.printed_angle_deg=(-50:5:-5).';
c2.operating_point.printed_Pg=rand(10,1)*10;
c2.operating_point.printed_Qg=rand(10,1)*5;
c2.reference.table95_eigenvalues=(101:120).'+1i*(201:220).';
r2=pfsolver.powerflow_newton_raphson(c2,opt);
verifyEqual(testCase,r2.converged,r1.converged);
verifyEqual(testCase,r2.iterations,r1.iterations);
verifyEqual(testCase,r2.mismatch_history,r1.mismatch_history,'AbsTol',1e-12);
verifyEqual(testCase,r2.Ybus,r1.Ybus,'AbsTol',1e-12);
verifyEqual(testCase,r2.bus_voltage,r1.bus_voltage,'AbsTol',1e-12);
verifyEqual(testCase,r2.bus_angle_deg,r1.bus_angle_deg,'AbsTol',1e-12);
verifyEqual(testCase,r2.P_generation,r1.P_generation,'AbsTol',1e-12);
verifyEqual(testCase,r2.Q_generation,r1.Q_generation,'AbsTol',1e-12);
end

function test_no_fault_ts_equilibrium(testCase)
for excitation={'manual','avr'}
    r=stability.ts_simulate_padiyar_model11([],struct('excitation',excitation{1}, ...
        'fault_enabled',false,'t_end',1,'dt',0.01));
    verifyEqual(testCase,r.nonconverged_step_count,0);
    verifyLessThan(testCase,r.initial_dae_residual,1e-10);
    verifyLessThan(testCase,max(abs(r.delta-r.delta(1,:)),[],'all'),1e-10);
    verifyLessThan(testCase,max(abs(r.omega-r.omega(1,:)),[],'all'),1e-10);
    verifyLessThan(testCase,max(abs(r.Vbus-r.Vbus(1,:)),[],'all'),1e-10);
  end
end

function test_project_fault_scenario_converges(testCase)
for excitation={'manual','avr'}
    r=stability.ts_simulate_padiyar_model11([],struct('excitation',excitation{1}, ...
        'fault_enabled',true,'fault_bus',3,'Zf',1i*0.5,'t_fault',1, ...
        't_clear',1.1,'t_end',2,'dt',0.005));
    verifyEqual(testCase,r.nonconverged_step_count,0);
    verifyTrue(testCase,all(isfinite(r.delta),'all'));
    verifyTrue(testCase,all(isfinite(r.Vbus),'all'));
  end
end

function test_table_9_5_matching_permutation_invariant(testCase)
% Provable invariant under reordering of either input. The matching helper is
% a deterministic greedy successive-minimum one-to-one matching (NOT a global
% optimum assignment). It does NOT guarantee a global minimum total cost, and
% the specific (ref_idx, got_idx) pairing can change when reference or
% computed eigenvalues have equal or near-equal distances. The property that
% DOES hold — and is what this guard verifies — is that the SORTED MULTISET of
% absolute errors is invariant to the ordering of either input, match counts
% are preserved, and matched indices remain unique (one-to-one). This is the
% diagnostic invariant; the matching is used for reporting only, never as an
% acceptance gate.
c=cases.case_padiyar_two_area_4m_avr();
r=stability.padiyar_model11_ssa(c,struct('excitation','avr','fd_eps',1e-6));
ref=c.reference.table95_eigenvalues(:); ref=ref(abs(ref)>0.01);
got=r.eigenvalues(abs(r.eigenvalues)>0.01);
cmp0=table95_comparison(got,ref);
% Permute computed order.
rng(1,'twister');
pg=randperm(numel(got));
cmp_g=table95_comparison(got(pg),ref);
% Permute reference order.
pr=randperm(numel(ref));
cmp_r=table95_comparison(got,ref(pr));
% Sorted absolute-error multiset must match exactly (this is the
% order-independent property the diagnostic relies on).
verifyEqual(testCase,sort(cmp0.absolute_errors),sort(cmp_g.absolute_errors), ...
    'AbsTol',1e-14,'computed-order permutation changes error multiset');
verifyEqual(testCase,sort(cmp0.absolute_errors),sort(cmp_r.absolute_errors), ...
    'AbsTol',1e-14,'reference-order permutation changes error multiset');
% Permutation must not change how many modes matched / went unmatched.
verifyEqual(testCase,numel(cmp_g.matched_ref_idx),numel(cmp0.matched_ref_idx), ...
    'computed-order permutation changes match count');
verifyEqual(testCase,numel(cmp_r.matched_ref_idx),numel(cmp0.matched_ref_idx), ...
    'reference-order permutation changes match count');
% Indices must remain unique (one-to-one) under permutation.
verifyEqual(testCase,numel(unique(cmp_g.matched_got_idx)),numel(cmp_g.matched_got_idx), ...
    'permuted computed indices still unique');
verifyEqual(testCase,numel(unique(cmp_r.matched_ref_idx)),numel(cmp_r.matched_ref_idx), ...
    'permuted reference indices still unique');
end

function test_table_9_5_matching_conjugate_order_invariant(testCase)
% Conjugate pairs are an ordering ambiguity (which member of the pair is
% listed first). Swapping the order of a conjugate pair in the reference
% must not change the diagnostic metrics.
c=cases.case_padiyar_two_area_4m_avr();
r=stability.padiyar_model11_ssa(c,struct('excitation','avr','fd_eps',1e-6));
ref=c.reference.table95_eigenvalues(:); ref=ref(abs(ref)>0.01);
got=r.eigenvalues(abs(r.eigenvalues)>0.01);
cmp0=table95_comparison(got,ref);
% Swap the two members of the first conjugate pair found in the reference.
ref_swap=ref; done=false;
for k=1:numel(ref)-1
    if abs(ref(k+1)-conj(ref(k)))<1e-9 && abs(imag(ref(k)))>1e-9
        ref_swap([k k+1])=ref([k+1 k]); done=true; break;
    end
end
verifyTrue(testCase,done,'found a conjugate pair to swap in the reference');
cmp_s=table95_comparison(got,ref_swap);
verifyEqual(testCase,sort(cmp0.absolute_errors),sort(cmp_s.absolute_errors), ...
    'AbsTol',1e-14,'conjugate-pair reorder changes errors');
end

function test_table_9_5_matching_nan_input_reports_failure(testCase)
% NaN/Inf inputs must be flagged, not silently paired to give misleading
% finite metrics.
got=[NaN; -1+1i; Inf]; ref=[-1+1i; -2; -3];
cmp=table95_comparison(got,ref);
verifyTrue(testCase,cmp.invalid_input,'NaN/Inf input sets invalid_input flag');
verifyTrue(testCase,all(isnan(cmp.absolute_errors)), ...
    'absolute_errors are NaN on invalid input');
verifyEmpty(testCase,cmp.matched_ref_idx,'no matches on invalid input');
end

function test_table_9_5_matching_unmatched_modes_reported(testCase)
% When counts differ, the comparison must report unmatched modes, not
% silently drop them.
got=[-1+1i; -2-1i]; ref=[-1+1i; -2-1i; -3+0.5i];
cmp=table95_comparison(got,ref);
verifyEqual(testCase,numel(cmp.matched_ref_idx),2,'matched count');
verifyEqual(testCase,numel(cmp.unmatched_reference),1, ...
    'one unmatched reference mode reported');
verifyEqual(testCase,numel(cmp.unmatched_computed),0, ...
    'no unmatched computed modes (got shorter)');
end

function test_table_9_5_matching_no_duplicate_indices(testCase)
% Explicit guard: each computed eigenvalue is matched to at most one
% reference eigenvalue and vice versa.
c=cases.case_padiyar_two_area_4m_avr();
r=stability.padiyar_model11_ssa(c,struct('excitation','avr','fd_eps',1e-6));
ref=c.reference.table95_eigenvalues(:); ref=ref(abs(ref)>0.01);
got=r.eigenvalues(abs(r.eigenvalues)>0.01);
cmp=table95_comparison(got,ref);
verifyEqual(testCase,numel(unique(cmp.matched_ref_idx)),numel(cmp.matched_ref_idx), ...
    'reference match indices unique');
verifyEqual(testCase,numel(unique(cmp.matched_got_idx)),numel(cmp.matched_got_idx), ...
    'computed match indices unique');
end

function cmp=table95_comparison(got,ref)
%TABLE95_COMPARISON  Diagnostic-only comparison of computed vs published eigenvalues.
%   Returns a metadata-rich struct. required_for_acceptance is ALWAYS false:
%   Padiyar Table 9.5 is an external published reference used as a secondary
%   cross-check, never a fitted target or a numerical acceptance gate.
%
%   Matching is a deterministic greedy successive-minimum one-to-one matching
%   over the full |complex distance| matrix with mutual exclusion (base MATLAB
%   only; no Hungarian/toolbox assignment solver). This is GREEDY: at each
%   iteration it takes the global minimum of the remaining matrix, then marks
%   that row/column used. It does NOT guarantee a global minimum total cost
%   (a Hungarian solver could yield a lower total by accepting a locally
%   suboptimal pairing). The specific (ref_idx, computed_idx) pairing can
%   change when reference or computed eigenvalues have equal or near-equal
%   distances; only the SORTED absolute-error multiset is invariant to the
%   ordering of either input. The metric is absolute complex distance
%   |lambda_computed - lambda_book|. Used for diagnostic reporting only;
%   never an acceptance gate (see test_table_9_5_matching_permutation_invariant
%   and the guard test_no_table95_acceptance_gate).
ref=ref(:); got=got(:);
cmp.reference_name='Padiyar Table 9.5';
cmp.reference_source='Padiyar, Power System Dynamics (2nd ed.), Sec. 9.6.1';
cmp.matching_method='deterministic greedy successive-minimum one-to-one matching';
cmp.matching_metric='absolute complex distance |lambda_computed - lambda_book|';
cmp.required_for_acceptance=false;
cmp.reference_values=ref;
cmp.computed_values=got;
if isempty(ref) || isempty(got)
    cmp.absolute_errors=[]; cmp.relative_errors=[];
    cmp.matched_ref_idx=[]; cmp.matched_got_idx=[];
    cmp.unmatched_reference=(1:numel(ref)).';
    cmp.unmatched_computed=(1:numel(got)).';
    return;
end
% NaN/Inf guard: report failure, do not return misleading metrics.
if any(~isfinite(ref)) || any(~isfinite(got))
    cmp.absolute_errors=NaN(numel(ref),1);
    cmp.relative_errors=NaN(numel(ref),1);
    cmp.matched_ref_idx=[]; cmp.matched_got_idx=[];
    cmp.unmatched_reference=(1:numel(ref)).';
    cmp.unmatched_computed=(1:numel(got)).';
    cmp.invalid_input=true;
    return;
end
cmp.invalid_input=false;
% Full distance matrix and greedy successive-minimum one-to-one matching
% with mutual exclusion (deterministic; no toolbox/Hungarian solver). Greedy,
% NOT global optimum: does not guarantee minimum total cost.
D=abs(got-ref.');  % numel(ref) x numel(got)
nmatch=min(numel(ref),numel(got));
abs_err=zeros(nmatch,1);
rel_err=zeros(nmatch,1);
matched_ref_idx=zeros(nmatch,1);
matched_got_idx=zeros(nmatch,1);
used_ref=false(numel(ref),1);
used_got=false(numel(got),1);
for k=1:nmatch
    Dk=D;
    Dk(used_ref,:)=inf;
    Dk(:,used_got)=inf;
    [dmin,lin]=min(Dk(:));
    [ir,ic]=ind2sub(size(Dk),lin);
    abs_err(k)=dmin;
    rel_err(k)=dmin/(abs(ref(ir))+eps);
    matched_ref_idx(k)=ir;
    matched_got_idx(k)=ic;
    used_ref(ir)=true;
    used_got(ic)=true;
end
% Sort matches by reference index for a stable, human-readable report.
[matched_ref_idx,order]=sort(matched_ref_idx);
matched_got_idx=matched_got_idx(order);
abs_err=abs_err(order);
rel_err=rel_err(order);
cmp.matched_ref_idx=matched_ref_idx(:);
cmp.matched_got_idx=matched_got_idx(:);
cmp.absolute_errors=abs_err(:);
cmp.relative_errors=rel_err(:);
cmp.unmatched_reference=find(~used_ref);
cmp.unmatched_computed=find(~used_got);
end
