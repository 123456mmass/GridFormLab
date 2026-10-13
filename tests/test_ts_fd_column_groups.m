function tests = test_ts_fd_column_groups()
%TEST_TS_FD_COLUMN_GROUPS  Falsify the structural FD column grouping.
%   stability.ts_fd_column_groups claims that one column of each device may be
%   perturbed in the SAME residual evaluation and still reproduce the
%   per-column forward difference exactly. That claim rests on two properties
%   of stability.composite_dae: device k's differential rows are written from
%   x(xr_k) only, and device k's current injection lands only on KCL row
%   bus_map(k). These tests attack the claim three ways:
%     1. the partition invariants (cover, no shared device, no shared bus);
%     2. exact equality of the grouped and per-column Jacobians on the real
%        IEEE14 1SG+4IBR composite residual, at equilibrium, away from
%        equilibrium, and on a faulted admittance matrix;
%     3. the fail-closed paths, including two devices mapped to one bus, which
%        must NOT be grouped together.
%
%   Test 2 is the load-bearing one: it runs the production step with
%   opt.fd_structure_check, which rebuilds the Jacobian column by column and
%   raises ts_step_composite:fdGroupingMismatch unless every entry is
%   bit-identical.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();

c = cases.case_ieee14_1sg_4ibr_auto_vsg();
modes = struct('device_id',{'IBR2','IBR3','IBR6','IBR8'}, ...
    'mode',{'GFM','gfl','gfl','gfl'});
dispatch = struct('IBR2',109.7,'IBR3',49.8,'IBR6',49.8,'IBR8',49.8);
devices = ibr.build_ieee14_sg_ibr_devices(c,modes,dispatch);
devices(1).initial_online = false;
devices(1).mode = 'breaker_open';
config = struct('devices',devices,'selected_gfm_indices',2, ...
    'n_gfm_required',1,'reference_resource_index',2);
eq = stability.mixed_equilibrium_solve(c,config,struct('verbose',false));
testCase.assertTrue(eq.converged,eq.failure_reason);

testCase.TestData.eq = eq;
testCase.TestData.dae = stability.composite_dae(c,eq.devices, ...
    struct('load_model','cz_p_cz_q'));
testCase.TestData.active = eq.dynamic_state_indices(:)';
end

function test_partition_covers_every_column_exactly_once(testCase)
dae = testCase.TestData.dae;
active = testCase.TestData.active;
ny = numel(dae.y0);
nz = numel(active) + ny;

[groups,rowsets,info] = stability.ts_fd_column_groups(dae,active,ny,true);

testCase.verifyTrue(info.grouped,'Structure must be established for this case.');
testCase.verifyEqual(sort([groups{:}]),1:nz,'AbsTol',0, ...
    'Every unknown column must belong to exactly one group.');
testCase.verifyEqual(numel(groups),info.n_groups,'AbsTol',0);
testCase.verifyEqual(numel(rowsets),numel(groups),'AbsTol',0);
testCase.verifyLessThan(info.n_groups,nz, ...
    'Grouping must reduce the residual evaluation count for this case.');

% Algebraic columns are never grouped: they follow the state groups and each
% one must stand alone.
for gi = info.n_state_groups+1:numel(groups)
    testCase.verifyEqual(numel(groups{gi}),1,'AbsTol',0, ...
        'y columns must remain one per group.');
end

% The state-group count is forced by the busiest bus: every active state hosted
% on one bus writes the same two KCL rows, so they cannot share a group.
off = double(dae.device_offsets(:)');
nxd = double([dae.devices.nx]);
per_bus = zeros(1,dae.nb);
for s = active
    k = find(s > off & s <= off+nxd,1);
    b = dae.bus_map(k);
    per_bus(b) = per_bus(b) + 1;
end
testCase.verifyEqual(info.n_state_groups,max(per_bus),'AbsTol',0, ...
    'Group count must equal the largest active-state count on any single bus.');
end

function test_no_group_shares_a_device_or_a_bus(testCase)
dae = testCase.TestData.dae;
active = testCase.TestData.active;
ny = numel(dae.y0);
[groups,~,info] = stability.ts_fd_column_groups(dae,active,ny,true);

off = double(dae.device_offsets(:)');
nxd = double([dae.devices.nx]);
for gi = 1:info.n_state_groups
    cols = groups{gi};
    dev = zeros(1,numel(cols));
    bus = zeros(1,numel(cols));
    for m = 1:numel(cols)
        s = active(cols(m));
        dev(m) = find(s > off & s <= off+nxd,1);
        bus(m) = dae.bus_map(dev(m));
    end
    testCase.verifyEqual(numel(unique(dev)),numel(dev),'AbsTol',0, ...
        'Two columns of one device would share differential rows.');
    testCase.verifyEqual(numel(unique(bus)),numel(bus),'AbsTol',0, ...
        'Two devices on one bus would share KCL rows.');
end
end

function test_grouped_jacobian_equals_per_column_jacobian(testCase)
% The load-bearing check. opt.fd_structure_check makes ts_step_composite build
% the Jacobian both ways and error unless they are bit-identical, so a step that
% completes here IS the equality assertion. Three operating points are used
% because the claim must not depend on the state or on the admittance pattern.
eq = testCase.TestData.eq;
dae = testCase.TestData.dae;
active = testCase.TestData.active;
opt = struct('newton_tol',1e-8,'max_iter',50,'fd_eps',3e-6, ...
    'full_kcl',true,'t_now',0,'fd_structure_check',true);

% (a) at the solved equilibrium
step = stability.ts_step_composite(eq.x0,eq.y0,0.01,dae,dae.Ynet, ...
    eq.u_eq,eq.equilibrium_context,active,opt);
testCase.verifyTrue(step.converged,'Equilibrium step must converge.');
testCase.verifyTrue(step.fd_column_groups.grouped, ...
    'The checked step must actually have used the grouped construction.');

% (b) away from equilibrium: continue from the step just taken
step2 = stability.ts_step_composite(step.x_full,step.y_full,0.01,dae, ...
    dae.Ynet,eq.u_eq,eq.equilibrium_context,active,opt);
testCase.verifyTrue(step2.converged);
testCase.verifyTrue(step2.fd_column_groups.grouped);

% (c) with a different admittance matrix. The derivation never consults Y, so a
% faulted network must not change the grouping's exactness. A shunt fault at
% bus 9 mirrors the production chronology's fault location.
Yf = dae.Ynet;
b9 = find(dae.bus_ids == 9,1);
testCase.assertNotEmpty(b9,'Bus 9 must exist in this case.');
Yf(b9,b9) = Yf(b9,b9) + 1/(0.01+0.01i);
stepf = stability.ts_step_composite(eq.x0,eq.y0,0.01,dae,Yf, ...
    eq.u_eq,eq.equilibrium_context,active,opt);
testCase.verifyTrue(stepf.fd_column_groups.grouped);
testCase.verifyTrue(all(isfinite(stepf.terminal_residual_vector)), ...
    'Faulted-network step must still produce a finite residual.');
end

function test_grouping_off_matches_grouping_auto(testCase)
% Independent of the internal check: the two option settings must produce the
% same accepted root, the same residual and the same conditioning number.
eq = testCase.TestData.eq;
dae = testCase.TestData.dae;
active = testCase.TestData.active;
base = struct('newton_tol',1e-8,'max_iter',50,'fd_eps',3e-6, ...
    'full_kcl',true,'t_now',0);

on = base; on.fd_grouping = 'auto';
off = base; off.fd_grouping = 'off';
a = stability.ts_step_composite(eq.x0,eq.y0,0.01,dae,dae.Ynet,eq.u_eq, ...
    eq.equilibrium_context,active,on);
b = stability.ts_step_composite(eq.x0,eq.y0,0.01,dae,dae.Ynet,eq.u_eq, ...
    eq.equilibrium_context,active,off);

testCase.verifyTrue(a.fd_column_groups.grouped);
testCase.verifyFalse(b.fd_column_groups.grouped);
testCase.verifyEqual(b.fd_column_groups.fallback_reason,'disabled_by_option');
testCase.verifyEqual(a.x_full,b.x_full,'AbsTol',0);
testCase.verifyEqual(a.y_full,b.y_full,'AbsTol',0);
testCase.verifyEqual(a.iterations,b.iterations,'AbsTol',0);
testCase.verifyEqual(a.residual_norm,b.residual_norm,'AbsTol',0);
testCase.verifyEqual(a.rcond,b.rcond,'AbsTol',0);
end

function test_structural_preconditions_fail_closed(testCase)
dae = testCase.TestData.dae;
active = testCase.TestData.active;
ny = numel(dae.y0);
nz = numel(active) + ny;

[g1,~,i1] = stability.ts_fd_column_groups(dae,active,ny,false);
testCase.verifyFalse(i1.grouped);
testCase.verifyEqual(i1.fallback_reason,'reduced_kcl_rows');
testCase.verifyEqual(numel(g1),nz,'AbsTol',0);

d2 = dae;
d2.vcon = struct('vars',1,'rows',1,'kind','fixed_y_only','ref',1);
[~,~,i2] = stability.ts_fd_column_groups(d2,active,ny,true);
testCase.verifyFalse(i2.grouped);
testCase.verifyEqual(i2.fallback_reason,'vcon_rows_declared');

d3 = rmfield(dae,'bus_map');
[~,~,i3] = stability.ts_fd_column_groups(d3,active,ny,true);
testCase.verifyFalse(i3.grouped);
testCase.verifyEqual(i3.fallback_reason,'missing_bus_map');

[~,~,i4] = stability.ts_fd_column_groups(dae,active,ny+1,true);
testCase.verifyFalse(i4.grouped);
testCase.verifyEqual(i4.fallback_reason,'ny_not_two_per_bus');

d5 = dae;
d5.bus_map(1) = dae.nb + 5;
[~,~,i5] = stability.ts_fd_column_groups(d5,active,ny,true);
testCase.verifyFalse(i5.grouped);
testCase.verifyEqual(i5.fallback_reason,'device_table_out_of_range');

% An active index outside every device range cannot be attributed.
[~,~,i6] = stability.ts_fd_column_groups(dae,[active, 10^6],ny,true);
testCase.verifyFalse(i6.grouped);
testCase.verifyEqual(i6.fallback_reason, ...
    'active_state_not_owned_by_one_device');
end

function test_devices_on_one_bus_get_separate_groups(testCase)
% Synthetic two-device topologies exercise the shared-bus branch that the
% IEEE14 case (devices on buses 1,2,3,6,8) never reaches. composite_dae
% explicitly supports two devices on one bus, and their injections both land on
% the same KCL row, so no group may hold columns from both.
shared = struct('device_offsets',[0;2],'devices',struct('nx',{2,2}), ...
    'bus_map',[1;1],'nb',2,'vcon',struct('rows',[]),'y0',zeros(4,1));
[~,~,shared_info] = stability.ts_fd_column_groups(shared,1:4,4,true);
testCase.verifyTrue(shared_info.grouped);
testCase.verifyEqual(shared_info.n_state_groups,4,'AbsTol',0, ...
    'Four active states on one bus admit no grouping at all.');

split = shared;
split.bus_map = [1;2];
[groups,~,split_info] = stability.ts_fd_column_groups(split,1:4,4,true);
testCase.verifyEqual(split_info.n_state_groups,2,'AbsTol',0, ...
    'Two devices on distinct buses halve the state-column count.');
testCase.verifyEqual(sort(groups{1}),[1 3],'AbsTol',0);
testCase.verifyEqual(sort(groups{2}),[2 4],'AbsTol',0);
end

function test_fd_perturbation_default_is_byte_identical(testCase)
% forward_fd accepts either a scalar step (the historical absolute rule) or a
% per-column vector. Passing the default explicitly must therefore change
% nothing at all, not merely agree to a tolerance.
eq = testCase.TestData.eq;
dae = testCase.TestData.dae;
active = testCase.TestData.active;
base = struct('newton_tol',1e-8,'max_iter',50,'fd_eps',3e-6, ...
    'full_kcl',true,'t_now',0);
implicit = stability.ts_step_composite(eq.x0,eq.y0,0.01,dae,dae.Ynet, ...
    eq.u_eq,eq.equilibrium_context,active,base);
explicit_opt = base; explicit_opt.fd_perturbation = 'absolute';
explicit = stability.ts_step_composite(eq.x0,eq.y0,0.01,dae,dae.Ynet, ...
    eq.u_eq,eq.equilibrium_context,active,explicit_opt);
testCase.verifyEqual(explicit.x_full,implicit.x_full,'AbsTol',0);
testCase.verifyEqual(explicit.y_full,implicit.y_full,'AbsTol',0);
testCase.verifyEqual(explicit.iterations,implicit.iterations);
testCase.verifyEqual(explicit.residual_norm,implicit.residual_norm,'AbsTol',0);
testCase.verifyEqual(explicit.rcond,implicit.rcond,'AbsTol',0);
end

function test_grouping_is_exact_for_a_vector_fd_step(testCase)
% The structural derivation is about which ROWS a column can touch, so it must
% hold for a per-column step too. fd_structure_check rebuilds the Jacobian
% per column using the same per-column steps and errors unless the two are
% bit-identical, so a completed step is the assertion.
eq = testCase.TestData.eq;
dae = testCase.TestData.dae;
active = testCase.TestData.active;
opt = struct('newton_tol',1e-8,'max_iter',50,'fd_eps',3e-6, ...
    'full_kcl',true,'t_now',0,'fd_structure_check',true, ...
    'fd_perturbation','scaled');
step = stability.ts_step_composite(eq.x0,eq.y0,0.01,dae,dae.Ynet, ...
    eq.u_eq,eq.equilibrium_context,active,opt);
testCase.verifyTrue(step.converged);
testCase.verifyTrue(step.fd_column_groups.grouped);
end

function test_fd_perturbation_rejects_an_unknown_rule(testCase)
eq = testCase.TestData.eq;
dae = testCase.TestData.dae;
active = testCase.TestData.active;
opt = struct('newton_tol',1e-8,'max_iter',50,'fd_eps',3e-6, ...
    'full_kcl',true,'t_now',0,'fd_perturbation','relative');
testCase.verifyError(@() stability.ts_step_composite(eq.x0,eq.y0,0.01,dae, ...
    dae.Ynet,eq.u_eq,eq.equilibrium_context,active,opt), ...
    'ts_step_composite:badFdPerturbation');
end




function test_y_cache_hit_on_same_key(testCase)
% DIAGNOSTIC counter check: a second call with the SAME device tables,
% context and Ynet must be served from the persistent cache (cache_hit=true)
% without running another probe (probe_evaluations unchanged), and the
% served locality decision must be identical.
eq = testCase.TestData.eq;
dae = testCase.TestData.dae;
active = testCase.TestData.active;
ny = numel(dae.y0);
probe_opt = struct('y_grouping',true,'Ynet',dae.Ynet,'x',eq.x0, ...
    'u',eq.u_eq,'event_context',eq.equilibrium_context,'t',0);

[~,~,info1] = stability.ts_fd_column_groups(dae,active,ny,true,probe_opt);
[~,~,info2] = stability.ts_fd_column_groups(dae,active,ny,true,probe_opt);

testCase.verifyEqual(info1.y_locality_reason,info2.y_locality_reason);
testCase.verifyEqual(info2.y_grouping,info1.y_grouping);
% When this case proves y-locality the cache is actually populated, so the
% second identical lookup must be a HIT and must not run another probe
% evaluation. info1.cache_hit itself is NOT asserted: the persistent cache may
% already be warm from an earlier test that probed the same shared fixture.
if info1.y_grouping
    testCase.verifyTrue(info2.cache_hit, ...
        'Second identical lookup must be served from the cache.');
    testCase.verifyEqual(info2.probe_evaluations, ...
        info1.probe_evaluations,'AbsTol',0);
end
end

function test_y_cache_miss_on_ynet_change(testCase)
% Ynet is part of the cache key: a call with a CHANGED topology (here the
% same Ynet with one branch zeroed, shape unchanged) must invalidate the
% cache and re-run the probe (cache_hit=false, probe_evaluations advances).
eq = testCase.TestData.eq;
dae = testCase.TestData.dae;
active = testCase.TestData.active;
ny = numel(dae.y0);
Y_a = dae.Ynet;
Y_b = Y_a;
[maxval, maxidx] = max(Y_b(:));
Y_b(maxidx) = 0;   % cut the one strongest branch (shape unchanged)
probe_a = struct('y_grouping',true,'Ynet',Y_a,'x',eq.x0, ...
    'u',eq.u_eq,'event_context',eq.equilibrium_context,'t',0);
probe_b = probe_a; probe_b.Ynet = Y_b;

[~,~,info1] = stability.ts_fd_column_groups(dae,active,ny,true,probe_a);
[~,~,info2] = stability.ts_fd_column_groups(dae,active,ny,true,probe_b);

testCase.verifyFalse(info2.cache_hit, ...
    'A changed Ynet must invalidate the cache and re-probe.');
testCase.verifyEqual(info2.probe_evaluations, ...
    info1.probe_evaluations+1,'AbsTol',0);
% And a third call on the ORIGINAL topology re-misses again (the LRU entry
% now holds the cut topology), proving the key actually distinguishes them.
[~,~,info3] = stability.ts_fd_column_groups(dae,active,ny,true,probe_a);
testCase.verifyFalse(info3.cache_hit);
end

function test_y_cache_miss_on_mode_change(testCase)
% The event context (modes/freeze/hybrid state) is part of the key: a call
% whose context differs in an ACTUAL device mode (gfl<->gfm) must re-run the
% probe, never reuse the decision. The mode contract is what changes here —
% hs.device_modes flips one device's mode value — so this exercises the real
% mode/layout invalidation, not just an unrelated added field.
eq = testCase.TestData.eq;
dae = testCase.TestData.dae;
active = testCase.TestData.active;
ny = numel(dae.y0);
ec = eq.equilibrium_context;
ec_mode = ec;
if isfield(ec,'hybrid_state') && isstruct(ec.hybrid_state) && ...
        isfield(ec.hybrid_state,'device_modes') && ...
        isstruct(ec.hybrid_state.device_modes)
    dm = ec.hybrid_state.device_modes;
    keys = fieldnames(dm);
    testCase.verifyGreaterThan(numel(keys), 0, ...
        'Fixture must carry at least one device mode to flip.');
    if strcmpi(char(dm.(keys{1})), 'gfm')
        dm.(keys{1}) = 'gfl';
    else
        dm.(keys{1}) = 'gfm';
    end
    ec_mode.hybrid_state.device_modes = dm;
else
    % No device_modes in this context: switch the whole hybrid_state to the
    % other mode family so the context genuinely differs.
    ec_mode.hybrid_state = struct('device_modes', ...
        {struct('probe_device','gfl')});
end
probe_a = struct('y_grouping',true,'Ynet',dae.Ynet,'x',eq.x0, ...
    'u',eq.u_eq,'event_context',ec,'t',0);
probe_b = probe_a; probe_b.event_context = ec_mode;

[~,~,info1] = stability.ts_fd_column_groups(dae,active,ny,true,probe_a);
[~,~,info2] = stability.ts_fd_column_groups(dae,active,ny,true,probe_b);
testCase.verifyFalse(info2.cache_hit, ...
    'A changed device mode (gfl<->gfm) must re-probe.');
testCase.verifyEqual(info2.probe_evaluations, ...
    info1.probe_evaluations+1,'AbsTol',0);
end

function test_grouping_still_bit_exact_with_cache_fields(testCase)
% The new diagnostic fields must not perturb the numerics: a completed
% production step with fd_structure_check still proves the grouped Jacobian
% is bit-identical to the per-column build.
eq = testCase.TestData.eq;
dae = testCase.TestData.dae;
active = testCase.TestData.active;
opt = struct('newton_tol',1e-8,'max_iter',50,'fd_eps',3e-6, ...
    'full_kcl',true,'t_now',0,'fd_structure_check',true);
step = stability.ts_step_composite(eq.x0,eq.y0,0.01,dae,dae.Ynet, ...
    eq.u_eq,eq.equilibrium_context,active,opt);
testCase.verifyTrue(step.converged);
testCase.verifyTrue(step.fd_column_groups.grouped);
end
