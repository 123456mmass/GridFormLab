function measure_bus9_windows()
%MEASURE_BUS9_WINDOWS  Re-measure every bus-9 number the V2 report prints,
% against the CURRENT fixed-GFL cache.  Read-only.
pf_init_paths();
A = load(fullfile('output','diagnostics','ieee14_gfm_lock_compare_zeta','adaptive_250s.mat'));
F = load(fullfile('output','diagnostics','ieee14_locked_gfl_diag', ...
    'locked_gfl_diag_gauge_thevenin_fine_250s.mat'));
ra = A.result; rf = F.result;

case_data = cases.case_ieee14bus_eecon49_switch();
mpc = case_data.mpc;
sys = ibr.build_ieee14_switch_system(index_mode='agsi_pp', ...
    case_profile='eecon49_figure4',sg_H=2.5,sg_D=1.0,T_d_on=0.10,T_d_off=1.0);
b9 = find(ra.bus_ids(:)'==9,1);
row9 = find(mpc.bus(:,1)==9,1);
S9pf = (mpc.bus(row9,3)+1i*mpc.bus(row9,4))/mpc.baseMVA;
V9pf = abs(sys.pf.bus_voltage(b9));
y9 = conj(S9pf)/(V9pf^2);
Zf = ra.sched.Zf;

names = {'adaptive','fixed'};
runs  = {ra,rf};
for ii = 1:2
    r = runs{ii}; t = r.t(:);
    V9 = abs(complex(r.y_traj(2*b9-1,:),r.y_traj(2*b9,:))).';
    inf_ = strcmp(r.topology_history(:),'fault');
    m = 1 + 0.20*(t>=r.sched.load_step);
    S = (V9.^2).*conj(m*y9 + inf_*(1/Zf));
    P = real(S); Q = imag(S);
    fprintf('=== %s (n=%d) ===\n',names{ii},numel(t));
    for W = {[100 109],[130 144]}
        a = W{1}; w = t>=a(1) & t<=a(2);
        fprintf('  [%3d %3d] V9 %.4f  P %.4f  Q %.4f   (V9 range %.4f..%.4f)\n', ...
            a(1),a(2),mean(V9(w)),mean(P(w)),mean(Q(w)),min(V9(w)),max(V9(w)));
    end
    fprintf('  terminal t=250: P %.4f  Q %.4f  V9 %.4f\n',P(end),Q(end),V9(end));
    % Converter frequency band over the islanded window.  The fault window
    % [85, 85.5] s is EXCLUDED: the report's frequency claim is about the
    % islanded operating band, and the bolted-fault transient is reported
    % separately as an event extreme.  Both bands are printed here so the
    % report can state whichever it actually claims.
    devs = r.equilibrium.devices; nx=[devs.nx]; nu=[devs.nu];
    xo=cumsum([0 nx(1:end-1)]); uo=cumsum([0 nu(1:end-1)]);
    cv = find(r.device_bus_ids(:)' ~= 1);
    isl_all = t>=20 & t<=145;
    isl_nof = isl_all & ~(t>=85 & t<=85.5);
    fmin=inf; fmax=-inf; gmin=inf; gmax=-inf;
    ji = find(isl_all);
    for jj = 1:numel(ji)
        j = ji(jj); ec = r.event_context_history{j};
        for mm = 1:numel(cv)
            k = cv(mm);
            o = devs(k).reconstruct(t(j),r.x_traj(xo(k)+(1:nx(k)),j), ...
                r.y_traj(:,j),r.u_history(uo(k)+(1:nu(k)),j),ec);
            if isfield(o,'gfm'), v = 60*(1+o.gfm.omega_m);
            elseif isfield(o,'gfl'), v = 60*o.gfl.omega_PLL_pu; else, continue; end
            gmin=min(gmin,v); gmax=max(gmax,v);
            if isl_nof(j), fmin=min(fmin,v); fmax=max(fmax,v); end
        end
    end
    fprintf('  f_conv island, fault window excluded: %.4f .. %.4f Hz\n',fmin,fmax);
    fprintf('  f_conv island, fault window included: %.4f .. %.4f Hz\n',gmin,gmax);
end
end
