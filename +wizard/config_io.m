function varargout = config_io(op, a, b)
%CONFIG_IO  Save/load validated wizard configurations (wizard_config_v1).
%   config_io('save', cfg, path) writes a validated configuration to PATH.
%   cfg = config_io('load', path) reads a configuration from PATH.
%   [cfg, fp] = config_io('load', path) also returns the recomputed fingerprint.
%
%   The two ops have different argument shapes:
%     save: (op, cfg, path)   — cfg is the request struct, path is the file
%     load: (op, path)        — a is the file path; no cfg argument
%   This dispatcher routes by op so callers do not have to pad a dummy cfg.
%
%   The schema is wizard_config_v1 — a SEPARATE schema and fingerprint from
%   Section H or selector fingerprints (different ownership/meaning). The
%   fingerprint is a canonical serialization hash of the stable request
%   fields (analysis, case_id, options, events_policy) excluding volatile
%   values (timestamps, paths, wall-clock) per correction #9.
%
%   This function is PURE w.r.t. the production result: it only reads/writes
%   configuration files. It does NOT invoke solvers or load solved states.
%
%   See also: wizard.BUILD_REQUEST, wizard.VALIDATE_REQUEST.

switch lower(op)
    case 'save'
        cfg = a;
        path = b;
        config_io_save(cfg, path);
        varargout{1} = path;
    case 'load'
        path = a;
        [cfg, fp] = config_io_load(path);
        varargout{1} = cfg;
        if nargout > 1, varargout{2} = fp; end
    otherwise
        error('wizard:config_io:badOp', ...
            'Unknown op %s (expected save/load).', op);
end
end

function config_io_save(cfg, path)
if isempty(path)
    error('wizard:config_io:noPath', 'A file path is required for save.');
end
req = ensure_request(cfg);
req = wizard.validate_request(req);
% Build a portable on-disk representation (no function handles, no volatile).
portable = request_to_portable(req);
record = struct( ...
    'schema_version', 'wizard_config_v1', ...
    'request', portable, ...
    'fingerprint', '');
% The on-disk request JSON (includes interactive for round-trip fidelity).
on_disk_request_json = jsonencode(record.request, 'PrettyPrint', true);
% Fingerprint excludes the volatile 'interactive' flag: hash a copy of the
% portable request with that field removed. Both save and load compute the
% fingerprint the same way (load re-encodes the decoded request minus
% interactive), so the stored and recomputed fingerprints agree.
fp_source = rmfield(record.request, 'interactive');
fp_json = jsonencode(fp_source, 'PrettyPrint', true);
record.fingerprint = hash_canonical(fp_json);
fid = fopen(path, 'w');
if fid < 0
    error('wizard:config_io:writeFailed', 'Cannot write to %s.', path);
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, '%s\n', jsonencode(record, 'PrettyPrint', true));
end

function [cfg, fp] = config_io_load(path)
if isempty(path) || exist(path, 'file') ~= 2
    error('wizard:config_io:readFailed', 'Cannot read %s.', path);
end
txt = fileread(path);
record = jsondecode(txt);
if ~isstruct(record) || ~isfield(record, 'schema_version') ...
        || ~strcmp(record.schema_version, 'wizard_config_v1')
    error('wizard:config_io:badSchema', ...
        'Not a wizard_config_v1 file.');
end
% Recompute fingerprint the same way save did: from the request JSON with the
% volatile 'interactive' field removed. Both sides operate on the decoded
% request struct, so the canonical form agrees.
fp_source = record.request;
if isfield(fp_source, 'interactive')
    fp_source = rmfield(fp_source, 'interactive');
end
fp_json = jsonencode(fp_source, 'PrettyPrint', true);
fp = hash_canonical(fp_json);
record_fp = '';
if isfield(record, 'fingerprint'), record_fp = record.fingerprint; end
if ~isempty(record_fp) && ~strcmp(record_fp, fp)
    error('wizard:config_io:fingerprintMismatch', ...
        'Stored fingerprint %s != recomputed %s.', record_fp, fp);
end
req = request_from_portable(record.request);
req = wizard.validate_request(req);
cfg = req;
end

function fp = hash_canonical(s)
% Deterministic SHA-256 hash of a string (base MATLAB via Java).
try
    md = java.security.MessageDigest.getInstance('SHA-256');
    md.update(uint8(s));
    b = typecast(md.digest, 'uint8');
    fp = sprintf('%02x', b);
catch
    v = uint8(s);
    sumv = 0;
    for k = 1:numel(v), sumv = sumv + double(v(k)); end
    fp = sprintf('cs%016d', sumv);
end
end

function req = ensure_request(cfg)
if isstruct(cfg) && isfield(cfg, 'schema_version') ...
        && strcmp(cfg.schema_version, 'wizard_request_v1')
    req = cfg;
else
    error('wizard:config_io:notRequest', ...
        'Input must be a wizard_request_v1 struct.');
end
end

function fp = fingerprint(req)
% Canonical fingerprint of stable request fields (correction #9: exclude
% volatile values). Computes the fingerprint from the on-disk portable
% representation with the volatile 'interactive' flag removed, so save and
% load agree (both hash jsonencode of the same struct minus interactive).
p = request_to_portable(req);
p = rmfield(p, 'interactive');
fp = hash_canonical(jsonencode(p, 'PrettyPrint', true));
end

function p = request_to_portable(req)
p = struct( ...
    'analysis', char(req.analysis), ...
    'case_id', char(req.case_id), ...
    'options', options_to_portable(req.options), ...
    'events', events_to_portable(req.events), ...
    'events_policy', char(req.events_policy), ...
    'interactive', logical(req.interactive), ...
    'schema_version', char(req.schema_version));
end

function req = request_from_portable(p)
% Reconstruct a request. options/events are restored as structs; complex
% numbers in events (e.g. Zf) are stored as {real, imag} pairs. The
% 'interactive' flag is volatile UI session state and may be absent from
% the stored portable form (it is excluded from the fingerprint).
interactive = false;
if isfield(p, 'interactive'), interactive = logical(p.interactive); end
req = struct( ...
    'analysis', char(p.analysis), ...
    'case_id', char(p.case_id), ...
    'options', portable_to_options(p.options), ...
    'events', portable_to_events(p.events), ...
    'events_policy', char(p.events_policy), ...
    'interactive', interactive, ...
    'schema_version', 'wizard_request_v1');
end

function p = options_to_portable(opt)
p = struct();
if ~isstruct(opt) || isempty(opt), return; end
names = fieldnames(opt);
for k = 1:numel(names)
    n = names{k}; v = opt.(n);
    p.(n) = value_to_portable(v);
end
end

function opt = portable_to_options(p)
opt = struct();
if ~isstruct(p) || isempty(p), return; end
names = fieldnames(p);
for k = 1:numel(names)
    n = names{k};
    opt.(n) = portable_to_value(p.(n));
end
end

function p = events_to_portable(ev)
if ~isstruct(ev) || isempty(ev)
    p = struct();
    return;
end
p = options_to_portable(ev);
end

function ev = portable_to_events(p)
if ~isstruct(p) || isempty(p) || isempty(fieldnames(p))
    ev = [];
    return;
end
ev = portable_to_options(p);
end

function pv = value_to_portable(v)
% Convert a value to a JSON-portable form. Function handles and non-numeric
% types are dropped (they are not part of the config contract).
if isnumeric(v) && isscalar(v)
    if isreal(v)
        pv = struct('kind', 'scalar_real', 'value', v);
    else
        pv = struct('kind', 'scalar_complex', 'real', real(v), 'imag', imag(v));
    end
elseif islogical(v) && isscalar(v)
    pv = struct('kind', 'logical', 'value', v);
elseif ischar(v) || (isstring(v) && isscalar(v))
    pv = struct('kind', 'char', 'value', char(v));
elseif isnumeric(v) && isvector(v) && isreal(v)
    pv = struct('kind', 'vector_real', 'value', v(:).');
elseif isempty(v)
    pv = struct('kind', 'empty');
else
    pv = struct('kind', 'dropped');
end
end

function v = portable_to_value(p)
switch p.kind
    case 'scalar_real', v = p.value;
    case 'scalar_complex', v = complex(p.real, p.imag);
    case 'logical', v = logical(p.value);
    case 'char', v = char(p.value);
    case 'vector_real', v = p.value;
    case 'empty', v = [];
    otherwise, v = [];
end
end
