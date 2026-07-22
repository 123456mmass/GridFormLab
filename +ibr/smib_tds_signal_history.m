function signals = smib_tds_signal_history(dev,X,Y,u,ec)
%SMIB_TDS_SIGNAL_HISTORY Reconstruct dq current and P/Q along a SMIB TDS run.
%   GFL-RMS10 exposes native inverter-base i_d/i_q states. GFM-noPLL has no
%   current state, so its dq current is a reporting-only transformation of
%   I_inv into the virtual-rotor frame. P and Q always use the generator
%   injection convention S = V*conj(I_sys) on the system base.
arguments
    dev (1,1) struct
    X double
    Y double
    u (:,1) double
    ec (1,1) struct = struct()
end
if ~isfield(dev,'reconstruct') || ~isa(dev.reconstruct,'function_handle') || ...
        size(X,1) ~= dev.nx || size(Y,1) < 2 || size(X,2) ~= size(Y,2)
    error('ibr:smib_tds_signal_history:deviceContract', ...
        'Device reconstruction and trajectory dimensions are inconsistent.');
end
n = size(X,2);
signals = struct('i_d_pu_inverter',NaN(n,1), ...
    'i_q_pu_inverter',NaN(n,1),'P_pu_system',NaN(n,1), ...
    'Q_pu_system',NaN(n,1),'P_MW',NaN(n,1),'Q_MVAr',NaN(n,1), ...
    'f_hz',NaN(n,1),'f_source','', ...
    'power_identity_error',NaN(n,1),'current_source','', ...
    'current_frame','DEVICE_SYNCHRONOUS_DQ', ...
    'power_convention','GENERATOR_INJECTION_S_EQUALS_V_CONJ_I', ...
    'classification','TDS_RECONSTRUCTION_DIAGNOSTIC');
tol = 1e-10; % NUMERICAL_METHOD reporting consistency gate
for k = 1:n
    rec = dev.reconstruct(0,X(:,k),Y(:,k),u,ec);
    if isfield(rec,'i_d') && isfield(rec,'i_q')
        i_d = rec.i_d;
        i_q = rec.i_q;
        % Native current states. Label by device family so a GFM with a
        % genuine inner-current-loop state (e.g. gfm_vsm_sakimoto) is not
        % mislabelled as GFL. GFL-RMS10 keeps its established label.
        if isfield(dev,'device_type') && contains(lower(char(dev.device_type)),'gfl')
            source = 'NATIVE_GFL_CURRENT_STATES';
        else
            source = 'NATIVE_GFM_CURRENT_STATES';
        end
    elseif isfield(rec,'I_inv') && isfield(rec,'delta_vsm')
        I_dq_inv = rec.I_inv*exp(-1i*rec.delta_vsm);
        i_d = real(I_dq_inv);
        i_q = imag(I_dq_inv);
        source = 'PROJECT_DERIVED_DIAGNOSTIC_VSM_FRAME_TRANSFORM';
    else
        error('ibr:smib_tds_signal_history:missingDqCurrent', ...
            'Device does not expose native or reconstructable dq current.');
    end
    if isfield(rec,'I_sys')
        I_sys = rec.I_sys;
    elseif isfield(rec,'I_gfl')
        I_sys = rec.I_gfl;
    else
        error('ibr:smib_tds_signal_history:missingSystemCurrent', ...
            'Device reconstruction does not expose system-base current.');
    end
    V = complex(Y(1,k),Y(2,k));
    S = V*conj(I_sys);
    if ~isfield(rec,'Pe') || ~isfield(rec,'Qe')
        error('ibr:smib_tds_signal_history:missingPower', ...
            'Device reconstruction does not expose Pe and Qe.');
    end
    identity_error = abs(complex(rec.Pe,rec.Qe)-S);
    if any(~isfinite([i_d i_q real(S) imag(S) identity_error])) || ...
            identity_error > tol
        error('ibr:smib_tds_signal_history:powerIdentityMismatch', ...
            'TDS sample %d violates S=V*conj(I) (error %.3e, tol %.3e).', ...
            k,identity_error,tol);
    end
    Sbase = rec.Sbase;
    signals.i_d_pu_inverter(k) = i_d;
    signals.i_q_pu_inverter(k) = i_q;
    signals.P_pu_system(k) = real(S);
    signals.Q_pu_system(k) = imag(S);
    signals.P_MW(k) = real(S)*Sbase;
    signals.Q_MVAr(k) = imag(S)*Sbase;
    signals.power_identity_error(k) = identity_error;
    signals.current_source = source;
    if isfield(rec,'f_hz') && isfinite(rec.f_hz)
        signals.f_hz(k) = rec.f_hz;
        if isfield(dev,'device_type') && contains(lower(char(dev.device_type)),'gfl')
            signals.f_source = 'PLL_ESTIMATED_FREQUENCY';
        else
            signals.f_source = 'VSG_VIRTUAL_ROTOR_FREQUENCY';
        end
    end
end
signals.power_identity_tolerance = tol;
end
