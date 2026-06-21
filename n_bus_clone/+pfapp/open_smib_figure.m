function open_smib_figure(app)
%OPEN_SMIB_FIGURE Open standalone SMIB figures for the last result.
%   Delegates to the internal/plotting/smib_plot_* functions, picking the
%   set of plots most relevant to the active Kundur model.

res = app.last_smib;
if isempty(res)
    pfapp.append_log(app, 'No SMIB result to plot. Run SMIB Stability Analysis first.');
    return;
end

model = res.model;
vis = struct('visible', 'on');
c = res.case;
machine = c.machine;

switch model
    case 'A'
        op = res.op; w0 = res.w0;
        KDvals = -10:2:20; eigc = cell(numel(KDvals), 1);
        for i = 1:numel(KDvals)
            s = smib.smib_build_state_matrix('A', struct('H', machine.H, ...
                'KD', KDvals(i), 'Ks', op.Ks, 'w0', w0));
            eigc{i} = eig(s.A);
        end
        sweep = struct('values', KDvals, 'eigenvalues', {eigc}, ...
            'param_name', 'K_D', 'title', 'SMIB classical: eigenvalues vs K_D');
        o1 = vis; o1.mark_points = struct('value', {-10, 0, 10}, ...
            'label', {'K_D=-10', 'K_D=0', 'K_D=10'});
        smib_plot_root_locus(sweep, o1);
        sysA10 = smib.smib_build_state_matrix('A', struct('H', machine.H, ...
            'KD', 10, 'Ks', op.Ks, 'w0', w0));
        smib_plot_step_response(sysA10, vis);
        smib_plot_power_response(sysA10, vis);

    case 'B'
        smib_plot_mode_shape(res.analyze, vis);
        sysB = res.sys;
        smib_plot_step_response(sysB, vis);
        smib_plot_power_response(sysB, vis);

    case 'C'
        K = res.K; ex = res.ex; w0 = res.w0;
        omega_eval = 10;
        if isfield(res, 'golden') && isfield(res.golden, 'omega_eval')
            omega_eval = res.golden.omega_eval;
        end
        o4 = vis; o4.omega_eval = omega_eval;
        smib_plot_torque_vs_ka(K, ex, machine.H, w0, o4);
        smib_plot_mode_shape(res.analyze, vis);
        smib_plot_step_response(res.sys, vis);

    case 'D'
        setAVR = struct('eigenvalues', res.analyze_avr.eigenvalues, 'name', 'AVR only (K_A=200)', ...
            'color', [0.83 0.20 0.15], 'marker', 'o');
        setPSS = struct('eigenvalues', res.analyze.eigenvalues, 'name', 'AVR + PSS', ...
            'color', [0.05 0.36 0.60], 'marker', 's');
        smib_plot_eig_comparison([setAVR, setPSS], vis);
        smib_plot_step_response(res.sys, vis);
        smib_plot_mode_shape(res.analyze, vis);

    otherwise
        pfapp.append_log(app, sprintf('No standalone plots for SMIB model %s.', model));
        return;
end

pfapp.append_log(app, sprintf('Opened SMIB model %s standalone figures.', model));
end
