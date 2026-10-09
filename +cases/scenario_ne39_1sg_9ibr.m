function scenario = scenario_ne39_1sg_9ibr(scenario_opt)
%SCENARIO_NE39_1SG_9IBR profile TAMU NE39 แบบ SG31 และ 9 IBR.
arguments
    scenario_opt struct = struct()
end
scenario = cases.scenario_ne39_tamu_mixed(cases.case_ne39_1sg_9ibr(),scenario_opt);
end
