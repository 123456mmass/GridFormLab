function app = open_output_action(app)
%DEPRECATED (Phase C): superseded by the Studio GUI (+studio/launch.m).
%   Header banner only; behavior unchanged.
%OPEN_OUTPUT_ACTION Log the absolute path to the output directory.
pfapp.append_log(app, fullfile(pwd, 'output'));
end
