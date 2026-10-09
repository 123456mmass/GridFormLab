function [vdc,idc] = dc_source_equilibrium(p,Pac,Vdefault)
%DC_SOURCE_EQUILIBRIUM high-voltage equilibrium ของ fixed plant ที่ chopper ไม่ทำงาน.
% ผู้เรียกเดิมคง initializer เดิม; fixed plant ต้องแก้ V^2-EV+RP=0 จริง.
vdc=Vdefault; idc=p.Idc0;
if ~isfield(p,'fixed_plant') || ~p.fixed_plant, return; end
if ~isnumeric(Pac) || ~isscalar(Pac) || ~isreal(Pac) || ~isfinite(Pac) || Pac<0
    error('ibr:dc_source_equilibrium:noHighBranch', ...
        'Fixed DC plant requires finite nonnegative converter power.');
end
disc=p.Edc^2-4*p.Rdc*Pac;
if disc<=0
    error('ibr:dc_source_equilibrium:noHighBranch', ...
        'Fixed DC plant has no supported exporting high-voltage equilibrium.');
end
vdc=(p.Edc+sqrt(disc))/2;
if vdc>p.Vdc_max
    error('ibr:dc_source_equilibrium:chopperActive', ...
        'This initializer requires a chopper-inactive equilibrium.');
end
idc=(p.Edc-vdc)/p.Rdc;
end
