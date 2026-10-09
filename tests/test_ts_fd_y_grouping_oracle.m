function tests = test_ts_fd_y_grouping_oracle()
%TEST_TS_FD_Y_GROUPING_ORACLE  Algebraic-column FD grouping vs the full-FD oracle.
%   WS-A proof test. The old composite FD Jacobian evaluated the WHOLE residual
%   once per algebraic (y) column: 78 of 88 groups on the 39-bus case were y
%   columns. The new path groups y columns whose closed network neighbourhoods
%   are disjoint, after proving (in stability.ts_fd_y_locality) that every
%   device reads only its own bus voltage. This test proves the grouped
%   Jacobian is BIT-IDENTICAL to the per-column construction (not merely
%   trajectory-similar):
%     - fd_structure_check=true rebuilds the Jacobian one column at a time and
%       requires exact equality, so a passing run IS the oracle comparison;
%     - the converged step results of the grouped and per-column paths are
%       compared exactly and must be equal.
%   Nothing is relaxed: the same residual, tolerances, and gates are used.
tests = functiontests(localfunctions);
end

function setupOnce(tc)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
s = cases.scenario_ne39_5sg_5ibr();
[devices,~] = stability.build_mixed_resource_devices( ...
    s.case_data, s.resources, s.scenario_opt);
eq = stability.mixed_equilibrium_solve(s.case_data, ...
    struct('devices',devices), struct('verbose',false));
dae = stability.composite_dae(s.case_data, devices, ...
    struct('full_kcl',true,'u_eq',eq.u_eq, ...
           'event_context',eq.equilibrium_context, ...
           'dynamic_state_indices',eq.dynamic_state_indices));
tc.TestData.s = s;
tc.TestData.eq = eq;
tc.TestData.dae = dae;
end

function test_grouping_reduces_y_column_count(tc)
eq = tc.TestData.eq; dae = tc.TestData.dae;
opts = struct('y_grouping',true,'Ynet',dae.Ynet,'x',eq.x0,'u',eq.u_eq, ...
    'event_context',eq.equilibrium_context,'t',0);
[~,~,info] = stability.ts_fd_column_groups(dae, ...
    eq.dynamic_state_indices, numel(dae.y0), true, opts);
tc.verifyTrue(info.y_grouping, info.y_locality_reason);
tc.verifyLessThan(info.n_y_groups, info.n_y_columns);
tc.verifyEqual(info.n_y_columns, numel(dae.y0));
end

function test_grouping_off_keeps_one_y_column_per_group(tc)
eq = tc.TestData.eq;
[~,~,info] = stability.ts_fd_column_groups(tc.TestData.dae, ...
    eq.dynamic_state_indices, numel(tc.TestData.dae.y0), true, struct());
tc.verifyFalse(info.y_grouping);
tc.verifyEqual(info.n_y_groups, info.n_y_columns);
tc.verifyEqual(info.n_groups, info.n_state_groups + info.n_y_columns);
end

function test_locality_proof_holds_for_ne39_devices(tc)
eq = tc.TestData.eq; dae = tc.TestData.dae;
loc = stability.ts_fd_y_locality(dae, eq.x0, eq.u_eq, ...
    eq.equilibrium_context, 0);
tc.verifyTrue(loc.local, loc.reason);
tc.verifyEqual(loc.n_devices, numel(dae.devices));
end

function test_grouped_step_equals_per_column_step_bitwise(tc)
eq = tc.TestData.eq; dae = tc.TestData.dae; h = 0.004;
% Per-column construction (historical): fd_grouping off.
step_off = stability.ts_step_composite(eq.x0, dae.y0, h, dae, dae.Ynet, ...
    eq.u_eq, eq.equilibrium_context, eq.dynamic_state_indices, ...
    struct('fd_grouping','off','fd_eps',3e-6));
% Grouped construction WITH the per-column oracle check enabled: this errors
% if any grouped column differs from its per-column value.
step_grp = stability.ts_step_composite(eq.x0, dae.y0, h, dae, dae.Ynet, ...
    eq.u_eq, eq.equilibrium_context, eq.dynamic_state_indices, ...
    struct('fd_grouping','auto','fd_y_grouping','auto', ...
           'fd_structure_check',true,'fd_eps',3e-6));
tc.verifyTrue(step_grp.converged,'grouped NE39 step must converge');
tc.verifyTrue(step_grp.fd_column_groups.y_grouping, 'y grouping must be active');
tc.verifyLessThan(step_grp.fd_column_groups.n_y_groups, ...
    step_grp.fd_column_groups.n_y_columns);
tc.verifyEqual(step_grp.x_full, step_off.x_full, 'AbsTol', 0);   % exact
tc.verifyEqual(step_grp.y_full, step_off.y_full, 'AbsTol', 0);
tc.verifyLessThan(step_grp.residual_norm, 1e-8);
end

function test_ieee14_device_set_is_also_y_local(tc)
% The proof is a device property: the delivered IEEE14 1-SG + 4-IBR set must
% pass it too, otherwise the default grouping would silently fall back there.
s = cases.scenario_ieee14_1sg_4ibr();
[devices,~] = stability.build_mixed_resource_devices( ...
    s.case_data, s.resources, s.scenario_opt);
eq = stability.mixed_equilibrium_solve(s.case_data, ...
    struct('devices',devices), struct('verbose',false));
dae = stability.composite_dae(s.case_data, devices, ...
    struct('full_kcl',true,'u_eq',eq.u_eq, ...
           'event_context',eq.equilibrium_context, ...
           'dynamic_state_indices',eq.dynamic_state_indices));
loc = stability.ts_fd_y_locality(dae, eq.x0, eq.u_eq, ...
    eq.equilibrium_context, 0);
tc.verifyTrue(loc.local, loc.reason);
% And the grouped IEEE14 step must match the per-column step exactly.
h = 0.002;
step_off = stability.ts_step_composite(eq.x0, dae.y0, h, dae, dae.Ynet, ...
    eq.u_eq, eq.equilibrium_context, eq.dynamic_state_indices, ...
    struct('fd_grouping','off','fd_eps',3e-6));
step_grp = stability.ts_step_composite(eq.x0, dae.y0, h, dae, dae.Ynet, ...
    eq.u_eq, eq.equilibrium_context, eq.dynamic_state_indices, ...
    struct('fd_grouping','auto','fd_y_grouping','auto', ...
           'fd_structure_check',true,'fd_eps',3e-6));
tc.verifyTrue(step_grp.converged,'grouped IEEE14 step must converge');
tc.verifyTrue(step_grp.fd_column_groups.y_grouping, 'IEEE14 y grouping must be active');
tc.verifyEqual(step_grp.x_full, step_off.x_full, 'AbsTol', 0);
end

function test_all_live_models_are_declared_y_local(tc)
% Every device on the delivered NE39 mixed set must carry a registered
% structural declaration; an undeclared device fails the proof closed.
eq = tc.TestData.eq;
for k = 1:numel(eq.devices)
    [dec, di] = stability.algebraic_y_locality_declaration(eq.devices(k));
    tc.verifyTrue(dec, sprintf('device %d undeclared (%s=%s)', ...
        k, di.source, di.key));
end
end

function test_undeclared_device_refuses_grouping(tc)
% A registered device replaced by an unregistered model must switch the whole
% group construction back to the conservative per-column path.
eq = tc.TestData.eq; dae = tc.TestData.dae;
d2 = dae; dev = d2.devices;
dev(1).device_type = 'mystery_unregistered_model';
if isfield(dev(1),'algebraic_locality'), dev(1).algebraic_locality = ''; end
d2.devices = dev;
info = get_group_info(d2, eq);
tc.verifyFalse(info.y_grouping);
tc.verifyTrue(contains(lower(string(info.y_locality_reason)),'undeclared'));
tc.verifyEqual(info.n_y_groups, info.n_y_columns);
end

function test_adversarial_nonlocal_device_is_caught(tc)
% A device that keeps a REGISTERED type but reads a FOREIGN bus voltage must be
% caught by the probe cross-check, so a lying model can never be grouped.
eq = tc.TestData.eq; dae = tc.TestData.dae;
k = 1; bf = 5;               % device 1 sits on bus 31; make it read bus 5
d2 = dae; dev = d2.devices;
fk = dev(k).f;
dev(k).f = @(t,xd,y,u,ec) fk(t,xd,y,u,ec) + 1e-3*[y(2*bf-1); -y(2*bf)];
d2.devices = dev;
loc = stability.ts_fd_y_locality(d2, eq.x0, eq.u_eq, ...
    eq.equilibrium_context, 0);
tc.verifyFalse(loc.local);
tc.verifyTrue(contains(lower(string(loc.reason)),'foreign'));
end

function test_faulted_topology_keeps_grouping_bit_identical(tc)
% The closed-neighbourhood row sets are recomputed from the CURRENT Ynet, so a
% faulted topology must still yield a valid, bit-identical grouping.
eq = tc.TestData.eq; dae = tc.TestData.dae;
if ~isfield(dae,'topology') || ~isfield(dae.topology,'Yfault')
    tc.assumeFail('no Yfault topology published');
end
Yf = dae.topology.Yfault;
h = 0.004;
step_off = stability.ts_step_composite(eq.x0, dae.y0, h, dae, Yf, ...
    eq.u_eq, eq.equilibrium_context, eq.dynamic_state_indices, ...
    struct('fd_grouping','off','fd_eps',3e-6));
step_grp = stability.ts_step_composite(eq.x0, dae.y0, h, dae, Yf, ...
    eq.u_eq, eq.equilibrium_context, eq.dynamic_state_indices, ...
    struct('fd_grouping','auto','fd_y_grouping','auto', ...
           'fd_structure_check',true,'fd_eps',3e-6));
tc.verifyTrue(step_grp.converged,'grouped faulted step must converge');
tc.verifyTrue(step_grp.fd_column_groups.y_grouping);
tc.verifyEqual(step_grp.x_full, step_off.x_full, 'AbsTol', 0);
end

function test_event_context_change_forces_reprobe(tc)
% A cached positive must NEVER be reused across a different event context
% (online/mode/regime changes): the cache key carries the serialised context,
% so a device that becomes non-local only under the new context is re-probed
% and caught, not served the stale positive.
eq = tc.TestData.eq; dae = tc.TestData.dae;
info1 = get_group_info_ec(dae, eq, eq.equilibrium_context);
tc.verifyTrue(info1.y_grouping, info1.y_locality_reason);   % cached positive
% Poison device 1 so it reads a FOREIGN bus, but ONLY when ec.poison is set.
k = 1; bf = 5; dev = dae.devices; fk = dev(k).f;
dev(k).f = @(t,x,y,u,ec) fk(t,x,y,u,ec) + ...
    double(isfield(ec,'poison') && isequal(ec.poison,true)) * 1e-3 * [y(2*bf-1); -y(2*bf)];
d2 = dae; d2.devices = dev;
% Same context -> same path -> still local (and same cache key as before).
info_same = get_group_info_ec(d2, eq, eq.equilibrium_context);
tc.verifyTrue(info_same.y_grouping);
% New context -> key changes -> re-probe -> foreign response caught.
ec2 = eq.equilibrium_context; ec2.poison = true;
info2 = get_group_info_ec(d2, eq, ec2);
tc.verifyFalse(info2.y_grouping);
tc.verifyEqual(info2.n_y_groups, info2.n_y_columns);
end

function test_swapped_closure_same_id_type_context_is_not_trusted(tc)
% Counterexample for the cache key: identical device_id/device_type/nx/nu/
% bus_map AND identical event context, but dev(1).f rebound to a closure that
% reads a FOREIGN bus. Type/metadata alone must not authorise reuse of the
% cached positive proof -- the closure fingerprint must invalidate it, so the
% device is re-probed and grouping is refused.
eq = tc.TestData.eq; dae = tc.TestData.dae;
info1 = get_group_info(dae, eq);
tc.verifyTrue(info1.y_grouping, info1.y_locality_reason);   % cache a positive
k = 1; bf = 5; d2 = dae; dev = d2.devices; fk = dev(k).f;
dev(k).f = @(t,x,y,u,ec) fk(t,x,y,u,ec) + 1e-3*[y(2*bf-1); -y(2*bf)];
d2.devices = dev;    % metadata + context deliberately UNCHANGED
info2 = get_group_info(d2, eq);
tc.verifyFalse(info2.y_grouping, ...
    'a swapped closure must not reuse the cached proof (no trust-on-type)');
tc.verifyEqual(info2.n_y_groups, info2.n_y_columns);
end

function test_real_imag_cancellation_is_not_local(tc)
% อ่านต่างบัสแบบ Re-Im จะหลุดหาก perturb สอง coordinate พร้อมกัน.
eq=tc.TestData.eq; d=tc.TestData.dae; fk=d.devices(1).f;
b=5;
d.devices(1).f=@(t,x,y,u,ec) fk(t,x,y,u,ec)+ ...
    1e-3*(y(2*b-1)-y(2*b))*ones(2,1);
loc=stability.ts_fd_y_locality(d,eq.x0,eq.u_eq,eq.equilibrium_context,0);
tc.verifyFalse(loc.local);
tc.verifyTrue(contains(loc.reason,'foreign'));
end

function test_captured_values_with_same_summary_force_reprobe(tc)
% closure text และ sum/sum-square เหมือนกัน แต่ captured weights ต่างกัน.
eq=tc.TestData.eq; d=tc.TestData.dae; fk=d.devices(1).f;
d.devices(1).f=weighted_foreign_callback(fk,[1 0]);
first=get_group_info(d,eq); tc.verifyTrue(first.y_grouping);
d.devices(1).f=weighted_foreign_callback(fk,[0 1]);
second=get_group_info(d,eq);
tc.verifyFalse(second.y_grouping);
tc.verifyEqual(second.n_y_groups,second.n_y_columns);
end

function f=weighted_foreign_callback(base,weights)
f=@(t,x,y,u,ec) base(t,x,y,u,ec)+weights(2)*1e-3*[y(9);-y(10)];
end

function info = get_group_info(dae, eq)
info = get_group_info_ec(dae, eq, eq.equilibrium_context);
end

function info = get_group_info_ec(dae, eq, ec)
[~,~,info] = stability.ts_fd_column_groups(dae, eq.dynamic_state_indices, ...
    numel(dae.y0), true, struct('y_grouping',true,'Ynet',dae.Ynet, ...
    'x',eq.x0,'u',eq.u_eq,'event_context',ec,'t',0));
end
