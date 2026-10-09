function w=sg_speed_deviation(dev,rec)
%SG_SPEED_DEVIATION แปลงความเร็ว SG เป็น deviation pu เพื่อเทียบ GFM omega_m.
% Classical ใช้ absolute pu (nominal1); EMF6 ใช้ deviation pu (nominal0).
arguments
    dev (1,1) struct
    rec (1,1) struct
end
if ~isfield(rec,'omega') || ~isscalar(rec.omega) || ...
        ~isreal(rec.omega) || ~isfinite(rec.omega)
    error('stability:sg_speed_deviation:missingSpeed','SG ต้องเผยแพร่ omega finite real scalar');
end
switch dev.device_type
    case 'sg_classical'
        w=rec.omega-1;
    case 'sg_emf6_composite'
        w=rec.omega;
    otherwise
        error('stability:sg_speed_deviation:unsupportedModel','ไม่ทราบฐานความเร็วของ SG model');
end
end
