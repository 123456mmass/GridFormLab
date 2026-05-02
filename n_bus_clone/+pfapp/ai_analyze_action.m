function app = ai_analyze_action(app, fig)
%AI_ANALYZE_ACTION Auto-analyze last result using AI service.

app = pfapp.set_busy(app, true);
app = pfapp.start_progress(app, fig, 'AI analyzing ...', 'Sending results to AI service.');

try
    analysis_text = '';
    structured_info = '';

    if ~isempty(app.last_result)
        r = app.last_result;
        bus_data = struct();
        if isfield(r, 'bus_voltage') && isfield(r, 'bus_angle_deg') && isfield(r, 'external_bus_ids')
            bus_data.bus = r.external_bus_ids(:)';
            bus_data.voltage = r.bus_voltage(:)';
            bus_data.angle = r.bus_angle_deg(:)';
        end
        pfapp.append_log(app, 'AI: Analyzing power flow results...');
        resp = ai_client.analyze(r.method, r);
        analysis_text = get_analysis_text(resp);
        if isfield(resp, 'structured') && ~isempty(resp.structured)
            structured_info = jsonencode(resp.structured, 'PrettyPrint', true);
        end

    elseif ~isempty(app.last_cpf)
        r = app.last_cpf;
        r.num_points = numel(r.lambdas);
        r.lambda_min = min(r.lambdas);
        r.lambda_max = max(r.lambdas);
        r.voltage_min = min(r.target_voltage);
        r.voltage_max = max(r.target_voltage);
        pfapp.append_log(app, 'AI: Analyzing CPF results...');
        resp = ai_client.analyze_cpf(r);
        analysis_text = get_analysis_text(resp);
        if isfield(resp, 'structured') && ~isempty(resp.structured)
            structured_info = jsonencode(resp.structured, 'PrettyPrint', true);
        end

    elseif ~isempty(app.last_opf)
        r = app.last_opf;
        pfapp.append_log(app, 'AI: Analyzing OPF results...');
        resp = ai_client.analyze_opf(r);
        analysis_text = get_analysis_text(resp);
        if isfield(resp, 'structured') && ~isempty(resp.structured)
            structured_info = jsonencode(resp.structured, 'PrettyPrint', true);
        end

    elseif ~isempty(app.last_suite)
        pfapp.append_log(app, 'AI: Analyzing suite results...');
        nr = app.last_suite.newton_raphson;
        gs = app.last_suite.gauss_seidel;
        resp = ai_client.compare(nr.method, nr, gs.method, gs);
        analysis_text = get_analysis_text(resp);
    else
        analysis_text = 'No results to analyze. Run a power flow method first.';
        structured_info = '';
    end

    % Show in AI Chat tab
    if ~isempty(analysis_text)
        current = app.ai_chat_display.Value;
        if ischar(current), current = {current}; end
        new_lines = {''; '--- AI Analysis ---'; analysis_text};
        if ~isempty(structured_info)
            new_lines = [new_lines; {''; 'Structured Findings:'; structured_info}];
        end
        app.ai_chat_display.Value = [current(:); new_lines];
        pfapp.append_log(app, 'AI analysis complete.');
    end

catch err
    pfapp.append_log(app, sprintf('AI ANALYSIS ERROR: %s', err.message));
    current = app.ai_chat_display.Value;
    if ischar(current), current = {current}; end
    app.ai_chat_display.Value = [current(:); {''; ['AI Error: ' err.message]; ...
        'Make sure the AI service is running: cd ai_service && python server.py'}];
end

app = pfapp.set_busy(app, false);
end

function text = get_analysis_text(resp)
text = '';
if isstruct(resp)
    if isfield(resp, 'analysis') && ~isempty(resp.analysis)
        text = char(resp.analysis);
    elseif isfield(resp, 'answer') && ~isempty(resp.answer)
        text = char(resp.answer);
    elseif isfield(resp, 'report') && ~isempty(resp.report)
        text = char(resp.report);
    end
elseif ischar(resp) || isstring(resp)
    text = char(resp);
end
end
