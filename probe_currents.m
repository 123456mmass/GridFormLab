function probe_currents()
%PROBE_CURRENTS Verify generator current sign convention matches power flow.
pf_init_paths;
case_data = cases.case_kundur_two_area_classical();
pf_opts = struct('plot_results', false, 'verbose', false, 'max_iter', 50, ...
    'tolerance', 1e-8, 'enforce_q_limits', false);
pf = pfsolver.powerflow_newton_raphson(case_data, pf_opts);
opts = struct('load_model','cc_p_cz_q');
ssa = stability.kundur_ex126_sauer_pai_ssa('pf', pf, 'options', opts);
init = ssa.init;

fprintf('%-4s %12s %12s %12s %12s\n','gen','Ig_re(machine)','Ig_im','Ig_re(pf)','Ig_im(pf)');
for k = 1:init.ng
    bidx = init.bus_idx(k);
    Vt = pf.bus_voltage(bidx) * exp(1i*deg2rad(pf.bus_angle_deg(bidx)));
    Sgen = pf.P_generation(bidx) + 1i*pf.Q_generation(bidx);
    Ig_pf = conj(Sgen / Vt);   % current out of generator (into network)
    % Machine-frame currents at op:
    delta = init.delta(k); Id = init.Id(k); Iq = init.Iq(k);
    Ire = sin(delta)*Id + cos(delta)*Iq;
    Iim = -cos(delta)*Id + sin(delta)*Iq;
    Ig_machine = complex(Ire, Iim);
    fprintf('%-4s %12.4f %12.4f %12.4f %12.4f\n', ...
        case_data.machines.units(k).gen_id, real(Ig_machine), imag(Ig_machine), ...
        real(Ig_pf), imag(Ig_pf));
end
end
