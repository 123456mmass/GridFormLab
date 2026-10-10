function probe_ne39_sg_on_spectrum()
pf_init_paths();
s = cases.scenario_ne39_1sg_9ibr(struct('study_capability',true));
[dev,~] = stability.build_mixed_resource_devices(s.case_data,s.resources,s.scenario_opt);
eq = stability.mixed_equilibrium_solve(s.case_data,struct('devices',dev),struct('verbose',false));
fprintf('eq converged=%d kcl=%g\n',eq.converged,eq.physical_kcl_norm);
for factor = [0.5 1 2]
    opt = struct('fd_eps',3e-6*factor,'verbose',false);
    opt.full_kcl = true; opt.u_eq = eq.u_eq;
    opt.event_context = eq.equilibrium_context;
    opt.active_state_indices = eq.active_state_indices;
    opt.reference_device_index = 1;
    a = stability.composite_sssa_model(dev,eq.x0,eq.y0,s.case_data,opt);
    fprintf('factor %.1f fields: %s\n',factor,strjoin(fieldnames(a),','));
    if ~isfield(a,'physical_eigenvalues'), continue; end
    lam = a.physical_eigenvalues(:);
    zeta = -real(lam)./abs(lam);
    [zw,j] = min(zeta);
    fprintf('factor %.1f n=%d worst_zeta=%g at %g%+gi  maxRe=%g\n', ...
        factor,numel(lam),zw,real(lam(j)),imag(lam(j)),max(real(lam)));
    near = abs(lam) < 1e-4;
    fprintf('  roots |lambda|<1e-4: %d\n',nnz(near));
    show = lam(near);
    for k = 1:numel(show)
        fprintf('    %+.6e%+.6ei\n',real(show(k)),imag(show(k)));
    end
end
end
