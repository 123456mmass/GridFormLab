function tests = test_composite_schema()
%TEST_COMPOSITE_SCHEMA  B5 composite_dae MATPOWER-mpc-only entry validation.
%   Verifies that composite_dae validates the case_data schema at FUNCTION
%   ENTRY before any PF solver call or field access, and fails closed with
%   composite_dae:unsupportedCaseSchema for non-mpc / malformed-mpc input.
%
%   Source: project B5 design (docs/project/plans/ibr_interface_foundation.md).
%   Uses SYNTHETIC fixtures; no +ibr.

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function dev = trivial_device(bus_id)
% Minimal valid device for composite_dae (1 state, 1 input, bus_id mapped).
% Returns a SCALAR struct (composite_dae expects a struct array, not a cell).
dev = struct( ...
    'name','trivial', 'device_id','g1', 'bus_id',bus_id, ...
    'nx',1, 'nu',1, ...
    'f',@(t,x,y,u,ec) -x, ...
    'current_injection',@(t,x,y,u,ec) complex(0,0), ...
    'electrical_power',@(t,x,y,u,ec) 0, ...
    'x0',0, 'u0',0, ...
    'state_names',{{'delta'}}, ...
    'reconstruct',@(t,x,y,u,ec) struct('delta',x,'omega',0,'Pe',0,'Vbus',abs(y(1))));
end

function d = dev_on(bus_id)
% Helper returning a 1-element struct array for composite_dae.
d = trivial_device(bus_id);
end

function test_non_struct_case_fail_closed(testCase)
% case_data not a struct => fail closed at entry.
testCase.verifyError(@() stability.composite_dae(42, dev_on(1), struct()), ...
    'composite_dae:unsupportedCaseSchema');
end

function test_non_scalar_struct_case_fail_closed(testCase)
% case_data a non-scalar struct array => fail closed at entry.
cd = repmat(struct('foo',1), 2, 1);
testCase.verifyError(@() stability.composite_dae(cd, dev_on(1), struct()), ...
    'composite_dae:unsupportedCaseSchema');
end

function test_missing_mpc_fail_closed(testCase)
% case_data without .mpc => fail closed at entry (no normalize_case fallback).
cd = struct('bus_data', 1, 'line_data', 2);
testCase.verifyError(@() stability.composite_dae(cd, dev_on(1), struct()), ...
    'composite_dae:unsupportedCaseSchema');
end

function test_mpc_missing_field_fail_closed(testCase)
% .mpc missing a required MATPOWER field => fail closed at entry.
cd = struct('mpc', struct('baseMVA',100,'bus',1,'branch',1));
% 'gen' missing
testCase.verifyError(@() stability.composite_dae(cd, dev_on(1), struct()), ...
    'composite_dae:unsupportedCaseSchema');
end

function test_mpc_bad_baseMVA_fail_closed(testCase)
% .mpc.baseMVA non-positive => fail closed at entry.
cd = struct('mpc', struct('baseMVA',0,'bus',1,'gen',1,'branch',1));
testCase.verifyError(@() stability.composite_dae(cd, dev_on(1), struct()), ...
    'composite_dae:unsupportedCaseSchema');
end

function test_mpc_empty_bus_fail_closed(testCase)
% .mpc.bus with zero rows => fail closed at entry.
cd = struct('mpc', struct('baseMVA',100,'bus',zeros(0,13),'gen',zeros(0,21),'branch',zeros(0,17)));
testCase.verifyError(@() stability.composite_dae(cd, dev_on(1), struct()), ...
    'composite_dae:unsupportedCaseSchema');
end

function test_valid_matpower14_runs(testCase)
% A valid MATPOWER-14 case passes entry validation and builds a composite.
% IEEE14 end-to-end integration gate (advisor directive): MATPOWER provides
% network/PF data only; device parameters here are SYNTHETIC test fixtures,
% not sourced SG parameters (ASSUMED_DIAGNOSTIC, excluded from production
% acceptance). This gate verifies the composite builds over a real MATPOWER
% network, not that the device dynamics are correct.
c = cases.case_matpower6_case14();
mpc = c.mpc;
gbus = mpc.gen(1,1);   % first generator bus
dae = stability.composite_dae(c, dev_on(gbus), struct());
testCase.verifyEqual(dae.model, 'composite', 'composite model label.');
testCase.verifyTrue(all(isfinite(dae.x0(:))), 'finite x0.');
testCase.verifyTrue(all(isfinite(dae.y0(:))), 'finite y0 from PF.');
testCase.verifyEqual(size(dae.Ynet,1), size(mpc.bus,1), 'Ybus is nb x nb.');
end
