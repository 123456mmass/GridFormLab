function data = collect_export_data(app)
%COLLECT_EXPORT_DATA Gather structured data from last result for JSON/HTML export.

data = [];

if ~isempty(app.last_result)
    r = app.last_result;
    data.system_name = char(r.system_name);
    data.method = char(r.method);
    data.converged = r.converged;
    data.iterations = r.iterations;
    data.num_buses = r.num_buses;
    data.num_lines = r.num_lines;
    data.P_loss_total = r.P_loss_total;
    data.Q_loss_total = r.Q_loss_total;
    if isfield(r, 'bus_voltage') && ~isempty(r.bus_voltage)
        data.bus_voltage = r.bus_voltage(:)';
    end
    if isfield(r, 'bus_angle_deg') && ~isempty(r.bus_angle_deg)
        data.bus_angle_deg = r.bus_angle_deg(:)';
    end
    if isfield(r, 'mismatch_history') && ~isempty(r.mismatch_history)
        data.mismatch_history = r.mismatch_history(:)';
    end
    if isfield(r, 'P_gen') && ~isempty(r.P_gen)
        data.P_gen = r.P_gen(:)';
    end
    if isfield(r, 'Q_gen') && ~isempty(r.Q_gen)
        data.Q_gen = r.Q_gen(:)';
    end
    if isfield(r, 'external_bus_ids') && ~isempty(r.external_bus_ids)
        data.external_bus_ids = r.external_bus_ids(:)';
    end

elseif ~isempty(app.last_cpf)
    r = app.last_cpf;
    data.system_name = char(r.system_name);
    data.method = char(r.method);
    data.target_bus = r.target_bus;
    data.nose_detected = r.nose_detected;
    data.num_points = r.num_points;
    data.lambda_min = r.lambda_min;
    data.lambda_max = r.lambda_max;
    data.voltage_min = r.voltage_min;
    data.voltage_max = r.voltage_max;
    data.stop_reason = char(r.stop_reason);
    if isfield(r, 'lambdas') && ~isempty(r.lambdas)
        data.lambdas = r.lambdas(:)';
    end
    if isfield(r, 'voltages') && ~isempty(r.voltages)
        data.voltages = r.voltages(:)';
    end

elseif ~isempty(app.last_opf)
    r = app.last_opf;
    data.system_name = char(r.system_name);
    data.method = char(r.method);
    data.converged = r.converged;
    data.total_cost = r.total_cost;
    if isfield(r, 'lambda')
        data.lambda = r.lambda;
    end
    if isfield(r, 'P_demand_MW')
        data.P_demand_MW = r.P_demand_MW;
    end
    if isfield(r, 'P_generation_MW') && ~isempty(r.P_generation_MW)
        data.P_generation_MW = r.P_generation_MW(:)';
    end
    if isfield(r, 'generator_ids') && ~isempty(r.generator_ids)
        data.generator_ids = r.generator_ids(:)';
    end
    if isfield(r, 'generator_cost') && ~isempty(r.generator_cost)
        data.generator_cost = r.generator_cost(:)';
    end

elseif ~isempty(app.last_suite)
    data.system_name = '5-Bus-Suite';
    data.method = 'Full 5-bus Suite';
    s = app.last_suite;
    data.nr_iterations = s.newton_raphson.iterations;
    data.nr_converged = s.newton_raphson.converged;
    data.gs_iterations = s.gauss_seidel.iterations;
    data.gs_converged = s.gauss_seidel.converged;
    data.cpf_ls_points = numel(s.cpf_load_scaling.lambdas);
    data.cpf_pc_points = numel(s.cpf_predictor_corrector.lambdas);
end
end
