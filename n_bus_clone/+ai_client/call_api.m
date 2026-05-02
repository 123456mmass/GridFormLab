function [response, ok] = call_api(endpoint, data)
%CALL_API  Send a POST request to the AI service.
%
%   [response, ok] = call_api(endpoint, data)  sends a JSON payload
%   to the given endpoint and returns the decoded response struct.
%
%   endpoint  — e.g. '/analyze', '/analyze/cpf', '/ask'
%   data      — struct (will be JSON-encoded)
%
%   response  — decoded JSON struct on success, or struct('error', ...) on failure
%   ok        — true on HTTP 2xx, false otherwise

cfg = ai_client.client_config();
url = [cfg.base_url endpoint];

if ~isfinite(cfg.timeout) || cfg.timeout <= 0
    cfg.timeout = 60;
end

opts = weboptions('MediaType', 'application/json', ...
                  'RequestMethod', 'post', ...
                  'Timeout', cfg.timeout);

try
    clean = sanitize_json(data);
    raw = webwrite(url, clean, opts);
    response = raw;
    ok = true;
catch ME
    response = struct('error', ME.message);
    ok = false;
    warning('AI_SERVICE:CALL_FAILED', ...
        'AI service call to %s failed: %s', endpoint, ME.message);
end
end

function x = sanitize_json(x)
%SANITIZE_JSON  Recursively convert complex/unsupported values to JSON-safe types.
if isnumeric(x) && ~isreal(x)
    x = abs(x);
elseif isstruct(x)
    f = fieldnames(x);
    for i = 1:numel(f)
        x.(f{i}) = sanitize_json(x.(f{i}));
    end
elseif iscell(x)
    for i = 1:numel(x)
        x{i} = sanitize_json(x{i});
    end
end
end
