function scenario = scenario_ne39_5sg_5ibr(scenario_opt)
%SCENARIO_NE39_5SG_5IBR profile TAMU NE39 แบบ 5 SG และ 5 IBR.
arguments
    scenario_opt struct = struct()
end
scenario = cases.scenario_ne39_tamu_mixed(cases.case_ne39_5sg_5ibr(),scenario_opt);
end
