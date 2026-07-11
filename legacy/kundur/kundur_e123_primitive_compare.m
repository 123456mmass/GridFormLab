function report = kundur_e123_primitive_compare(ssa)
%KUNDUR_E123_PRIMITIVE_COMPARE Diagnose the primitive-flux spectrum.
%   Reference values are used only after model assembly and eigensolution.

if nargin<1 || isempty(ssa)
    ssa=stability.multicase_sssa(cases.kundur_ex126_book_case());
end
ref=stability.kundur_e123_reference(); lam=ssa.eigenvalues(:);
groups={ ...
    'zero_jordan',find(abs(lam)<1e-2),find_ref(ref,'zero_jordan'),true; ...
    'common_rotor',find(abs(imag(lam))<1e-6 & real(lam)>-0.15 & real(lam)<-0.01), ...
        [find_ref(ref,'common_real');find_ref(ref,'common_real_2')],false; ...
    'interarea',find(abs(imag(lam))>=2.5 & abs(imag(lam))<=4.5),find_ref(ref,'interarea'),false; ...
    'field',find(abs(imag(lam))<1e-6 & real(lam)>-0.30 & real(lam)<-0.15),find_ref(ref,'field'),false; ...
    'local_area_1',find(abs(imag(lam))>6.3 & abs(imag(lam))<6.9),find_ref(ref,'local_area_1'),false; ...
    'local_area_2',find(abs(imag(lam))>=6.9 & abs(imag(lam))<7.4),find_ref(ref,'local_area_2'),false; ...
    'q_amortisseur',find(abs(imag(lam))<1e-6 & real(lam)<-1 & real(lam)>-10),find_ref(ref,'q_amortisseur'),false; ...
    'd_amortisseur',find(real(lam)<-10), ...
        [find_ref(ref,'d_amortisseur_real');find_ref(ref,'d_amortisseur_pair_1');find_ref(ref,'d_amortisseur_pair_2')],false};
rows=struct('family',{},'reference',{},'computed',{},'real_error_percent',{}, ...
    'imag_error_percent',{},'pass',{},'zero_absolute_distance',{});
for g=1:size(groups,1)
    idx=groups{g,2}(:); target=groups{g,3}(:);
    if numel(idx)~=numel(target)
        error('kundur_e123_primitive_compare:count', ...
            'Family %s has %d roots; expected %d.',groups{g,1},numel(idx),numel(target));
    end
    order=best_assignment(lam(idx),target);
    for k=1:numel(target)
        z=lam(idx(order(k))); zr=target(k);
        re=100*abs(real(z)-real(zr))/max(abs(real(zr)),eps);
        if abs(imag(zr))>1e-12, im=100*abs(imag(z)-imag(zr))/abs(imag(zr));
        else, im=NaN; end
        iszero=groups{g,4}; pass=~iszero && re<=ref.tolerance_component_percent && ...
            (isnan(im)||im<=ref.tolerance_component_percent);
        rows(end+1,1)=struct('family',groups{g,1},'reference',zr,'computed',z, ...
            'real_error_percent',re,'imag_error_percent',im,'pass',pass, ...
            'zero_absolute_distance',ternary(iszero,abs(z-zr),NaN)); %#ok<AGROW>
    end
end
nonzero=~strcmp({rows.family},'zero_jordan');
report=struct('rows',rows,'all_nonzero_families_pass',all([rows(nonzero).pass]), ...
    'passing_nonzero_roots',sum([rows(nonzero).pass]), ...
    'nonzero_root_count',sum(nonzero),'model','primitive rotor flux linkage');
end

function z=find_ref(ref,name)
i=find(strcmp({ref.families.name},name),1); z=ref.families(i).eigenvalues;
end

function order=best_assignment(computed,target)
n=numel(target); p=perms(1:n); cost=zeros(size(p,1),1);
for r=1:size(p,1)
    candidate=reshape(computed(p(r,:)),[],1);
    cost(r)=sum(abs(candidate-target(:)));
end
[~,i]=min(cost); order=p(i,:).';
end

function value=ternary(condition,a,b)
if condition, value=a; else, value=b; end
end
