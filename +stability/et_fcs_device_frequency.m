function out = et_fcs_device_frequency(device, t, x_dev, y, u_dev, ec, case_data)
%ET_FCS_DEVICE_FREQUENCY  Active frequency of ONE device from its own model.
%   OUT = ET_FCS_DEVICE_FREQUENCY(DEVICE,T,X_DEV,Y,U_DEV,EC,CASE_DATA) reads the
%   ACTIVE frequency of a single device from the device's OWN reconstruct(),
%   using the physical frequency variable each mode owns:
%
%     SG  (classical)   omega is the rotor speed in pu (1.0 at nominal), so
%                       f = f_base * omega.  The frequency is the machine's own
%                       swing speed -- NOT a finite difference of any bus angle.
%     GFM (VSG, no PLL) omega is the virtual synchronous speed in pu,
%                       f = f_base * omega.
%     GFL (PLL)         the PLL angle rate IS the frequency: the model publishes
%                       f = omega_PLL/(2*pi) with the controller terms folded in.
%                       A GFL has NO swing-speed state, so its frequency must
%                       come from the PLL, never from a floating rotor angle.
%
%   F_BASE is taken from CASE_DATA.base_values.frequency_Hz (50 or 60).  It is
%   NEVER hard-coded, so a 50 Hz case rates correctly.
%
%   Angle wrap / relative reference DO NOT affect this: frequency is read from a
%   speed/PLL state, not from a wrapped angle difference, so a reference-phase
%   jump moves no reported frequency.
%
%   OUT fields:
%     f_hz      active frequency [Hz]  (NaN when offline/tripped/unavailable)
%     f_pu      f_hz/f_base
%     omega     speed or PLL omega used
%     mode      the device's ACTIVE mode string (as reported by reconstruct)
%     online    logical
%     source    'sg_omega' | 'gfm_omega' | 'gfl_pll' | 'offline' | 'unavailable'
%     fdot_hz_s optional active-RHS frequency derivative when the device exposes
%                a speed state (SG/GFM); NaN otherwise (GFL uses a causal
%                derivative downstream, since the PLL has no speed state).
%
%   Classification PROJECT_DERIVED numerical accessor.  No model is changed.

arguments
    device struct
    t (1,1) double
    x_dev (:,1) double
    y (:,1) double
    u_dev (:,1) double
    ec
    case_data struct
end

fbase = resolve_fbase(case_data);

rec = device.reconstruct(t, x_dev, y, u_dev, ec);
mode = '';
if isfield(rec,'mode') && ~isempty(rec.mode), mode = char(rec.mode); end
online = true;
if isfield(rec,'online') && ~isempty(rec.online), online = logical(rec.online); end

out = struct('f_hz',NaN,'f_pu',NaN,'omega',NaN,'mode',mode,'online',online, ...
    'source','unavailable','fdot_hz_s',NaN);

if ~online || strcmpi(mode,'tripped')
    out.source = 'offline';
    return;
end

typ = '';
if isfield(device,'device_type') && ~isempty(device.device_type)
    typ = char(device.device_type);
end

if strcmpi(mode,'sg') || strcmpi(mode,'synchronous') || ...
        any(strcmpi(typ,{'sg_classical','sg_emf6_composite'}))
    % Speed-state machine. Classical/EMF6 both publish an omega speed state.
    if isfield(rec,'omega') && isscalar(rec.omega) && isfinite(rec.omega)
        omega = rec.omega;
        % Classical adapter: omega is pu speed (1.0 nominal).  The EMF6 composite
        % publishes the same pu-speed convention in out.omega for this engine.
        out.omega = omega;
        out.f_pu = omega;
        out.f_hz = fbase * omega;
        out.source = 'sg_omega';
    end
elseif isfield(rec,'gfm') && isstruct(rec.gfm) && ...
        isfield(rec.gfm,'omega') && isscalar(rec.gfm.omega) && isfinite(rec.gfm.omega)
    omega = rec.gfm.omega;
    out.omega = omega; out.f_pu = omega; out.f_hz = fbase * omega;
    out.source = 'gfm_omega';
elseif isfield(rec,'gfl') && isstruct(rec.gfl)
    if isfield(rec.gfl,'f_hz') && isscalar(rec.gfl.f_hz) && isfinite(rec.gfl.f_hz)
        out.f_hz = rec.gfl.f_hz;
    elseif isfield(rec.gfl,'omega_PLL') && isscalar(rec.gfl.omega_PLL)
        out.f_hz = rec.gfl.omega_PLL/(2*pi);
    end
    if isfield(rec.gfl,'omega_PLL') && isscalar(rec.gfl.omega_PLL)
        out.omega = rec.gfl.omega_PLL;
    end
    if isfinite(out.f_hz), out.f_pu = out.f_hz/fbase; out.source = 'gfl_pll'; end
end

% Active-RHS frequency derivative, when a swing speed state is present: the
% derivative of the machine/VSG speed is the device's own f() RHS component for
% that state.  This is the ACTIVE RHS, not a finite difference.
dev_f = [];
if isfield(device,'f') && ~isempty(device.f), dev_f = device.f; end
omega_idx = speed_state_index(device, out.source);
if ~isempty(dev_f) && ~isempty(omega_idx)
    try
        fdot = dev_f(t, x_dev, y, u_dev, ec);
        if numel(fdot) >= omega_idx && isfinite(fdot(omega_idx))
            out.fdot_hz_s = fbase * fdot(omega_idx);   % pu/s -> Hz/s
        end
    catch
        % A device that cannot evaluate its own RHS leaves the derivative NaN;
        % the accumulator then falls back to a clearly-defined causal difference.
    end
end
end

function fbase = resolve_fbase(case_data)
fbase = NaN;
if isfield(case_data,'base_values') && isstruct(case_data.base_values)
    if isfield(case_data.base_values,'frequency_Hz') && ...
            isscalar(case_data.base_values.frequency_Hz) && ...
            isfinite(case_data.base_values.frequency_Hz) && case_data.base_values.frequency_Hz>0
        fbase = double(case_data.base_values.frequency_Hz);
    end
end
if ~isfinite(fbase)
    error('stability:et_fcs_device_frequency:missingBase', ...
        'case_data.base_values.frequency_Hz must be a positive finite scalar.');
end
end

function idx = speed_state_index(device, source)
% Index of the frequency (speed) STATE in the device RHS, when this device has
% one.  SG classical: [delta; omega] -> 2.  Anything else (GFM VSG layout) is
% resolved from the device's declared state names when present.
idx = [];
switch source
    case 'sg_omega'
        idx = 2;                       % [delta, omega]
    case 'gfm_omega'
        if isfield(device,'state_names')
            k = find(strcmpi(string(device.state_names),'omega') | ...
                     strcmpi(string(device.state_names),'omega_VSM') | ...
                     strcmpi(string(device.state_names),'gfm_omega_VSG'),1,'first');
            if ~isempty(k), idx = k; end
        end
end
end
