function opts = two_ibr_switch_dialog(defaults)
%TWO_IBR_SWITCH_DIALOG  Simple settings dialog for the two-IBR AGSI GFL<->GFM
%   mode-switch study.
%
%   OPTS = ibr.two_ibr_switch_dialog(DEFAULTS) shows an input dialog pre-filled
%   with the scenario DEFAULTS (a struct with the fields below) and returns an
%   OPTS struct whose field names match the ibr.two_ibr_switch_demo Name=Value
%   options. Returns [] if the user presses Cancel.
%
%   Fields (all scalar; Z_line may be complex, e.g. 0.30i):
%     P_ref Q_ref V_inf Z_line AGSI_up AGSI_down event_time recover_time
%     Zline_factor step_dphase_deg step_dV step_ramp T dt
%
%   Used by run_two_ibr_switch when it is called with no arguments.

if nargin < 1 || ~isstruct(defaults)
    defaults = cases.case_ibr_two_ibr_switch().two_ibr_switch;
end

% Ordered field list + human-readable prompts (field names must match the
% ibr.two_ibr_switch_demo Name=Value option names).
spec = {
    'P_ref',            'Per-IBR active power  P_ref (pu)'
    'Q_ref',            'Per-IBR reactive power  Q_ref (pu)'
    'V_inf',            'Infinite-bus voltage  V_inf (pu)'
    'Z_line',           'Line impedance to PCC  Z_line (pu, e.g. 0.30i)'
    'AGSI_up',          'AGSI up-line  Gamma_on  (GFL -> GFM)'
    'AGSI_down',        'AGSI down-line  Gamma_off  (GFM -> GFL)'
    'event_time',       'Weak-grid event start time (s)'
    'recover_time',     'Grid recovery time (s)'
    'Zline_factor',     'Line weakening factor during event (x)'
    'step_dphase_deg',  'Grid phase step at event (deg)'
    'step_dV',          'Grid voltage step at event (pu)'
    'step_ramp',        'Transition ramp duration (s)'
    'T',                'Simulation time  T (s)'
    'dt',               'Time step  dt (s)'
    };

fields  = spec(:,1);
prompts = spec(:,2);
defstr  = cell(numel(fields),1);
for k = 1:numel(fields)
    if isfield(defaults, fields{k}) && ~isempty(defaults.(fields{k}))
        defstr{k} = num_to_str(defaults.(fields{k}));
    else
        defstr{k} = '';
    end
end

answer = inputdlg(prompts, 'Two-IBR GFL<->GFM AGSI switch - settings', 1, defstr);
if isempty(answer)
    opts = [];      % Cancel
    return;
end

opts = struct();
for k = 1:numel(fields)
    opts.(fields{k}) = parse_num(answer{k}, prompts{k});
end

% Light sanity checks (fail closed with a clear dialog, not a stack trace).
if opts.AGSI_down >= opts.AGSI_up
    errordlg('Gamma_off must be less than Gamma_on (hysteresis band).', ...
        'Invalid settings', 'modal');
    opts = [];
    return;
end
if opts.recover_time <= opts.event_time
    errordlg('Recovery time must be greater than the event start time.', ...
        'Invalid settings', 'modal');
    opts = [];
    return;
end
if opts.T <= opts.recover_time
    warndlg('Simulation time T is not much greater than the recovery time; the return-to-GFL switch may be cut off.', ...
        'Short horizon', 'modal');
end
end

% =========================================================================
function v = parse_num(s, label)
% Parse a scalar (real or complex) numeric entry; str2num handles '0.30i'.
v = str2num(strtrim(char(s))); %#ok<ST2NM>
if isempty(v) || ~isscalar(v) || ~all(isfinite(v))
    error('ibr:two_ibr_switch_dialog:badValue', ...
        'Invalid numeric entry for "%s": "%s".', label, char(s));
end
end

% =========================================================================
function s = num_to_str(z)
if ~isreal(z) && imag(z) ~= 0
    s = num2str(z);          % e.g. '0+0.3i'
else
    s = num2str(real(z));
end
end
