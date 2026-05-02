function app = ai_chat_action(app)
%AI_CHAT_ACTION Send user question to AI service and display response.

question = strtrim(app.ai_chat_input.Value);
if isempty(question)
    return;
end

% Append user message
current = app.ai_chat_display.Value;
if ischar(current), current = {current}; end
app.ai_chat_display.Value = [current(:); {''; ['You: ' question]}];
app.ai_chat_input.Value = '';
drawnow limitrate;

% Build results context from last result
results_json = '';
if ~isempty(app.last_result)
    r = app.last_result;
    s = struct('system', r.system_name, 'method', r.method, ...
        'converged', r.converged, 'iterations', r.iterations, ...
        'P_loss_pu', r.P_loss_total, 'num_buses', r.num_buses);
    try results_json = jsonencode(s); catch, end
elseif ~isempty(app.last_cpf)
    r = app.last_cpf;
    s = struct('system', r.system_name, 'method', r.method, ...
        'target_bus', r.target_bus, 'nose_detected', r.nose_detected, ...
        'lambda_max', max(r.lambdas));
    try results_json = jsonencode(s); catch, end
elseif ~isempty(app.last_opf)
    r = app.last_opf;
    s = struct('system', r.system_name, 'method', r.method, ...
        'total_cost', r.total_cost, 'converged', r.converged, ...
        'demand_MW', r.P_demand_MW);
    try results_json = jsonencode(s); catch, end
end

try
    response = ai_client.ask(question, results_json);
    if isstruct(response) && isfield(response, 'answer')
        answer = strtrim(response.answer);
    elseif ischar(response) || isstring(response)
        answer = char(response);
    else
        answer = 'No response from AI service.';
    end
catch err
    answer = sprintf('AI service error: %s\n\nMake sure the AI service is running:\n  cd ai_service && python server.py', err.message);
end

% Append AI response
current = app.ai_chat_display.Value;
if ischar(current), current = {current}; end
app.ai_chat_display.Value = [current(:); {''; ['AI: ' answer]}];
scroll_to_bottom(app);
end

function scroll_to_bottom(app)
drawnow;
try
    jTextArea = findjobj(app.ai_chat_display);
    if ~isempty(jTextArea)
        jTextArea.setCaretPosition(jTextArea.getDocument().getLength());
    end
catch
end
end
