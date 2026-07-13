function dev = synthetic_ibr_equilibrium(device_id, bus_id, mode, dispatch_MW, ...
    V_ref_pu, Re_pu, XL_pu)
%SYNTHETIC_IBR_EQUILIBRIUM  Test-only synthetic IBR stub for Phase 4 equilibrium.
%   dev = synthetic_ibr_equilibrium(device_id, bus_id, mode, dispatch_MW,
%       V_ref_pu, Re_pu, XL_pu) returns a device struct satisfying the
%   composite_dae 5-arg ABI. These are NOT production IBR models — they are
%   minimal algebraic current sources sufficient to exercise the equilibrium
%   solver's Newton layer and verify the fixed-gauge approach.
%
%   Modes:
%     'gfl'     -> current-source behind PLL-synchronized angle.
%                  x = [delta_pll]; f = 0 (equilibrium).
%                  Iinj = conj((P + jQ)/V_bus)  (constant PQ injection).
%     'GFM'     -> voltage-source-behind-impedance (REGFM_B1 Eq.13 form).
%                  x = [delta_gfm; E_gfm]; f = 0 (equilibrium).
%                  Iinj = (E_gfm*exp(j*delta_gfm) - V_bus)/(Re + j*XL).
%     'tripped' -> zero injection. x = [delta_frozen]; f = 0; Iinj = 0.
%
%   SOURCE: REGFM_B1 Eq.13 (NREL 90260) for the GFM output stage; standard
%   PQ-injection for GFL. The dynamic equations f=0 are trivial equilibrium
%   stubs (NOT the full REGFM_B1 VSM dynamics — those are Phase 5-6).
%   Labeled ASSUMED_DIAGNOSTIC for the test scaffolding; excluded from
%   production acceptance. Real GFL/VSG models replace these in Phase 5-6.

arguments
    device_id (1,1) string
    bus_id (1,1) double
    mode (1,1) string
    dispatch_MW (1,1) double
    V_ref_pu (1,1) double = 1.0
    Re_pu (1,1) double = 0.0
    XL_pu (1,1) double = 0.1
end

P_pu = dispatch_MW / 100;   % system base 100 MVA
Q_pu = 0.0;                  % unity power factor for the stub

dev = struct();
dev.name = char(device_id);
dev.device_id = char(device_id);
dev.bus_id = bus_id;
dev.device_type = 'ibr_synthetic';

switch mode
case 'gfl'
    dev.nx = 1; dev.nu = 0;
    dev.state_names = {'delta_pll'};
    % x0 initialized later from PF (delta_pll = angle(V_bus)).
    dev.x0 = 0;
    dev.u0 = [];
    dev.f = @(t,x_dev,y,u_dev,event_context) zeros(numel(x_dev),1);
    dev.current_injection = @(t,x_dev,y,u_dev,event_context) ...
        conj((P_pu + 1i*Q_pu) / (y(1) + 1i*y(2)));
    dev.electrical_power = @(t,x_dev,y,u_dev,event_context) P_pu;
    dev.reconstruct = @(t,x_dev,y,u_dev,event_context) ...
        struct('delta',x_dev(1),'omega',0,'Pe',P_pu,'Vbus',abs(y(1)+1i*y(2)));
case 'GFM'
    dev.nx = 2; dev.nu = 0;
    dev.state_names = {'delta_gfm','E_gfm'};
    % x0 initialized later from PF (delta=angle(V), E from S=V*conj(I)).
    dev.x0 = [0; V_ref_pu];
    dev.u0 = [];
    dev.f = @(t,x_dev,y,u_dev,event_context) zeros(numel(x_dev),1);
    dev.current_injection = @(t,x_dev,y,u_dev,event_context) ...
        (x_dev(2)*exp(1i*x_dev(1)) - (y(1) + 1i*y(2))) / (Re_pu + 1i*XL_pu);
    dev.electrical_power = @(t,x_dev,y,u_dev,event_context) ...
        real((y(1)+1i*y(2)) * conj(dev.current_injection(t,x_dev,y,u_dev,event_context)));
    dev.reconstruct = @(t,x_dev,y,u_dev,event_context) ...
        struct('delta',x_dev(1),'omega',0,'Pe',P_pu, ...
        'Vbus',abs(y(1)+1i*y(2)));
case 'tripped'
    dev.nx = 1; dev.nu = 0;
    dev.state_names = {'delta_frozen'};
    dev.x0 = 0;
    dev.u0 = [];
    dev.f = @(t,x_dev,y,u_dev,event_context) zeros(numel(x_dev),1);
    dev.current_injection = @(t,x_dev,y,u_dev,event_context) 0;
    dev.electrical_power = @(t,x_dev,y,u_dev,event_context) 0;
    dev.reconstruct = @(t,x_dev,y,u_dev,event_context) ...
        struct('delta',x_dev(1),'omega',0,'Pe',0,'Vbus',abs(y(1)+1i*y(2)));
otherwise
    error('synthetic_ibr_equilibrium:badMode', ...
        'Unknown mode "%s" (expected gfl|GFM|tripped).', mode);
end
end
