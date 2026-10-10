function [req, request_json] = ai_build_request(system_prompt, user_payload, api_key, opts)
%AI_BUILD_REQUEST  The POST this client sends, built where a test can inspect it.
%
%   [REQ, REQUEST_JSON] = ai.ai_build_request(SYSTEM_PROMPT, USER_PAYLOAD, ...
%                                            API_KEY, OPTS)
%
%   REQ is the matlab.net.http.RequestMessage for one chat completion;
%   REQUEST_JSON is the body, kept for provenance.
%
%   THIS IS A SEPARATE FUNCTION SO THE REQUEST CAN BE TESTED WITHOUT A NETWORK.
%   Every mistake it exists to prevent is silent until a real request goes out,
%   and all three were made here once already. Each cost a live run.
%
%   1. THE BODY IS A STRUCT, NOT A PRE-ENCODED JSON STRING. With
%      Content-Type: application/json, matlab.net.http does not pass a char
%      body through -- it encodes that char as a JSON *string*. The gateway
%      then receives "\"{\\\"model\\\":...}\"", finds no model field, and
%      answers HTTP 400 "Missing model". The signature is a Content-Length
%      larger than the char count by exactly one byte per quotation mark plus
%      the two wrapping quotes (216 chars + 34 quotes + 2 = 252). Handing over
%      the struct lets MATLAB encode it once, as an object.
%
%   2. HEADERS MUST BE A ROW VECTOR. A column of HeaderField --
%      [A; B], the shape that reads as the obvious way to write two headers --
%      builds without complaint and then makes send() throw
%      MATLAB:catenate:dimensionMismatch before a packet leaves the machine.
%      The failure names concatenation and not the headers, so it points at the
%      wrong file.
%
%   3. MessageBody TAKES ONE ARGUMENT in the release in use (R2025a).
%      MessageBody(data, 'application/json') raises MATLAB:TooManyInputs, and
%      the content type cannot be set afterwards either, because the
%      ContentType property is read-only. It is carried on the Content-Type
%      header instead, which is where the server reads it from regardless.
%
%   The API key is passed in rather than read here, so this function holds no
%   opinion about where a credential comes from; ai.ai_call_llm reads it from
%   the environment.
%
%   See also ai.ai_call_llm, ai.ai_decode_chat_body.

arguments
    system_prompt (1,1) string
    user_payload (1,1) string
    api_key (1,1) string
    opts struct
end

import matlab.net.http.RequestMessage
import matlab.net.http.MessageBody
import matlab.net.http.HeaderField

% Field order here is not the wire order -- jsonencode sorts names -- so this
% is assembled for readability, not to control the bytes.
payload = struct();
payload.model = char(opts.model);
payload.messages = { ...
    struct('role', 'system', 'content', char(system_prompt)), ...
    struct('role', 'user',   'content', char(user_payload))};
payload.temperature = opts.temperature;
payload.reasoning_effort = char(opts.reasoning_effort);
payload.response_format = struct('type', 'json_object');

request_json = string(jsonencode(payload));

% Row, not column: see note 2 in the header.
headers = [ ...
    HeaderField('Content-Type', 'application/json'), ...
    HeaderField('Authorization', ['Bearer ' char(api_key)])];

% The struct, not request_json: see note 1 in the header.
req = RequestMessage('POST', headers, MessageBody(payload));
end
