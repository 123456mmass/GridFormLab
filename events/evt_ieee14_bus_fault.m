function ev = evt_ieee14_bus_fault()
%EVT_IEEE14_BUS_FAULT  Three-phase bus fault on the IEEE 14-bus case.
%   EDIT THE FOUR MARKED VALUES. Everything else has a derived default.
%
%   The clearing instant is NOT stored: fault_clear is always derived as
%   t_fault + ds, so changing ds alone changes the disturbance length.
ev = events.schema();
% ---- THE FOUR VALUES YOU EDIT --------------------------------------------
ev.fault_bus = 4;       % external bus ID              CASE_DEFINED
ev.ds        = 0.10;    % FAULT DURATION, seconds      CASE_DEFINED
ev.trip      = [];      % trip time, [] = none         CASE_DEFINED
ev.Zf        = 1i*0.1;  % fault impedance, pu          CASE_DEFINED
% ---- advanced (leave [] for the derived default) -------------------------
ev.t_fault   = 1.0;     % fault inception, s           PROJECT_DERIVED
ev.sg_on     = [];      % reclose, [] = none
ev.profile   = 'fault_only';
ev.case_id   = 'ieee14';
ev.notes     = {'Bus 4 is the IEEE 14-bus fault bus this repository already uses', ...
                '(cases.network_case_catalog: ts fault bus 4).'};
end
