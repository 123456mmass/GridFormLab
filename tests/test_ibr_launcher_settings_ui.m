function tests = test_ibr_launcher_settings_ui
%TEST_IBR_LAUNCHER_SETTINGS_UI Static contract for the interactive IBR UI.
% The user-facing oracle is the approved three-column schema. Numerical
% validation remains in the production parser and runtime event validators.
tests = functiontests(localfunctions);
end

function test_three_column_base_matlab_layout(tc)
s = prompt_section();
tc.verifySubstring(s,"'Title','Simulation'");
tc.verifySubstring(s,"'Title','Initial IBR configuration'");
tc.verifySubstring(s,"'Title','Events'");
tc.verifyEqual(count(s,"uipanel('Parent',dlg"),3);
tc.verifySubstring(s,"uicontrol('Parent',panel,'Style','edit'");
tc.verifyEmpty(regexp(s,'\<uifigure\>|\<uigridlayout\>|\<inputdlg\>', ...
    'once'),'The IBR settings section must use base-MATLAB three-column controls.');
end

function test_simulation_fields_include_plot_controls(tc)
s = prompt_section();
tc.verifySubstring(s,"'Simulation end t_end (s)'");
tc.verifySubstring(s,"'Fixed step dt (s)'");
tc.verifySubstring(s,"'Generate/export two plots (true/false)'");
tc.verifySubstring(s,"'Show plot windows (true/false)'");
tc.verifyFalse(contains(s,"voltage_bus_ids"));
tc.verifyEqual(count(s,"sprintf('Fault bus (valid external IDs:"),1, ...
    'Fault bus is the single authoritative bus selector for fault and voltage plot.');
end

function test_initial_configuration_uses_existing_api(tc)
s = prompt_section();
tc.verifySubstring(s,"opt.initial_gfm_count");
tc.verifySubstring(s,"opt.initial_gfl_count");
tc.verifySubstring(s,"opt.initial_gfm_indices");
tc.verifySubstring(s,"opt.initial_reference_resource_index");
tc.verifySubstring(s,"blank=count selector");
end

function test_event_fields_include_reclose_dwell_timeout(tc)
s = prompt_section();
tc.verifySubstring(s,"'fault_on (s)'");
tc.verifySubstring(s,"'fault_clear (s)'");
tc.verifySubstring(s,"'sg_trip (s)'");
tc.verifySubstring(s,"'sg_on / reclose request (s)'");
tc.verifySubstring(s,"delay.dwell_s=dwell_s");
tc.verifySubstring(s,"delay.timeout_s=timeout_s");
tc.verifySubstring(s,"opt.delays_overrides=delay");
end

function test_dialog_validation_is_fail_closed(tc)
s = prompt_section();
tc.verifySubstring(s,"Require 0 < dt <= t_end.");
tc.verifySubstring(s,"Initial GFM+GFL counts must equal");
tc.verifySubstring(s,"Require 0 <= synchronism dwell <= synchronism timeout.");
tc.verifySubstring(s,"Require fault_on < fault_clear <= sg_trip < sg_on <= t_end.");
tc.verifySubstring(s,"Post-trip indices must be unique eligible resources and include the reference.");
end

function test_programmatic_path_remains_noninteractive(tc)
txt = launcher_source();
tc.verifyNotEmpty(regexp(txt, ...
    'if\s+case_selection_interactive\s*\r?\n\s*\[ibr_opt,accepted\]=prompt_ibr_options', ...
    'once'));
tc.verifySubstring(txt,"ibr_opt=merge_options(entry.options,user_opt)");
end

function s = prompt_section()
txt = launcher_source();
i1 = strfind(txt,'function [opt,accepted]=prompt_ibr_options');
i2 = strfind(txt,'function [opt,accepted]=prompt_pf_options');
assert(numel(i1)==1 && numel(i2)==1 && i2>i1, ...
    'test_ibr_launcher_settings_ui:sourceLayout', ...
    'Could not isolate the IBR settings section in solve_case.m.');
s = string(txt(i1:i2-1));
end

function txt = launcher_source()
repo = fileparts(fileparts(mfilename('fullpath')));
txt = fileread(fullfile(repo,'solve_case.m'));
end
