function e = ieee14_switch_electrical_signals(r,opts)
%IEEE14_SWITCH_ELECTRICAL_SIGNALS  Eight-panel electrical bundle for one run.
%
%   e = ieee14_switch_electrical_signals(r)
%
% Rebuilds the eight-panel signals from the stored accepted trajectory using each
% device's OWN reconstruct() callback, so the panels are numerically identical to
% the production electrical figure. Nothing is smoothed, filtered, decimated,
% clipped, offset, interpolated or augmented with synthetic noise: every returned
% sample is a raw accepted value.
%
% The reconstruction mirrors generate_switch_new_report_figures.m:351-428, which
% in turn mirrors the production report adapter. Two additions:
%
%   sg_Vbus   the SG terminal voltage magnitude. The existing generators leave
%             panel (g) without an SG trace, but |V| at the SG bus is a directly
%             comparable quantity and belongs there. Panel (h), the network
%             minimum voltage, has no SG counterpart by definition -- it is one
%             system-wide scalar -- so it stays a single trace.
%   truncation-safe indexing, so an arm that ended at its first event still
%             returns a well-formed (short) bundle instead of erroring.
%
% Cost note: this calls reconstruct() once per device per accepted sample. On the
% 250 s adaptive arm that is roughly 34,000 callback invocations and takes
% minutes. The decision bundle needs none of them, which is why the two figure
% pages are separate generators.
%
% Classification: presentation only, over raw accepted samples.

arguments
    r struct
    opts.f0_Hz (1,1) double = 60
end

req = {'t','x_traj','y_traj','u_history','device_currents','device_P_pu', ...
    'device_Q_pu','device_ids','device_bus_ids','bus_ids', ...
    'device_modes_history','event_context_history','equilibrium'};
for k = 1:numel(req)
    if ~isfield(r,req{k})
        error('ieee14_switch_electrical_signals:missingField', ...
            'The result lacks r.%s.',req{k});
    end
end

t  = r.t(:);
nt = numel(t);
devs = r.equilibrium.devices;
xoff = [0 cumsum([devs.nx])];
uoff = [0 cumsum([devs.nu])];

% IBR devices, identified the way the engine itself does it: by the resource
% type its capabilities declare, never by an ID-string prefix.
didx = [];
for k = 1:numel(devs)
    if is_ibr(devs(k)), didx(end+1) = k; end %#ok<AGROW>
end
if isempty(didx)
    error('ieee14_switch_electrical_signals:noIbrDevices', ...
        'No device declares capabilities.resource_type == "ibr".');
end
nibr = numel(didx);

V = complex(r.y_traj(1:2:end,1:nt),r.y_traj(2:2:end,1:nt));
buspos = zeros(1,nibr);
for j = 1:nibr
    b = find(r.bus_ids == devs(didx(j)).bus_id,1);
    if isempty(b)
        error('ieee14_switch_electrical_signals:busNotFound', ...
            'Device bus %g is not in r.bus_ids.',devs(didx(j)).bus_id);
    end
    buspos(j) = b;
end
Vibr   = V(buspos,:).';
busang = unwrap(angle(Vibr),[],1);

angle_ibr = busang;
f_ibr     = repmat(opts.f0_Hz,nt,nibr);
for j = 1:nibr
    dv = devs(didx(j));
    xr = r.x_traj(xoff(didx(j))+(1:dv.nx),1:nt).';
    ui = uoff(didx(j))+(1:dv.nu);
    for k = 1:nt
        rec = dv.reconstruct(t(k),xr(k,:).',r.y_traj(:,k), ...
            r.u_history(ui,k),r.event_context_history{k});
        if isfield(rec,'gfm')
            angle_ibr(k,j) = rec.gfm.delta_VSM;
            f_ibr(k,j)     = opts.f0_Hz*(1+rec.gfm.omega_m);
        elseif isfield(rec,'gfl')
            angle_ibr(k,j) = rec.gfl.delta_PLL;
            f_ibr(k,j)     = rec.gfl.f_hz;
        end
    end
end

Iibr = r.device_currents(didx,1:nt).';
Idq  = Iibr.*exp(-1i*angle_ibr);

% --- synchronous machine (device row 1) -----------------------------------
sg = devs(1);
sg_delta = r.x_traj(1,1:nt).';
sg_omega = r.x_traj(2,1:nt).';
sg_id = zeros(nt,1); sg_iq = zeros(nt,1);
for k = 1:nt
    rec = sg.reconstruct(t(k),r.x_traj(1:sg.nx,k),r.y_traj(:,k), ...
        r.u_history(uoff(1)+(1:sg.nu),k),r.event_context_history{k});
    sg_id(k) = rec.Id; sg_iq(k) = rec.Iq;
end
sgbp = find(r.bus_ids == r.device_bus_ids(1),1);

e = struct();
e.t = t;
e.device_ids = cellstr(string(r.device_ids(didx)));
e.device_bus_ids = r.device_bus_ids(didx);
e.device_result_rows = didx;
e.sg_id_label = char(string(r.device_ids{1}));
e.sg_bus = r.device_bus_ids(1);
e.f0_Hz = opts.f0_Hz;

e.P = r.device_P_pu(didx,1:nt).';
e.Q = r.device_Q_pu(didx,1:nt).';
e.id = real(Idq);
e.iq = imag(Idq);
e.f = f_ibr;
e.ang = wrap_pi(angle_ibr - busang);      % device-to-PCC, wrapped to (-pi,pi]
e.Vbus = abs(Vibr);
e.Vmin = min(abs(V),[],1).';
e.modes = string(r.device_modes_history(didx,1:nt)).';

e.sg_P = r.device_P_pu(1,1:nt).';
e.sg_Q = r.device_Q_pu(1,1:nt).';
e.sg_id_axis = sg_id;
e.sg_iq_axis = sg_iq;
e.sg_f = opts.f0_Hz*(1+sg_omega);
e.sg_ang = wrap_pi(sg_delta - unwrap(angle(V(sgbp,:))).');
e.sg_Vbus = abs(V(sgbp,:)).';

e.panels = panel_spec();
e.provenance = struct( ...
    'source','raw accepted samples via each device reconstruct() callback', ...
    'mirrors','generate_switch_new_report_figures.m:351-428', ...
    'presentation_noise',struct('kind','none','seed_base',NaN, ...
        'affects_solver_or_switching',false), ...
    'additions','sg_Vbus for panel (g); truncation-safe sample indexing', ...
    'classification','PRESENTATION_ONLY');
end

% ==========================================================================
function P = panel_spec()
%PANEL_SPEC  The eight panels, their labels, and whether an SG trace applies.
%   Panel (h) has sg_field '' because the network minimum voltage is one
%   system-wide scalar with no per-machine counterpart -- not an omission.
P = struct( ...
  'tag',   {'(a)','(b)','(c)','(d)','(e)','(f)','(g)','(h)'}, ...
  'title', {'Active power','Reactive power','d-axis current','q-axis current', ...
            'PCC / virtual-rotor frequency','device-to-PCC angle', ...
            'PCC voltage','Network minimum voltage'}, ...
  ...  Labels are written for MATLAB's tex interpreter, NOT its latex one:
  ...  the latex interpreter ignores FontName and always typesets in Computer
  ...  Modern, which does not match the report body (AGENTS.md:19-22).
  'ylabel',{'{\itP_i} [pu]','{\itQ_i} [pu]','{\iti_{d,i}} [pu]','{\iti_{q,i}} [pu]', ...
            '{\itf_i} [Hz]','\theta_i [deg]','|{\itV_i}| [pu]','min|{\itV}| [pu]'}, ...
  'field', {'P','Q','id','iq','f','ang','Vbus','Vmin'}, ...
  'sg_field',{'sg_P','sg_Q','sg_id_axis','sg_iq_axis','sg_f','sg_ang', ...
              'sg_Vbus',''}, ...
  'scale', {1,1,1,1,1,180/pi,1,1});
end

% ==========================================================================
function tf = is_ibr(dev)
tf = isfield(dev,'capabilities') && isstruct(dev.capabilities) && ...
    isfield(dev.capabilities,'resource_type') && ...
    strcmpi(char(string(dev.capabilities.resource_type)),'ibr');
end

function w = wrap_pi(a)
w = mod(a+pi,2*pi) - pi;
end
