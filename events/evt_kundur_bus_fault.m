function ev = evt_kundur_bus_fault()
%EVT_KUNDUR_BUS_FAULT  Three-phase bus fault on Kundur Example 12.6.
%   EDIT THE FOUR MARKED VALUES. Everything else has a derived default.
%
%   The clearing instant is NOT stored: fault_clear is always derived as
%   t_fault + ds, so changing ds alone changes the disturbance length.
ev = events.schema();
% ---- THE FOUR VALUES YOU EDIT --------------------------------------------
ev.fault_bus = 8;       % external bus ID              CASE_DEFINED
ev.ds        = 0.10;    % FAULT DURATION, seconds      CASE_DEFINED
ev.trip      = [];      % trip time, [] = none         CASE_DEFINED
ev.Zf        = 1i*0.1;  % fault impedance, pu          CASE_DEFINED
% ---- advanced (leave [] for the derived default) -------------------------
ev.t_fault   = 1.0;     % fault inception, s           PROJECT_DERIVED
ev.sg_on     = [];      % reclose, [] = none
ev.profile   = 'fault_only';
ev.case_id   = 'kundur';   % cases.network_case_catalog id 'kundur'
ev.notes     = {'Bus 8 is the Kundur Example 12.6 fault bus this repository', ...
                'already uses (cases.network_case_catalog: ts fault bus 8).'};
end
