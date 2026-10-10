function ev = evt_template()
%EVT_TEMPLATE  Copy-me starter for a transient-stability event configuration.
%   HOW TO USE
%     1. Copy this file to evt_<your_case>_<something>.m
%     2. Rename the function above to match the file name exactly.
%     3. Edit the FOUR marked values below. Nothing else needs changing.
%
%   The field list is closed (events.validate rejects an unknown field), the
%   file name must keep its 'evt_' prefix, and the function name must equal
%   the file name -- +events/list.m refuses to list anything that does not
%   resolve inside this folder.
%
%   See events/README.md. The numbers below are placeholders, not physics.
ev = events.schema();
% ---- THE FOUR VALUES YOU EDIT --------------------------------------------
ev.fault_bus = 4;          % external bus ID of the faulted bus
ev.ds        = 0.10;       % FAULT DURATION, seconds   <- single authority
ev.trip      = [];         % machine trip time, [] = none
ev.Zf        = 1i*0.1;     % fault impedance, pu
% ---- which case these numbers belong to ----------------------------------
ev.case_id   = 'ieee14';   % an ID events.validate accepts (e.g. 'ne39')
% ---- advanced (leave as they are for the derived default) ----------------
ev.t_fault   = [];         % fault inception; [] = events.schema default (1.0 s)
ev.sg_on     = [];         % reclose time, [] = none
ev.profile   = 'fault_only';   % which events this profile arms (see +stability/ibr_event_schedule)
ev.notes     = {'TEMPLATE - copy me and change the four values above.'};
end
