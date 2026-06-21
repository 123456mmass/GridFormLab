function app = run_smib_action(app, fig)
%RUN_SMIB_ACTION Run SMIB small-signal stability analysis for the selected
%   case and stash the result on app.last_smib. Dispatches to the right
%   Kundur model (A/B/C/D) based on the case's .model field and mirrors the
%   golden-reference workflow in run_smib_example.m.
%
%   NOTE: the local result struct is named `res` (not `smib`) so the +smib
%   package namespace stays resolvable as smib.<func> throughout.

app = pfapp.set_busy(app, true);
app = pfapp.start_progress(app, fig, 'Running SMIB stability analysis ...', ...
    'Building state matrix and computing eigenproperties.');
try
    case_data = pfapp.load_selected_case(app);
    app.last_case_data = case_data;
    if ~pfapp.is_smib_case(case_data)
        error('smib:badCase', ...
            'Selected case "%s" is not a Kundur SMIB case. Pick a case_kundur_smib_* case, or switch to a power-flow method.', ...
            case_data.system_name);
    end

    model = upper(case_data.model);
    w0 = 2 * pi * case_data.base_values.frequency_Hz;
    pfapp.append_log(app, sprintf('Running SMIB Model %s on %s ...', model, case_data.system_name));

    res = struct('model', model, 'case', case_data, 'w0', w0);

    switch model
        case 'A'
            op = smib.smib_classical_init(case_data.machine, case_data.network, case_data.operating);
            sys = smib.smib_build_state_matrix('A', struct( ...
                'H', case_data.machine.H, 'KD', case_data.machine.KD, ...
                'Ks', op.Ks, 'w0', w0));
            res.op = op; res.sys = sys;
            res.analyze = smib.smib_analyze(sys);

        case 'B'
            op = smib.smib_dq_init(case_data.machine, case_data.network, case_data.operating);
            K = smib.smib_k_constants(case_data.machine, case_data.network, op, w0);
            sys = smib.smib_build_state_matrix('B', struct( ...
                'H', case_data.machine.H, 'KD', case_data.machine.KD, 'w0', w0, ...
                'K1', K.K1, 'K2', K.K2, 'a32', K.a32, 'a33', K.a33, 'b3', K.b3));
            res.op = op; res.K = K; res.sys = sys;
            res.analyze = smib.smib_analyze(sys);

        case 'C'
            K = case_data.k_constants;
            ex = case_data.exciter;
            sys = smib.smib_build_state_matrix('C', struct( ...
                'H', case_data.machine.H, 'KD', case_data.machine.KD, 'w0', w0, ...
                'K1', K.K1, 'K2', K.K2, 'K3', K.K3, 'K4', K.K4, ...
                'K5', K.K5, 'K6', K.K6, 'T3', K.T3, 'TR', ex.TR, 'KA', ex.KA));
            res.K = K; res.ex = ex; res.sys = sys;
            res.analyze = smib.smib_analyze(sys);

        case 'D'
            K = case_data.k_constants;
            ex = case_data.exciter;
            pss = case_data.pss;
            sys_avr = smib.smib_build_state_matrix('C', struct( ...
                'H', case_data.machine.H, 'KD', case_data.machine.KD, 'w0', w0, ...
                'K1', K.K1, 'K2', K.K2, 'K3', K.K3, 'K4', K.K4, ...
                'K5', K.K5, 'K6', K.K6, 'T3', K.T3, 'TR', ex.TR, 'KA', ex.KA));
            sys_pss = smib.smib_build_state_matrix('D', struct( ...
                'H', case_data.machine.H, 'KD', case_data.machine.KD, 'w0', w0, ...
                'K1', K.K1, 'K2', K.K2, 'K3', K.K3, 'K4', K.K4, ...
                'K5', K.K5, 'K6', K.K6, 'T3', K.T3, 'TR', ex.TR, 'KA', ex.KA, ...
                'KSTAB', pss.KSTAB, 'Tw', pss.Tw, 'T1', pss.T1, 'T2', pss.T2));
            res.K = K; res.ex = ex; res.pss = pss;
            res.sys_avr = sys_avr; res.sys = sys_pss;
            res.analyze_avr = smib.smib_analyze(sys_avr);
            res.analyze = smib.smib_analyze(sys_pss);

        otherwise
            error('smib:badModel', 'Unknown SMIB model "%s".', model);
    end

    if isfield(case_data, 'reference_solution')
        res.golden = case_data.reference_solution;
    end

    app.last_smib = res;
    app.last_result = []; app.last_cpf = []; app.last_suite = []; app.last_opf = [];
    pfapp.show_smib_result(app);
    pfapp.append_log(app, pfapp.smib_summary_line(res));

    if app.auto_separate_checkbox.Value
        pfapp.open_smib_figure(app);
    end
catch err
    pfapp.append_log(app, sprintf('SMIB ERROR: %s', err.message));
    try
        uialert(fig, err.message, 'SMIB Analysis Failed');
    catch
    end
end
app = pfapp.set_busy(app, false);
end
