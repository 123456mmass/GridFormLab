function opts = padiyar_switch_dialog(system)
if nargin < 1 || strlength(string(system)) == 0, system = "padiyar"; end
if strcmpi(system,"ieee14")
    sysname = "IEEE 14-bus 1-SG + 4-IBR";
    fault_hint = 'Fault bus  (2,3,6,8 = IBR; 1 = SG; others = load)';
    fault_default = '5'; valid_buses = 1:14;
else
    sysname = "Padiyar two-area 1-SG + 3-IBR";
    fault_hint = 'Fault bus  (1,2,12 = IBR; 11 = SG; 3,13 = load)';
    fault_default = '3'; valid_buses = [1 2 3 11 12 13];
end
%PADIYAR_SWITCH_DIALOG  Two-step settings dialog for the Padiyar 1-SG + 3-GFL
%   AGSI++ GFL<->GFM mode-switch study.
%     Step 1 (list): choose the disturbance method (fault / load step / SG trip /
%                    combinations, incl. fault or step BEFORE the SG trip).
%     Step 2 (input): set the parameters for that method (index mode; fault ON/
%                     CLEAR times; load-step time; SG trip/reclose times; T; dt).
%   Returns an opts struct (index_mode, sg_trip_time, sg_reclose_time, fault_on,
%   fault_clear, step_on, T, dt) or [] on Cancel. Disabled events are Inf.

% --- Step 1: disturbance method (columns: fault trip reclose step) ---------
methods = { ...
    'SG trip only  (form island, no reclose)'; ...
    'SG trip + reclose  (island, then index-qualified handback)'; ...
    'Fault (3-phase, temporary) THEN SG trip + reclose'; ...
    'Load step THEN SG trip + reclose'; ...
    'Fault only (3-phase, temporary; no SG trip)'; ...
    'Load step only (no SG trip)'};
FL = [ 0 1 0 0 ; 0 1 1 0 ; 1 1 1 0 ; 0 1 1 1 ; 1 0 0 0 ; 0 0 0 1 ];
[sel, ok] = listdlg('PromptString','Select the disturbance method:', ...
    'SelectionMode','single', 'ListString',methods, 'ListSize',[440 150], ...
    'Name',sprintf('%s - disturbance method',sysname), 'InitialValue',2);
if ~ok || isempty(sel), opts = []; return; end
fl = struct('fault',FL(sel,1),'trip',FL(sel,2),'reclose',FL(sel,3),'step',FL(sel,4));

% --- Step 2: parameters (built dynamically for the chosen method) ----------
K = {}; L = {}; D = {};
add('index_mode','Switching index mode  (agsi_pp = AGSI++, or agsi)','agsi_pp');
add('T_d_on','Dwell GFL->GFM (s)  [0 = instant; filters spurious re-switch]','0.5');
add('sg_droop_R','SG governor droop R (pu/pu; Inf = no governor)','0.05');
add('gfm_ilim','Converter current limit (x rated; Inf = no limit)','1.2');
if fl.fault
    add('fault_on','Fault ON time (s)','1.0');
    add('fault_clear','Fault CLEAR time (s)','1.15');
    add('fault_bus',fault_hint,fault_default);
    add('fault_Zf_imag','Fault reactance  Zf = j*(value) pu  (smaller = more severe)','0.5');
end
if fl.step
    add('step_on','Load-step time (s)','1.0');
    add('step_factor','Load-step fraction  (+fraction of the load)','0.10');
end
if fl.trip
    add('sg_trip_time','SG trip time (s)', num2str(2.0*(fl.fault||fl.step) + 1.0*~(fl.fault||fl.step)));
end
if fl.reclose
    add('sg_reclose_time','SG reclose time (s)','5.0');
end
add('T','Simulation time  T (s)','8.0');
add('dt','Time step  dt (s)','0.002');

answer = inputdlg(L, sprintf('%s switch settings  [%s]', sysname, methods{sel}), 1, D);
if isempty(answer), opts = []; return; end

opts = struct('index_mode',"agsi_pp",'excitation',"",'sg_trip_time',Inf,'sg_reclose_time',Inf, ...
    'fault_on',Inf,'fault_clear',Inf,'fault_bus',3,'fault_Zf',0.5i,'step_on',Inf,'step_factor',0.10, ...
    'T_d_on',0.5,'T_d_off',1.0,'sg_droop_R',0.05,'gfm_ilim',1.2, ...
    'T',8.0,'dt',2e-3);
for i = 1:numel(K)
    if strcmp(K{i},'index_mode')
        im = lower(strtrim(char(answer{i})));
        if ~ismember(im,{'agsi','agsi_pp'})
            errordlg('Index mode must be "agsi_pp" or "agsi".','Invalid settings','modal');
            opts = []; return;
        end
        opts.index_mode = string(im);
    elseif strcmp(K{i},'excitation')
        ex = lower(strtrim(char(answer{i})));
        if ~ismember(ex,{'manual','avr'})
            errordlg('Excitation must be "manual" (NO AVR) or "avr".','Invalid settings','modal');
            opts = []; return;
        end
        opts.excitation = string(ex);
    elseif strcmp(K{i},'fault_Zf_imag')
        opts.fault_Zf = 1i*parse_num(answer{i}, L{i});
    else
        opts.(K{i}) = parse_num(answer{i}, L{i});
    end
end

% --- validation ------------------------------------------------------------
if opts.T <= 0, opts = fail('Simulation time T must be positive.'); return; end
if fl.fault && ~(opts.fault_clear > opts.fault_on)
    opts = fail('Fault CLEAR time must be greater than fault ON time.'); return;
end
if fl.fault && ~ismember(opts.fault_bus, valid_buses)
    opts = fail(sprintf('Fault bus must be one of the %s buses [%s].', sysname, num2str(valid_buses))); return;
end
if fl.trip && opts.T <= opts.sg_trip_time
    opts = fail('T must be greater than the SG trip time.'); return;
end
if fl.reclose && opts.sg_reclose_time <= opts.sg_trip_time
    opts = fail('SG reclose time must be greater than the SG trip time.'); return;
end

    function add(k,l,dv), K{end+1}=k; L{end+1}=l; D{end+1}=dv; end
end

% =========================================================================
function v = parse_num(s, label)
v = str2double(strtrim(char(s)));   % accepts 'Inf'
if ~isscalar(v) || isnan(v)
    error('ibr:padiyar_switch_dialog:badValue','Invalid numeric entry for "%s": "%s".',label,char(s));
end
end

function o = fail(msg)
errordlg(msg,'Invalid settings','modal'); o = [];
end
