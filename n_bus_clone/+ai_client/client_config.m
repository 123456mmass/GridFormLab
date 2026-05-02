function cfg = client_config()
%CLIENT_CONFIG  Return AI service client configuration.
%
%   cfg = client_config()  returns a struct with:
%       .base_url   - Base URL of the AI service (default http://127.0.0.1:8000)
%       .timeout    - Request timeout in seconds (default 60)
%       .auth_token - Optional Bearer token for authenticated services
%
%   Override by setting environment variables before starting MATLAB:
%       set AI_SERVICE_URL=http://1.2.3.4:8000
%       set AI_SERVICE_TIMEOUT=120
%       set AI_SERVICE_TOKEN=my-secret-token

persistent cfg_

if isempty(cfg_)
    cfg_.base_url   = getenv_default('AI_SERVICE_URL', 'http://127.0.0.1:8000');
    cfg_.timeout    = parse_timeout(getenv_default('AI_SERVICE_TIMEOUT', '60'));
    cfg_.auth_token = getenv_default('AI_SERVICE_TOKEN', '');
end

cfg = cfg_;
end

function val = getenv_default(name, default_val)
    val = getenv(name);
    if isempty(val) || strcmp(val, '')
        val = default_val;
    end
end

function t = parse_timeout(str_val)
    t = str2double(str_val);
    if ~isfinite(t) || t <= 0
        t = 60;
    end
end
