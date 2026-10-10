function [content, why] = ai_decode_chat_body(body)
%AI_DECODE_CHAT_BODY  Assistant text out of a chat-completion response body.
%
%   [CONTENT, WHY] = ai.ai_decode_chat_body(BODY)
%
%   BODY is whatever matlab.net.http left in response.Body.Data: a struct when
%   the Content-Type invited parsing, or the raw text when it did not. CONTENT
%   is the assistant message; WHY is empty on success and a human-readable
%   cause otherwise.
%
%   THE TRAILING SSE TERMINATOR. The gateway in use answers a NON-streaming
%   request with a complete JSON object followed by the server-sent-events
%   terminator:
%       {"id":...,"choices":[...]}data: [DONE]
%   That trailing token makes the body invalid JSON, so a decoder that trusts
%   the Content-Type header rejects a reply that is entirely well formed. This
%   is not a hypothetical: it is what the first real request through this
%   client returned.
%
%   Only a TRAILING terminator is removed. A body that is genuinely a stream of
%   data: lines is refused rather than partly decoded, because reading the first
%   frame of a real stream would hide a transport problem instead of fixing one.
%
%   This is a separate function, rather than a local one inside ai.ai_call_llm,
%   so the decoding can be tested against a recorded body with no network.
%
%   See also ai.ai_call_llm, ai.ai_parse_decision.

arguments
    body = []
end

content = "";
why = "";

if isempty(body)
    why = "Response body is empty.";
    return;
end

d = body;
if ischar(d) || isstring(d)
    txt = strip_sse_trailer(char(string(d)));
    if is_rejected_stream(txt)
        why = ['Response body is a server-sent event stream, not a single ' ...
            'completion. This client sends non-streaming requests; a stream ' ...
            'here means the request or the endpoint is not what it appears.'];
        return;
    end
    try
        d = jsondecode(txt);
    catch
        why = "Response body is not valid JSON.";
        return;
    end
end

if ~isstruct(d)
    why = "Response body is not a JSON object.";
    return;
end
if isfield(d, 'error')
    why = "The endpoint returned an error object: " + ...
        truncate(string(jsonencode(d.error)));
    return;
end
if ~isfield(d, 'choices') || isempty(d.choices)
    why = "Response has no choices array.";
    return;
end
ch = d.choices(1);
if ~isfield(ch, 'message') || ~isfield(ch.message, 'content')
    why = "First choice carries no message.content.";
    return;
end
content = string(ch.message.content);
if strlength(strtrim(content)) == 0
    why = "message.content is empty.";
end
end

% =========================================================================
function txt = strip_sse_trailer(txt)
%STRIP_SSE_TRAILER  Remove a trailing [DONE] sentinel, and nothing else.
%   Deliberately narrow. Any other trailing junk is left in place so the
%   decode fails and says so, rather than this function guessing at how much
%   of the body was not the body.
txt = regexprep(txt, '(\s*data:\s*\[DONE\]\s*)+$', '');
end

function tf = is_rejected_stream(txt)
%IS_REJECTED_STREAM  True when what remains still leads with a data: frame.
tf = ~isempty(regexp(txt, '^\s*data:\s*', 'once'));
end

function s = truncate(s)
%TRUNCATE  Keep a log line readable without hiding the nature of the failure.
maxlen = 400;
s = string(s);
if strlength(s) > maxlen
    s = extractBefore(s, maxlen) + " ...(truncated)";
end
end
