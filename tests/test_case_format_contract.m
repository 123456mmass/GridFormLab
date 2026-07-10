function tests=test_case_format_contract
tests=functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function test_all_network_loaders_use_power_case_v1(testCase)
loaders={ ...
    @cases.case_ieee5bus,@cases.case_ieee14bus,@cases.case_ieee300bus, ...
    @cases.case_matpower_ieee30bus,@cases.case_saadat_example_6_7, ...
    @cases.case_saadat_example_6_8,@cases.case_saadat_ieee30bus, ...
    @cases.case_template_nbus,@cases.case_kundur_two_area_classical, ...
    @cases.kundur_ex126_book_case,@cases.case_matpower6_case9, ...
    @cases.case_matpower6_case14};
for k=1:numel(loaders)
    c=loaders{k}();
    verifyEqual(testCase,c.case_kind,'network');
    verifyEqual(testCase,c.schema_version,'power_case/1.0');
    verifyEqual(testCase,size(c.bus_data,2),12);
    verifyEqual(testCase,size(c.line_data,2),7);
    verifyEqual(testCase,c.mpc.version,'2');
    verifyEqual(testCase,size(c.mpc.bus,2),13);
    verifyEqual(testCase,size(c.mpc.gen,2),21);
    verifyEqual(testCase,size(c.mpc.branch,2),13);
    verifyTrue(testCase,istable(c.tables.bus));
    verifyTrue(testCase,istable(c.tables.branch));
    verifyTrue(testCase,istable(c.tables.matpower_bus));
end
end

function test_bus_type_mapping_is_unambiguous(testCase)
c=cases.kundur_ex126_book_case();
verifyEqual(testCase,c.bus_data(:,2),[1;2;2;2;3;3;3;3;3;3;3]);
verifyEqual(testCase,c.mpc.bus(:,2),[3;2;2;2;1;1;1;1;1;1;1]);
verifyEqual(testCase,string(c.tables.bus.TypeName(1:4)),string({'REF';'PV';'PV';'PV'}));
end

function test_all_study_loaders_use_study_case_v1(testCase)
loaders={ ...
    @cases.case_saadat_opf_example_7_4,@cases.case_saadat_opf_example_7_5, ...
    @cases.case_saadat_opf_example_7_6,@cases.case_kundur_smib_classical, ...
    @cases.case_kundur_smib_detailed,@cases.case_kundur_smib_avr, ...
    @cases.case_kundur_smib_pss,@cases.sauer_pai_ex83_case, ...
    @()cases.synthetic_sauer_pai_case(3),@()cases.ieee_au14g_case(1)};
expected=[repmat(string('economic_dispatch'),3,1); ...
    repmat(string('smib'),4,1);repmat(string('dynamic_benchmark'),3,1)];
for k=1:numel(loaders)
    c=loaders{k}();
    verifyEqual(testCase,string(c.case_kind),expected(k));
    verifyEqual(testCase,c.schema_version,'study_case/1.0');
    verifyTrue(testCase,isfield(c,'system_name'));
    verifyTrue(testCase,isfield(c,'tables'));
    verifyGreaterThan(testCase,numel(fieldnames(c.tables)),0);
    verifyFalse(testCase,isfield(c,'mpc'), ...
        'Non-network studies must not receive a fabricated MATPOWER network.');
end
end
