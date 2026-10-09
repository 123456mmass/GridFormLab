function case_data = case_ne39_5sg_5ibr()
%CASE_NE39_5SG_5IBR TAMU NE39: SG31/32/35/38/39 และ IBR30/33/34/36/37.
% เครือข่ายและ GENROU parameters มาจาก TAMU; classical reduction
% และ composition เป็น PROJECT_DERIVED ไม่ใช่ GENROU dynamics เต็ม.
case_data = cases.case_ne39_tamu_mixed([31 32 35 38 39]);
end
