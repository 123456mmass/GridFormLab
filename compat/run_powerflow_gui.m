function app = run_powerflow_gui()
%DEPRECATED (Phase C): superseded by the Studio GUI (studio.launch).
%   Header banner only; behavior unchanged.
pf_init_paths();
app = pfapp.run_powerflow_gui();
end
