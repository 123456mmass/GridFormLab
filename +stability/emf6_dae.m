function dae = emf6_dae(case_data, varargin)
%EMF6_DAE Assemble the operational sixth-order EMF DAE.
% State order: [delta, omega, E'q, E'd, E''q, E''d].

options=struct('load_model','cc_p_cz_q');
if nargin>1 && isstruct(varargin{1})
    names=fieldnames(varargin{1});
    for k=1:numel(names), options.(names{k})=varargin{1}.(names{k}); end
end
emf=stability.synchronous_emf6_ssa(case_data,options);
required={'dae_f','dae_g','electrical_power','units','init','Ynet','pf'};
for k=1:numel(required)
    if ~isfield(emf,required{k}) || isempty(emf.(required{k}))
        error('emf6_dae:noDAE','EMF6 engine did not expose %s.',required{k});
    end
end
dae=struct();
dae.dae_f=emf.dae_f; dae.dae_g=emf.dae_g;
dae.electrical_power=emf.electrical_power; dae.init=emf.init;
dae.Ynet=emf.Ynet; dae.units=emf.units; dae.machine=emf.machine;
dae.M=case_data.machines; dae.base=case_data.base_values;
dae.nb=size(emf.Ynet,1); dae.ng=emf.init.ng;
dae.bus_ids=emf.pf.external_bus_ids(:);
dae.gen_buses=dae.bus_ids(emf.units.bus_idx);
dae.load_model=emf.options.load_model; dae.case_name=case_data.system_name;
dae.model='operational_emf_sixth_order'; dae.state_layout=emf.state_layout;
dae.coefficients=emf.coefficients; dae.newton_residual=emf.newton_residual;
dae.fd_eps=emf.fd_eps; dae.Jxx=emf.Jxx; dae.Jxy=emf.Jxy;
dae.Jyx=emf.Jyx; dae.Jyy=emf.Jyy; dae.pf=emf.pf;
end
