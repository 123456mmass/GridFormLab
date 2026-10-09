function rows = ne39_scenario_catalog()
%NE39_SCENARIO_CATALOG เหตุการณ์ PROJECT_DERIVED ที่ freeze ก่อนดูผลทดลอง.
% เวลาเทียบ IEEE14 chronology; fault shunt ที่ bus16 ไม่ใช่ mid-line fault.
base=struct('enabled',true,'sg_id','SG31','automatic_gfm_switching',true);
rows=struct('id',{},'events',{},'horizon_s',{},'defining_event',{},'scope',{});
e=struct('enabled',false,'automatic_gfm_switching',false);
rows(end+1)=row('no_event',e,5,'','STATIONARY_DIAGNOSTIC_NO_SWITCHING');
e=struct('enabled',true,'event_profile','fault_only','fault_bus',16, ...
    'Zf',1i*.1,'fault_on',.5,'fault_clear',.7,'automatic_gfm_switching',false);
rows(end+1)=row('fault_bus16',e,5,'fault_clear','FAULT_ONLY_NO_SWITCHING');
e=struct('enabled',true,'event_profile','load_only','load_step',.5, ...
    'load_step_factor',.2,'automatic_gfm_switching',false);
rows(end+1)=row('load_step20',e,5,'load_step','LOAD_ONLY_NO_SWITCHING');
e=struct('enabled',true,'event_profile','line_cycle','line_trip',.5, ...
    'restore_time',2,'line_from_bus',16,'line_to_bus',17, ...
    'automatic_gfm_switching',false);
rows(end+1)=row('line_outage_restore',e,5,'topology_restore','LINE_ONLY_NO_SWITCHING');
e=base; e.event_profile='sg_cycle'; e.sg_trip=20; e.sg_on=100;
rows(end+1)=row('sg_cycle',e,120,'sg_reclose','AUTHENTICATED_SWITCHING_REQUIRED');
e=base; e.event_profile='sg_load_cycle'; e.sg_trip=20; e.load_step=50;
e.load_step_factor=.2; e.sg_on=100;
rows(end+1)=row('sg_load_step20',e,120,'load_step','AUTHENTICATED_SWITCHING_REQUIRED');
e=base; e.event_profile='sg_fault_cycle'; e.sg_trip=20;
e.fault_bus=16; e.Zf=1i*.1; e.fault_on=60; e.fault_clear=60.15; e.sg_on=100;
rows(end+1)=row('sg_fault_bus16',e,120,'fault_clear','AUTHENTICATED_SWITCHING_REQUIRED');
e=base; e.event_profile='line_fault_relay_clear'; e.sg_trip=20;
e.fault_bus=16; e.Zf=1i*.1; e.fault_on=60; e.line_fault_clear=60.15;
e.line_from_bus=16; e.line_to_bus=17; e.sg_on=100;
rows(end+1)=row('line_fault_16_17',e,120,'line_fault_clear', ...
    'CLOSE_IN_LINE_FAULT_NOT_MIDLINE');
e=base; e.event_profile='sg_trip_then_former_outage'; e.sg_trip=20;
e.ibr_trip=50; e.ibr_trip_target='reference_owner'; e.sg_on=100;
rows(end+1)=row('former_outage',e,120,'ibr_trip','REFERENCE_OWNER_RESOLVED_AT_EVENT');
e=base; e.event_profile='chronology'; e.sg_trip=20; e.load_step=50;
e.load_step_factor=.2; e.fault_bus=16; e.Zf=1i*.1;
e.fault_on=85; e.fault_clear=85.15; e.line_trip=110;
e.line_from_bus=16; e.line_to_bus=17; e.restore_time=145; e.sg_on=145;
rows(end+1)=row('chronology',e,160,'topology_restore', ...
    'CHRONOLOGY_SEPARATE_FROM_SUITE');
end

function r=row(id,e,T,defining,scope)
r=struct('id',id,'events',e,'horizon_s',T,'defining_event',defining,'scope',scope);
end
