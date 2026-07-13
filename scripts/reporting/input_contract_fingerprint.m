function fp = input_contract_fingerprint(c, scenario, opt)
%INPUT_CONTRACT_FINGERPRINT  Deterministic summary of a case input contract.
%   FP = input_contract_fingerprint(C, SCENARIO, OPT) returns a struct whose
%   fields are a deterministic summary of the case + scenario + solver options
%   that determine the numerical result. Two runs with the same fingerprint
%   are contract-compatible; a mismatch means a fresh run cannot be compared
%   against a saved artifact without reporting the contract difference.
%
%   Fields (mission manifest requirement):
%     base_MVA, frequency_Hz, n_bus, n_branch, n_gen, gen_buses,
%     H, D, Xdp, load_model, fault_bus, Zf, t_fault, t_clear, t_end,
%     dt, corrector_mode, corrector_iter, stepper,
%     Ybus_nnz, Ybus_norm, Ybus_fingerprint (hash of nonzero pattern).
%
%   The fingerprint is used to label FRESH vs SAVED comparisons: a FRESH Ours
%   run may be plotted against a SAVED reference only when the saved artifact's
%   recorded fingerprint equals the fresh run's fingerprint.

fp = struct();
if nargin < 1 || isempty(c), fp = struct('empty',true); return; end
if nargin < 2 || isempty(scenario), scenario = struct(); end
if nargin < 3 || isempty(opt), opt = struct(); end

% --- System base ---
if isfield(c,'base_values')
    fp.base_MVA = c.base_values.S_base_MVA;
    fp.frequency_Hz = c.base_values.frequency_Hz;
    if isfield(c.base_values,'V_base_kV')
        fp.V_base_kV = c.base_values.V_base_kV;
    end
elseif isfield(c,'mpc') && isfield(c.mpc,'baseMVA')
    fp.base_MVA = c.mpc.baseMVA;
    fp.frequency_Hz = 60;   % MATPOWER default
end

% --- Network dimensions ---
if isfield(c,'mpc')
    fp.n_bus = size(c.mpc.bus,1);
    fp.n_branch = size(c.mpc.branch,1);
    fp.gen_buses = unique(c.mpc.gen(c.mpc.gen(:,8)~=0,1)).';
elseif isfield(c,'bus_data')
    fp.n_bus = size(c.bus_data,1);
    if isfield(c,'line_data'), fp.n_branch = size(c.line_data,1); end
    fp.gen_buses = c.bus_data(c.bus_data(:,2)<=2,1).';
end
fp.n_gen = numel(fp.gen_buses);

% --- Machine parameters (H, D, Xdp) ---
if isfield(c,'machines') && isstruct(c.machines) && isfield(c.machines,'units')
    u = c.machines.units;
    fp.H = arrayfun(@(x)x.H, u);
    fp.D = arrayfun(@(x)x.D, u);
    if isfield(c.machines,'reactances') && isfield(c.machines.reactances,'Xdp')
        fp.Xdp = c.machines.reactances.Xdp;
    end
    if isfield(c.machines,'reactances') && isfield(c.machines.reactances,'Xd')
        fp.Xd = c.machines.reactances.Xd;
    end
end

% --- Load model ---
if isfield(c,'operating_point') && isfield(c.operating_point,'load_model')
    fp.load_model = c.operating_point.load_model;
elseif isfield(opt,'load_model')
    fp.load_model = opt.load_model;
else
    fp.load_model = 'default';
end

% --- Scenario (fault/event contract) ---
fp.fault_bus = [];
fp.Zf = [];
fp.t_fault = [];
fp.t_clear = [];
fp.t_end = [];
fp.dt = [];
if isfield(scenario,'fault_bus'), fp.fault_bus = scenario.fault_bus; end
if isfield(scenario,'Zf'), fp.Zf = scenario.Zf; end
if isfield(scenario,'t_fault'), fp.t_fault = scenario.t_fault; end
if isfield(scenario,'t_clear'), fp.t_clear = scenario.t_clear; end
if isfield(scenario,'t_end'), fp.t_end = scenario.t_end; end
if isfield(scenario,'dt'), fp.dt = scenario.dt; end

% --- Solver options ---
fp.corrector_mode = [];
fp.corrector_iter = [];
fp.stepper = [];
if isfield(opt,'corrector_mode'), fp.corrector_mode = opt.corrector_mode; end
if isfield(opt,'corrector_iter'), fp.corrector_iter = opt.corrector_iter; end
if isfield(opt,'stepper'), fp.stepper = opt.stepper; end

% --- Network matrix summary (computed if Ybus is available) ---
fp.Ybus_nnz = NaN;
fp.Ybus_norm = NaN;
fp.Ybus_fingerprint = '';
try
    Y = compute_ybus_summary(c);
    if ~isempty(Y)
        fp.Ybus_nnz = nnz(Y);
        fp.Ybus_norm = norm(Y, 'fro');
        % Hash the nonzero pattern (row, col indices) for a stable fingerprint.
        [rows, cols] = find(Y);
        pat = [rows, cols];
        fp.Ybus_fingerprint = char(java.security.MessageDigest.getInstance('SHA-256') ...
            .digest(uint8(mat2str(pat(:)'))));
    end
catch
    % Ybus not computable here; leave NaN/empty.
end

% --- Deterministic string hash of the whole struct (for quick comparison) ---
fp.hash = contract_hash(fp);
end

function Y = compute_ybus_summary(c)
Y = [];
if isfield(c,'mpc')
    bus = c.mpc.bus; br = c.mpc.branch; nb = size(bus,1);
    Y = complex(zeros(nb));
    for k = 1:size(br,1)
        if size(br,2) >= 11 && br(k,11)==0, continue; end
        i = find(bus(:,1)==br(k,1),1); j = find(bus(:,1)==br(k,2),1);
        if isempty(i)||isempty(j), continue; end
        r = br(k,3); x = br(k,4); b = 0;
        if size(br,2)>=5, b = br(k,5); end
        tap = 1; shift = 0;
        if size(br,2)>=9 && br(k,9)~=0, tap = br(k,9); end
        if size(br,2)>=10, shift = br(k,10); end
        a = tap*exp(1i*deg2rad(shift)); y = 1/(r+1i*x);
        Y(i,i) = Y(i,i)+y/(a*conj(a))+1i*b/2;
        Y(j,j) = Y(j,j)+y+1i*b/2;
        Y(i,j) = Y(i,j)-y/conj(a);
        Y(j,i) = Y(j,i)-y/a;
    end
    if size(bus,2)>=6
        Y = Y + diag((bus(:,5)+1i*bus(:,6))/c.mpc.baseMVA);
    end
elseif isfield(c,'line_data') && isfield(c,'bus_data')
    bd = c.bus_data; ld = c.line_data; nb = size(bd,1);
    Y = complex(zeros(nb));
    for k = 1:size(ld,1)
        i = find(bd(:,1)==ld(k,1),1); j = find(bd(:,1)==ld(k,2),1);
        if isempty(i)||isempty(j), continue; end
        ys = 1/(ld(k,3)+1i*ld(k,4)); bh = 0;
        if size(ld,2)>=5, bh = ld(k,5); end
        Y(i,i)=Y(i,i)+ys+1i*bh; Y(j,j)=Y(j,j)+ys+1i*bh;
        Y(i,j)=Y(i,j)-ys; Y(j,i)=Y(j,i)-ys;
    end
    for b = 1:nb
        if size(bd,2)>=10, Y(b,b)=Y(b,b)+bd(b,9)+1i*bd(b,10); end
    end
end
end

function h = contract_hash(fp)
% Deterministic hash of the fingerprint struct for quick equality check.
keys = fieldnames(fp);
parts = cell(numel(keys),1);
for i = 1:numel(keys)
    v = fp.(keys{i});
    s = val_to_str(v);
    parts{i} = [keys{i} '=' s];
end
s = strjoin(parts, '|');
try
    md = java.security.MessageDigest.getInstance('SHA-256');
    md.update(uint8(s));
    hb = typecast(md.digest, 'uint8');
    h = char(reshape(dec2hex(hb,2)', 1, []));
catch
    h = s;   % fallback: return the string itself
end
end

function s = val_to_str(v)
% Robust conversion of any value to a single-row string for hashing.
if ischar(v), s = strjoin(cellstr(v'), ''); return; end
if isnumeric(v)
    if isempty(v), s = '[]'; else, s = mat2str(v(:).'); end
    return;
end
if islogical(v), s = mat2str(v(:).'); return; end
if iscell(v)
    s = 'cell{';
    for i = 1:numel(v), s = [s val_to_str(v{i}) ',']; end
    s = [s '}'];
    return;
end
if isstruct(v)
    s = 'struct{';
    fns = fieldnames(v);
    for i = 1:numel(fns)
        s = [s fns{i} ':' val_to_str(v.(fns{i})) ','];
    end
    s = [s '}'];
    return;
end
s = 'other';
end
