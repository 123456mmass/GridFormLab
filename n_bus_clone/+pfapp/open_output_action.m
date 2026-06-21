function app = open_output_action(app)
%OPEN_OUTPUT_ACTION Log the absolute path to the output directory.
pfapp.append_log(app, fullfile(pwd, 'output'));
end
