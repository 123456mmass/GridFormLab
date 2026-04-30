function result = ask(question, results_json)
%ASK  Ask a free-form question to the AI, optionally with data context.
%
%   result = ai_client.ask(question)
%   result = ai_client.ask(question, results_json)
%
%   question     — string
%   results_json — optional JSON string or struct (will be JSON-encoded)
%
%   Returns struct with:
%       .answer — AI response text

data = struct('question', question);

if nargin > 1 && ~isempty(results_json)
    if isstruct(results_json)
        data.results_json = jsonencode(results_json);
    else
        data.results_json = char(results_json);
    end
end

[resp, ok] = ai_client.call_api('/ask', data);
if ok
    result = resp;
else
    result = resp;
end
end
