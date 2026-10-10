function probe_ne39_sssa_mode()
%PROBE_NE39_SSSA_MODE  FD-step refinement of the NE39 full-active SSSA.
%   Rebuilds the composite SSSA at a sweep of fd_eps. If a positive-real mode
%   is physical it must be insensitive to the step; if it is an FD artifact it
%   moves/vanishes as the step is refined. No tolerance is loosened anywhere.
pf_init_paths();
s = cases.scenario_ne39_5sg_5ibr();
[devices,~] = stability.build_mixed_resource_devices( ...
    s.case_data, s.resources, s.scenario_opt);
eq = stability.mixed_equilibrium_solve(s.case_data, ...
    struct('devices',devices), struct('verbose',false));
fprintf('EQ active=%d nx=%d ny=%d ref_dev=%d\n', numel(eq.active_state_indices), ...
    numel(eq.x0), numel(eq.y0), eq.reference.device_index);

eps_list = [3e-6 1e-6 3e-7 1e-7];
for e = eps_list
    m = stability.composite_sssa_model(eq.devices, eq.x0, eq.y0, s.case_data, ...
        struct('full_kcl',true,'u_eq',eq.u_eq, ...
        'event_context',eq.equilibrium_context, ...
        'active_state_indices',eq.active_state_indices,'fd_eps',e, ...
        'reference_device_index',eq.reference.device_index));
    ev = m.eigenvalues; re = real(ev);
    [~, ix] = sort(re, 'descend');
    fprintf('eps=%.1e n=%d maxRe=%.6e nPos=%d rcond=%s\n', e, numel(ev), ...
        max(re), sum(re>1e-6), num2str(getfield_safe(m,'Jacobian_rcond')));
    for j = 1:min(3, numel(ev))
        fprintf('   top%d = %+.6e %+.6ei\n', j, real(ev(ix(j))), imag(ev(ix(j))));
    end
    % Name the states that participate in the most positive real mode.
    try
        [V,~] = eig(m.A);
        v = V(:, ix(1));
        [~, pk] = sort(abs(v), 'descend');
        fprintf('   participation(top abs): %s\n', strjoin(string(pk(1:min(5,numel(pk)))), ','));
        if isfield(m,'state_names')
            fprintf('   names: %s\n', strjoin(string(m.state_names(pk(1:min(5,numel(pk))))), ','));
        end
    catch
    end
end
end

function v = getfield_safe(s, f)
v = NaN;
if isfield(s, f) && isnumeric(s.(f)) && isscalar(s.(f)), v = s.(f); end
end
