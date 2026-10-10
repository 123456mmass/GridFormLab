function tests=test_ne39_sg_reclose_rating
%TEST_NE39_SG_RECLOSE_RATING  Opt-in prospective close rating audit contract.
%   Covers only the opt-in augmented branch of
%   stability.sg_prospective_close_metrics: explicit PROJECT_DERIVED stator
%   rating on the system base, fail-closed behaviour when the rating is not
%   declared, refusal of invalid provenance, and the actual-vs-command
%   mechanical-power distinction. The legacy route's own tests are untouched.
tests=functiontests(localfunctions);
end

function setupOnce(tc)
% Snapshot the caller PATH and restore it verbatim on teardown. Removing the
% repository root with rmpath(root) would drop a path entry the caller may
% already have had, which broke the suites that run after this file.
p=path;
tc.addTeardown(@() path(p));
root=fileparts(fileparts(mfilename('fullpath')));
addpath(root,'-begin');
pf_init_paths();
end

function testOptinUsesExplicitRatedMvaOnSystemBase(tc)
% Declared 600 MVA rating on a 100 MVA system base with a 1000 MVA machine
% normalization base: the declared system-base rating decides the circle.
dev=augmented_device(0.50+0.10i,0.50,600);
m=run_metrics(dev,[0.50;1.0],case_data(100,1000));
tc.verifyEqual(m.rating_MVA,600,'AbsTol',0);
tc.verifyEqual(m.rating_system_pu,6.0,'AbsTol',1e-15);
tc.verifyEqual(m.rating_classification,'PROJECT_DERIVED');
tc.verifyEqual(m.rating_status,'DECLARED_PROJECT_DERIVED');
tc.verifyTrue(contains(m.rating_source,'PROJECT_DERIVED'));
tc.verifyEqual(abs(m.S_abs_pu),hypot(0.50,0.10),'AbsTol',1e-14);
tc.verifyTrue(m.current_pass);
tc.verifyTrue(m.apparent_power_pass);
tc.verifyTrue(m.passes);
end

function testActualMechanicalPowerStateIsReadNotTheCommand(tc)
% u(1) is the electrical reference P_ref (0.50); the actual shaft state is
% Pm=0.60. The audit must report the actual state, not the command.
dev=augmented_device(0.50+0.10i,0.60,600);
m=run_metrics(dev,[0.50;1.0],case_data(100,100));
tc.verifyEqual(m.Tm_pu,0.50,'AbsTol',0);
tc.verifyEqual(m.mechanical_power_pu,0.60,'AbsTol',0);
tc.verifyNotEqual(m.mechanical_power_pu,m.Tm_pu);
tc.verifyEqual(m.mechanical_power_minus_electrical_pu,0.60-m.Pe_pu,'AbsTol',1e-15);
tc.verifyEqual(m.Tm_pu_semantics,'PER_UNIT_COMMAND_CHANNEL_P_REF_NOT_ACTUAL_SHAFT_POWER');
tc.verifyTrue(m.passes);
end

function testRatingCircleKeepsTheLegacyOperatorAndEps(tc)
% 7.0 pu current against the 6.0 pu explicit circle: the same operator/eps
% family as the legacy comparison now yields a FAIL on both fields.
dev=augmented_device(7.0,0.50,600);
m=run_metrics(dev,[0.50;1.0],case_data(100,100));
expected=abs(m.S_abs_pu)<=m.rating_system_pu+100*eps(max(1,m.rating_system_pu));
tc.verifyEqual(m.apparent_power_pass,expected);
tc.verifyFalse(m.apparent_power_pass);
tc.verifyFalse(m.passes);
end

function testMissingRatingFailsClosedEvenWithHugeMachineBase(tc)
% Schema present but S_rated_MVA absent: NOT_DECLARED and no fallback to the
% deliberately huge machine MVA base.
dev=augmented_device(0.10,0.50,NaN);
m=run_metrics(dev,[0.10;1.0],case_data(100,10000));
tc.verifyEqual(m.rating_status,'NOT_DECLARED');
tc.verifyTrue(isnan(m.rating_MVA));
tc.verifyTrue(isnan(m.rating_system_pu));
tc.verifyTrue(isnan(m.current_limit_system_pu));
tc.verifyFalse(m.current_pass);
tc.verifyFalse(m.apparent_power_pass);
tc.verifyFalse(m.passes);
end

function testMissingSchemaIdOnMarkedDeviceFailsClosed(tc)
% A device carrying the augmented input names must NOT silently use the
% legacy machine-base route when its declared record schema is missing.
dev=augmented_device(0.10,0.50,600);
dev.provenance.params=rmfield(dev.provenance.params,'schema_id');
m=run_metrics(dev,[0.10;1.0],case_data(100,10000));
tc.verifyEqual(m.rating_status,'NOT_DECLARED');
tc.verifyTrue(isnan(m.rating_MVA));
tc.verifyFalse(m.passes);
end

function testLegacyDeviceWithoutAnyMarkerKeepsMachineBaseRoute(tc)
% No augmented marker at all (no model marker, no declared input names, no
% schema id): the legacy path must stay in force, keep
% case_data.machines.base.S_MVA, and gain no opt-in fields.
dev=augmented_device(0.20-0.10i,0.50,600);
dev=rmfield(dev,'input_names');
dev.provenance=rmfield(dev.provenance,'model');
dev.provenance.params=rmfield(dev.provenance.params,'schema_id');
m=run_metrics(dev,[0.25;1.0],case_data(100,100));
tc.verifyEqual(m.rating_MVA,100,'AbsTol',0);
tc.verifyEqual(m.rating_system_pu,1,'AbsTol',0);
tc.verifyFalse(isfield(m,'rating_status'));
tc.verifyFalse(isfield(m,'mechanical_power_pu'));
tc.verifyTrue(m.passes);
end

function testExactSchemaIdAloneAlsoSelectsOptin(tc)
% The exact declared schema id is itself sufficient identification: a device
% carrying the fixed schema must not be driven down the legacy route.
dev=augmented_device(0.50+0.10i,0.50,600);
dev=rmfield(dev,'input_names');
dev.provenance=rmfield(dev.provenance,'model');
m=run_metrics(dev,[0.50;1.0],case_data(100,1000));
tc.verifyEqual(m.rating_MVA,600,'AbsTol',0);
tc.verifyEqual(m.rating_status,'DECLARED_PROJECT_DERIVED');
tc.verifyTrue(m.passes);
end

function testMarkedDeviceWithoutParamsRecordFailsClosedNotThrows(tc)
% Model marker present but dev.provenance.params missing entirely: must report
% NOT_DECLARED with NaN rating instead of a field-reference hard throw.
dev=augmented_device(0.10,0.50,600);
dev.provenance=rmfield(dev.provenance,'params');
m=run_metrics(dev,[0.10;1.0],case_data(100,10000));
tc.verifyEqual(m.rating_status,'NOT_DECLARED');
tc.verifyTrue(isnan(m.rating_MVA));
tc.verifyFalse(m.passes);
end

function testModelMarkerAlsoSelectsOptin(tc)
% The model marker alone must be sufficient (no input_names field).
dev=augmented_device(0.50+0.10i,0.50,600);
dev=rmfield(dev,'input_names');
m=run_metrics(dev,[0.50;1.0],case_data(100,100));
tc.verifyEqual(m.rating_MVA,600,'AbsTol',0);
tc.verifyTrue(contains(m.rating_source,'PROJECT_DERIVED'));
tc.verifyTrue(m.passes);
end

function testBaseMismatchIsRefusedNoWrongBaseSubstitution(tc)
% Declared system_base_MVA must match the case base; a mismatch is refused
% rather than rescaling the rating.
dev=augmented_device(0.10,0.50,600);
dev.provenance.params.system_base_MVA=200;
m=run_metrics(dev,[0.10;1.0],case_data(100,10000));
tc.verifyEqual(m.rating_status,'INVALID_METADATA');
tc.verifyTrue(isnan(m.rating_MVA));
tc.verifyFalse(m.passes);
end

function testEmptySourceIsRefused(tc)
dev=augmented_device(0.10,0.50,600);
dev.provenance.params.source='';
m=run_metrics(dev,[0.10;1.0],case_data(100,100));
tc.verifyEqual(m.rating_status,'INVALID_METADATA');
tc.verifyFalse(m.passes);
end

function testNonFiniteRatingFailsClosed(tc)
dev=augmented_device(0.10,0.50,Inf);
m=run_metrics(dev,[0.10;1.0],case_data(100,100));
tc.verifyEqual(m.rating_status,'NOT_DECLARED');
tc.verifyTrue(isnan(m.rating_MVA));
tc.verifyFalse(m.passes);
end

function testExcessiveCurrentFailsClosedOnExplicitRating(tc)
% 7.0 pu current against a 600 MVA / 100 MVA circle (6.0 pu) fails current
% even though the apparent-power check is also explicit.
dev=augmented_device(7.0,0.50,600);
m=run_metrics(dev,[0.50;1.0],case_data(100,100));
tc.verifyEqual(m.rating_system_pu,6.0,'AbsTol',0);
tc.verifyFalse(m.current_pass);
tc.verifyFalse(m.passes);
end

function testInvalidClassificationIsRefused(tc)
dev=augmented_device(0.10,0.50,600);
dev.provenance.params.classification='SOURCE_DEFINED';
m=run_metrics(dev,[0.10;1.0],case_data(100,100));
tc.verifyEqual(m.rating_status,'INVALID_METADATA');
tc.verifyTrue(isnan(m.rating_MVA));
tc.verifyFalse(m.passes);
end

function testMissingClassificationMetadataIsNotAHardThrow(tc)
% Metadata absence must be reported, not thrown: this is the fail-closed path
% that previously threw on a field reference.
dev=augmented_device(0.10,0.50,600);
dev.provenance.params=rmfield(dev.provenance.params,'classification');
m=run_metrics(dev,[0.10;1.0],case_data(100,100));
tc.verifyEqual(m.rating_status,'INVALID_METADATA');
tc.verifyFalse(m.passes);
end

function m=run_metrics(dev,u,c)
m=stability.sg_prospective_close_metrics(0,zeros(2,1),[1;0],u, ...
    offline_context(),dev,c);
end

function dev=augmented_device(I,Pm,S_rated_MVA)
d=struct('device_id','SG31','bus_position',1, ...
    'input_names',{{'P_ref','Emag_ref'}}, ...
    'current_injection',@(t,x,y,u,ec) current_if_online(I,ec), ...
    'electrical_power',@(t,x,y,u,ec) real(complex(y(1),y(2))*conj(current_if_online(I,ec))), ...
    'f',@(t,x,y,u,ec) zeros(size(x)), ...
    'reconstruct',@(t,x,y,u,ec) struct('V_open_circuit',complex(1,0),'Pm_pu',Pm));
p=struct('schema_id','ne39_sg31_classical_reclose_v1', ...
    'system_base_MVA',100,'classification','PROJECT_DERIVED', ...
    'source','PROJECT_DERIVED stator apparent-power envelope');
if isfinite(S_rated_MVA), p.S_rated_MVA=S_rated_MVA; end
d.provenance=struct('model','sg_classical_reclose_project_derived','params',p);
dev=d;
end

function I=current_if_online(value,ec)
if ec.hybrid_state.device_online.SG31, I=value; else, I=0; end
end

function c=case_data(Sbase,Mbase)
c=struct('base_values',struct('S_base_MVA',Sbase), ...
    'machines',struct('base',struct('S_MVA',Mbase)));
end

function ec=offline_context()
ec=struct('hybrid_state',struct( ...
    'device_online',struct('SG31',false), ...
    'device_modes',struct('SG31','breaker_open')));
end
