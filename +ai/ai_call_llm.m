function resp = ai_call_llm(system_prompt, user_payload, opts)
%Ai_CALL_LLM  POST one chat-completion request and return the assistant text.
%
%   RESP = ai.ai_call_llm(SYSTEM_PROMPT, USER_PAYLOAD, OPTS)
%
%   Sends an OpenAI-compatible chat-completion request with
%       Authorization: Bearer <OPTS.api_key_env>
%       Content-Type: application/json
%   and the options OPTS.model, OPTS.temperature, OPTS.reasoning_effort, plus
%   response_format = {"type":"json_object"} so the reply is a JSON object
%   rather than prose wrapped around one.
%
%   THE API KEY IS READ FROM THE ENVIRONMENT and never appears in a source
%   file: this repository is version controlled, and a key written into a .m
%   file would be committed with it. Set the variable named by OPTS.api_key_env
%   (default LLM_API_KEY) before running.
%
%   THIS FUNCTION NEVER THROWS FOR A TRANSPORT FAILURE. It returns
%   RESP.ok = false with a stable RESP.error_id, because the caller's contract
%   is to keep the supervisory loop running on its deterministic fallback
%   rather than to abort the study. A thrown error here would stop a run that
%   has a perfectly good answer available.
%
%   RESP fields:
%     ok            logical
%     content       assistant message text ("" when ok is false)
%     http_status   numeric, NaN if the request never completed
%     attempts      requests actually sent
%     elapsed_s     wall clock over all attempts
%     error_id      "" when ok; otherwise a stable identifier
%     error_message human-readable cause
%     request_json  the exact body sent, for provenance
%     response_json the exact body received, for provenance
%
%   Retried: transport errors, timeouts, HTTP 408/429, and 5xx. Not retried:
%   other 4xx, which a second identical request cannot fix.
%
%   See also ai.ai_parse_decision, ai.ai_fallback_selector.

arguments
    system_prompt (1,1) string
    user_payload (1,1) string
    opts struct = ai.ai_supervisor_defaults()
end

resp = struct('ok', false, 'content', "", 'http_status', NaN, ...
    'attempts', 0, 'elapsed_s', NaN, 'error_id', "", 'error_message', "", ...
    'request_json', "", 'response_json', "");

if opts.force_fallback
    resp.error_id = "ai:ai_call_llm:forcedFallback";
    resp.error_message = "force_fallback is set; no request was sent.";
    return;
end

key_name = char(opts.api_key_env);
api_key = strtrim(getenv(key_name));
if isempty(api_key)
    resp.error_id = "ai:ai_call_llm:missingApiKey";
    resp.error_message = sprintf( ...
        ['Environment variable %s is empty. Set it to the API key before ' ...
         'running; the key is deliberately not read from any file in this ' ...
         'repository.'], key_name);
    return;
end

[req, request_json] = ai.ai_build_request(system_prompt, user_payload, ...
    string(api_key), opts);
resp.request_json = string(request_json);

import matlab.net.URI
import matlab.net.http.HTTPOptions

uri = URI(char(opts.endpoint));
% ConnectTimeout bounds reaching the endpoint; ResponseTimeout bounds waiting
% for it to answer. Both are set, because a hang at either stage leaves the
% supervisory loop with no verdict, which is the failure mode that matters.
http_opts = HTTPOptions('ConnectTimeout', opts.timeout_s, ...
    'ResponseTimeout', opts.timeout_s);

total = 1 + max(0, round(opts.max_retries));
t0 = tic;
for attempt = 1:total
    resp.attempts = attempt;
    try
        [response, ~, ~] = req.send(uri, http_opts);
    catch me
        resp = record_transport_failure(resp, me);
        if attempt < total
            pause(opts.retry_backoff_s * 2^(attempt-1));
            continue;
        end
        resp.elapsed_s = toc(t0);
        return;
    end

    status = double(response.StatusCode);
    resp.http_status = status;
    resp.response_json = body_text(response);

    if status ~= 200
        resp.error_id = "ai:ai_call_llm:httpStatus";
        resp.error_message = sprintf('HTTP %d from %s. Body: %s', ...
            status, opts.endpoint, truncate(resp.response_json));
        if is_retriable_status(status) && attempt < total
            pause(opts.retry_backoff_s * 2^(attempt-1));
            continue;
        end
        resp.elapsed_s = toc(t0);
        return;
    end

    [content, why] = ai.ai_decode_chat_body(response.Body.Data);
    if strlength(why) > 0
        resp.error_id = "ai:ai_call_llm:badResponseShape";
        resp.error_message = why + " Body: " + truncate(resp.response_json);
        if attempt < total
            pause(opts.retry_backoff_s * 2^(attempt-1));
            continue;
        end
        resp.elapsed_s = toc(t0);
        return;
    end

    resp.ok = true;
    resp.content = content;
    resp.error_id = "";
    resp.error_message = "";
    resp.elapsed_s = toc(t0);
    return;
end
resp.elapsed_s = toc(t0);
end

% =========================================================================
function resp = record_transport_failure(resp, me)
%RECORD_TRANSPORT_FAILURE  Classify a caught send() error.
%   A timeout and a DNS failure are both "no answer", but they are not the
%   same finding for whoever reads the log, so they keep distinct ids.
id = string(me.identifier);
msg = string(me.message);
if contains(lower(msg), "timed out") || contains(lower(msg), "timeout")
    resp.error_id = "ai:ai_call_llm:timeout";
elseif contains(lower(msg), "name or service") || contains(lower(msg), "dns")
    resp.error_id = "ai:ai_call_llm:dnsFailure";
else
    resp.error_id = "ai:ai_call_llm:transport";
end
resp.error_message = "Request failed (" + id + "): " + msg;
end

function tf = is_retriable_status(status)
%IS_RETRIABLE_STATUS  Server-side or throttling statuses worth a second try.
tf = status == 408 || status == 429 || (status >= 500 && status < 600);
end

function s = body_text(response)
%BODY_TEXT  Response body as text, whatever MATLAB auto-parsed it into.
d = response.Body.Data;
if ischar(d)
    s = string(d);
elseif isstring(d)
    s = d;
elseif isempty(d)
    s = "";
else
    try
        s = string(jsonencode(d));
    catch
        s = "<unserializable response body>";
    end
end
end

function s = truncate(s)
%TRUNCATE  Keep log lines readable without hiding the nature of the failure.
maxlen = 400;
s = string(s);
if strlength(s) > maxlen
    s = extractBefore(s, maxlen) + " ...(truncated)";
end
end
