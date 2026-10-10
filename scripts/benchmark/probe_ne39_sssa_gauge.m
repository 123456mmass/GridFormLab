function probe_ne39_sssa_gauge()
%PROBE_NE39_SSSA_GAUGE  Validate the rotational-symmetry tangent and the gauge
%   quotient on the full-active NE39 SSSA, without deleting any physical mode.
%   Builds the FULL tangent over the active-state model -- every SG rotor angle
%   AND every IBR PLL/VSG angle, plus the algebraic bus-voltage rotation -- and
%   checks J*T ~= 0 (gauge invariance) BEFORE trusting the quotient.
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
m = stability.composite_sssa_model(eq.devices, eq.x0, eq.y0, s.case_data, ...
    struct('full_kcl',true,'u_eq',eq.u_eq, ...
    'event_context',eq.equilibrium_context, ...
    'active_state_indices',eq.active_state_indices,'fd_eps',3e-6, ...
    'reference_device_index',eq.reference.device_index));

nx = numel(eq.x0); ny = numel(eq.y0); nb = ny/2; y0 = eq.y0;
% --- full rotational tangent -------------------------------------------------
Tx = zeros(nx,1); n_ang = 0; ang_names = {};
cands = {'delta','gfl_delta_PLL','delta_PLL','gfm_delta_VSG','gfm_delta_PLL','delta_VSG'};
for dk = 1:numel(dae.devices)
    dev = dae.devices(dk); nm = cellstr(string(dev.state_names)); pos = [];
    for c = cands
        p = find(strcmpi(nm, c{1}), 1);
        if ~isempty(p), pos = p; break; end
    end
    if ~isempty(pos)
        g = dae.device_offsets(dk) + pos;
        Tx(g) = 1; n_ang = n_ang + 1;
        ang_names{end+1} = sprintf('%s:%s', dev.device_id, nm{pos});
    end
end
Ty = zeros(ny,1);
for b = 1:nb
    re = y0(2*b-1); im = y0(2*b);
    Ty(2*b-1) = -im; Ty(2*b) = re;   % d/dtheta of y0*exp(j theta)
end
T = [Tx; Ty];
J = [m.fx m.fy; m.gx m.gy];
rJ = J*T;
fprintf('GAUGE n_angle_coords=%d : %s\n', n_ang, strjoin(ang_names,', '));
fprintf('GAUGE ||J*T||inf=%.3e  ||T||2=%.3e  rel=%.3e\n', ...
    norm(rJ,inf), norm(T), norm(rJ,inf)/max(norm(T),eps));

% --- eigenvalues: full state table vs gauge-quotiented decision spectrum -----
ef = m.eigenvalues; ep = m.physical_eigenvalues;
fprintf('FULL    n=%d maxRe=%.6e nPos=%d\n', numel(ef), max(real(ef)), sum(real(ef)>1e-6));
fprintf('GUAGED  n=%d maxRe=%.6e nPos=%d method=%s\n', numel(ep), max(real(ep)), ...
    sum(real(ep)>1e-6), m.physical_reduction_method);
fprintf('GAUGE coordinate index=%s name=%s\n', ...
    mat2str(m.coordinate_gauge_global_index), m.coordinate_gauge_state_name);
% Did the quotient remove exactly the gauge direction (one near-zero eigenvalue)?
z_full = sum(abs(real(ef))<1e-4 & abs(imag(ef))<1e-4);
z_phys = sum(abs(real(ep))<1e-4 & abs(imag(ep))<1e-4);
fprintf('NEARZERO full=%d gauged=%d  (quotient should drop one)\n', z_full, z_phys);
% Any real non-gauge unstable pair kept?
rp = ep(real(ep)>1e-6);
fprintf('POSITIVE(gauged) n=%d : %s\n', numel(rp), mat2str(round(real(rp),8)));
end
