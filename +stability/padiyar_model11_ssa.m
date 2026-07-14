function result = padiyar_model11_ssa(case_data, options)
%PADIYAR_MODEL11_SSA SSSA for Padiyar model 1.1, manual or AVR excitation.
if nargin<1 || isempty(case_data), case_data=cases.case_padiyar_two_area_4m_avr(); end
if nargin<2 || isempty(options), options=struct(); end
if ~isfield(options,'fd_eps'), options.fd_eps=1e-6; end
dae=stability.padiyar_model11_dae(case_data,options);
model=struct('x0',dae.x0,'y0',dae.y0,'f',dae.dae_f, ...
    'g',@(x,y) dae.dae_g(x,y,dae.Ynet),'fd_eps',options.fd_eps, ...
    'free_y',1:numel(dae.y0),'reduction','none', ...
    'ng',dae.ng,'states_per_machine',dae.ns, ...
    'angle_state_index',1,'speed_state_index',2, ...
    'inertia',dae.units.H,'state_names',{dae.state_names}, ...
    'metadata',struct('engine','stability.multimachine_ssa', ...
        'model','Padiyar model 1.1','excitation',dae.excitation));
result=stability.multimachine_ssa(model);
result.dae=dae; result.pf=dae.pf; result.initial_residual=dae.initial_residual;
result.excitation=dae.excitation; result.reference=case_data.reference;
result.launcher_eigenvalue_display = diagnostic_display_metadata( ...
    result.eigenvalues, case_data.reference);
shift=zeros(size(dae.x0)); shift(1:dae.ns:end)=1;
result.angle_shift_residual=norm(result.Afull*shift,inf);
end

function md = diagnostic_display_metadata(lambda, reference)
%DIAGNOSTIC_DISPLAY_METADATA  Published-row ordering for display only.
% This function runs after multimachine_ssa has produced Afull/eigenvalues.
% It cannot feed the matrix, eigenproblem, root counts, or stability status.
lambda=lambda(:); n=numel(lambda);
md=struct('order',(1:n).','mode_labels',{cell(n,1)}, ...
    'description','computed eigensolver order','diagnostic_only',true);
if ~isstruct(reference) || ~isfield(reference,'table95_eigenvalues')
    return;
end
ref=reference.table95_eigenvalues(:);
if numel(ref)~=n || any(~isfinite(ref)) || any(~isfinite(lambda))
    return;
end
used=false(n,1); order=zeros(n,1);
for k=1:n
    distance=abs(lambda-ref(k));
    distance(used)=inf;
    [~,j]=min(distance);
    order(k)=j;
    used(j)=true;
end
labels=cell(n,1);
if n>=20
    labels(9:10)={'Swing 1'};
    labels(11:12)={'Swing 2'};
    labels(13:14)={'Inter-area'};
    labels(18:19)={'reference/gauge'};
end
md.order=order;
md.mode_labels=labels;
md.description='Padiyar Table 9.5 one-to-one match (diagnostic only)';
end
