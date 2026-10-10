function ev = evt_ne39_bus_fault()
%EVT_NE39_BUS_FAULT  Three-phase bus fault on the New England 39-bus case.
%   EDIT THE FOUR MARKED VALUES. Everything else has a derived default.
%
%   The clearing instant is NOT stored: fault_clear is always derived as
%   t_fault + ds, so changing ds alone changes the disturbance length.
ev = events.schema();
% ---- THE FOUR VALUES YOU EDIT --------------------------------------------
ev.fault_bus = 16;      % external bus ID              CASE_DEFINED
ev.ds        = 0.10;    % FAULT DURATION, seconds      CASE_DEFINED
ev.trip      = [];      % trip time, [] = none         CASE_DEFINED
ev.Zf        = 1i*0.1;  % fault impedance, pu          CASE_DEFINED
% ---- advanced (leave [] for the derived default) -------------------------
ev.t_fault   = 1.0;     % fault inception, s           PROJECT_DERIVED
ev.sg_on     = [];      % reclose, [] = none
ev.profile   = 'fault_only';
ev.case_id   = 'ne39';
ev.notes     = {'Bus 16 is a 345 kV load bus with no local generation.', ...
                'Reference: cases.case_ne39 / cases.network_case_catalog (ts fault bus 16).'};
end
