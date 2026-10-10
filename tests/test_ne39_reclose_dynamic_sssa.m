function tests = test_ne39_reclose_dynamic_sssa
tests = functiontests(localfunctions);
end

function setupOnce(tc)
p = path;
tc.addTeardown(@() path(p));
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
[design_opt, analysis] = ne39_endpoint_design_options();
c = cases.ne39_chronology_design(cases.case_ne39_1sg_9ibr(), design_opt);
ibr = find(strcmpi({analysis.initial_modes.device_id}, 'IBR'), 1);
assert(~isempty(analysis.initial_modes));
s = cases.scenario_ne39_tamu_mixed(c, struct( ...
    'sg_reclose_plant', true, 'initial_modes', analysis.initial_modes));
[d, ~] = stability.build_mixed_resource_devices(c, s.resources, s.scenario_opt);
eq = stability.mixed_equilibrium_solve(c, struct('devices', d), ...
    struct('verbose', false, 'tolerance', 1e-8));
tc.TestData.c = c;
tc.TestData.devices = d;
tc.TestData.eq = eq;
tc.TestData.ibr = find(strcmp({s.resources.resource_type}, 'ibr'));
end

function test_online_partition_and_gauge(tc)
eq = tc.TestData.eq;
tc.verifyTrue(eq.converged);
model = stability.composite_sssa_model(tc.TestData.devices, eq.x0, eq.y0, ...
    tc.TestData.c, sssa_opt(eq, eq.active_state_indices, 'equilibrium'));
tc.verifyEqual(numel(model.eigenvalues), 106);
tc.verifyEqual(numel(model.physical_eigenvalues), 105);
assert_gauge(tc, model, eq);
lam = model.physical_eigenvalues(:);
zeta = min(-real(lam)./abs(lam));
tc.verifyGreaterThanOrEqual(zeta, 0.02);
end

function test_dynamic_partition_requires_stationary_seed(tc)
eq = tc.TestData.eq;
dae = stability.composite_dae(tc.TestData.c, tc.TestData.devices, struct());
dynamic = stability.ts_dynamic_state_indices(dae, eq.equilibrium_context);
tc.verifyEqual(numel(dynamic), numel(eq.active_state_indices));
threw = false;
try
    stability.composite_sssa_model(tc.TestData.devices, eq.x0, eq.y0, ...
        tc.TestData.c, sssa_opt(eq, dynamic, 'not-a-partition'));
catch me
    threw = true;
    tc.verifyEqual(me.identifier, 'composite_sssa_model:badStatePartition');
end
tc.verifyTrue(threw);
end

function test_offline_dynamic_gauge_and_anchor_rejection(tc)
c = tc.TestData.c;
s = cases.scenario_ne39_tamu_mixed(c, struct('sg_reclose_plant', true));
resources = s.resources;
sg = find(strcmp({resources.resource_id}, 'SG31'));
ibr = find(strcmp({resources.resource_type}, 'ibr'));
resources(sg).initial_online = false;
resources(sg).initial_mode = "breaker_open";
for k = ibr
    resources(k).initial_mode = "gfm";
end
build_opt = struct('dispatch', c.dispatch_contract.post_trip.post_trip_Pg_MW);
[d, ~] = stability.build_mixed_resource_devices(c, resources, build_opt);
selection = struct('selected_gfm_indices', ibr, 'n_gfm_required', numel(ibr), ...
    'reference_resource_index', ibr(1));
eq = stability.mixed_equilibrium_solve(c, struct('devices', d, ...
    'selected_gfm_indices', selection.selected_gfm_indices, ...
    'n_gfm_required', selection.n_gfm_required, ...
    'reference_resource_index', selection.reference_resource_index), ...
    struct('verbose', false, 'tolerance', 1e-8));
tc.verifyTrue(eq.converged);
tc.verifyEqual(numel(eq.active_state_indices), 99);

dae = stability.composite_dae(c, d, struct());
k = find(strcmp({d.device_id}, 'SG31'));
ix = dae.device_offsets(k)+(1:7);
V = complex(eq.y0(2*d(k).bus_position-1), eq.y0(2*d(k).bus_position));
L0 = d(k).provenance.params.no_load_loss_pu;
x = eq.x0;
x(ix) = [angle(V); 1; L0; L0; abs(V); angle(V); 0];
dynamic = stability.ts_dynamic_state_indices(dae, eq.equilibrium_context);
tc.verifyEqual(numel(dynamic), 106);
model = stability.composite_sssa_model(d, x, eq.y0, c, sssa_opt( ...
    eq, dynamic, 'dynamic'));
tc.verifyEqual(numel(model.eigenvalues), 106);
tc.verifyEqual(numel(model.physical_eigenvalues), 105);
tc.verifyLessThan(model.partition_f_residual_norm, 1e-8);
tc.verifyLessThan(model.partition_kcl_residual_norm, 1e-6);
assert_gauge(tc, model, eq);

anchor_failed = false;
try
    stability.composite_sssa_model(d, eq.x0, eq.y0, c, sssa_opt( ...
        eq, dynamic, 'dynamic'));
catch me
    anchor_failed = true;
    tc.verifyEqual(me.identifier, ...
        'composite_sssa_model:nonstationaryDynamicPartition');
end
tc.verifyTrue(anchor_failed);
end

function opt = sssa_opt(eq, active, partition)
opt = struct('full_kcl', true, 'u_eq', eq.u_eq, ...
    'event_context', eq.equilibrium_context, ...
    'active_state_indices', active, ...
    'reference_device_index', eq.reference.device_index, ...
    'state_partition', partition, 'fd_eps', 3e-6);
end

function assert_gauge(tc, model, eq)
L = model.coordinate_quotient_left_map;
T = model.coordinate_quotient_right_map;
tc.verifyEqual(model.coordinate_mode_count, 1);
tc.verifyEqual(size(L,1)+1, size(L,2));
tc.verifyEqual(size(T,1), size(L,2));
pre_indices = [model.physical_state_global_indices, ...
    model.coordinate_gauge_global_index];
pre_indices = sort(pre_indices);
names = state_names_at(eq.devices, pre_indices);
r_full = zeros(size(L,2),1);
for i = 1:numel(names)
    if endsWith(names{i}, {'/delta','/theta_hat','/gfm_delta_VSG'})
        r_full(i) = 1;
    end
end
tc.verifyGreaterThanOrEqual(nnz(r_full), 10);
tc.verifyLessThan(norm(L*r_full, inf), 1e-12);
tc.verifyLessThan(norm(L*T-eye(size(L,1)), inf), 1e-12);
tc.verifyEqual(numel(model.physical_eigenvalues), numel(model.eigenvalues)-1);
tc.verifyNotEmpty(eq.reference.device_index);
end

function names = state_names_at(devices, indices)
names = cell(1, numel(indices));
offsets = [0, cumsum([devices.nx])];
for i = 1:numel(indices)
    k = find(indices(i) > offsets(1:end-1) & indices(i) <= offsets(2:end), 1);
    local = indices(i)-offsets(k);
    labels = cellstr(string(devices(k).state_names));
    names{i} = sprintf('%s/%s', devices(k).device_id, labels{local});
end
end
