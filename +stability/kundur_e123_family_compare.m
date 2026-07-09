function report = kundur_e123_family_compare(ssa)
%KUNDUR_E123_FAMILY_COMPARE Compare a full spectrum by physical families.
% Families are fixed from frequency bands, real-root bands, and state
% participation before any one-to-one target assignment is made.  Table
% E12.3 is comparison data only; it never enters the model construction.

if nargin<1 || isempty(ssa)
    ssa = stability.kundur_ex126_book_flux_ssa();
end
ref = stability.kundur_e123_reference();
lam = ssa.eigenvalues(:);
if ~isfield(ssa,'Afull') || ~isfield(ssa,'mode_shapes')
    error('kundur_e123_family_compare:model','Full eigenvectors are required.');
end

% The ranges define physical families, not table-value neighborhoods.
groups = [ ...
    group('zero_jordan',find(abs(lam)<1e-2),find_ref(ref,'zero_jordan'),true); ...
    group('common_rotor',find(abs(imag(lam))<1e-7 & real(lam)>-0.15 & real(lam)<-0.01), ...
        [find_ref(ref,'common_real');find_ref(ref,'common_real_2')],false); ...
    group('interarea',find(abs(imag(lam))>=2.5 & abs(imag(lam))<=4.5),find_ref(ref,'interarea'),false); ...
    group('field',find(abs(imag(lam))<1e-7 & real(lam)>-0.30 & real(lam)<-0.15),find_ref(ref,'field'),false); ...
    group('local_area_1',find(abs(imag(lam))>=6.3 & abs(imag(lam))<6.95),find_ref(ref,'local_area_1'),false); ...
    group('local_area_2',find(abs(imag(lam))>=6.95 & abs(imag(lam))<7.4),find_ref(ref,'local_area_2'),false); ...
    group('q_amortisseur',find(abs(imag(lam))<1e-7 & real(lam)<-1 & real(lam)>-10),find_ref(ref,'q_amortisseur'),false); ...
    group('d_amortisseur_real',find(abs(imag(lam))<1e-7 & real(lam)<-10),find_ref(ref,'d_amortisseur_real'),false); ...
    group('d_amortisseur_pairs',find(abs(imag(lam))>1e-7 & abs(imag(lam))<1 & real(lam)<-10), ...
        [find_ref(ref,'d_amortisseur_pair_1');find_ref(ref,'d_amortisseur_pair_2')],false)];

[W,Dleft] = eig(ssa.Afull.');
left_lam = diag(Dleft);
rows = struct('family',{},'reference',{},'computed',{},'real_error_percent',{}, ...
    'imag_error_percent',{},'frequency_Hz',{},'damping_ratio',{}, ...
    'dominant_states',{},'participation',{},'pass',{},'zero_absolute_distance',{});
for g=1:numel(groups)
    idx = groups(g).indices(:);
    target = groups(g).reference(:);
    if numel(idx)~=numel(target)
        error('kundur_e123_family_compare:count', ...
            'Family %s has %d computed roots; expected %d.', ...
            groups(g).name,numel(idx),numel(target));
    end
    order = best_assignment(lam(idx),target);
    for k=1:numel(target)
        j = idx(order(k)); z = lam(j); zref = target(k);
        [names,participation] = dominant_states(ssa.mode_shapes(:,j),W,left_lam,z,ssa.state_names);
        re_pct = 100*abs(real(z)-real(zref))/max(abs(real(zref)),eps);
        if abs(imag(zref))>1e-12
            im_pct = 100*abs(imag(z)-imag(zref))/abs(imag(zref));
        else
            im_pct = NaN;
        end
        is_zero = groups(g).is_zero;
        if is_zero
            pass = false; % an absolute criterion has not yet been declared.
            zero_distance = abs(z-zref);
        else
            pass = re_pct<=ref.tolerance_component_percent && ...
                (isnan(im_pct) || im_pct<=ref.tolerance_component_percent);
            zero_distance = NaN;
        end
        rows(end+1,1) = struct('family',groups(g).name,'reference',zref, ...
            'computed',z,'real_error_percent',re_pct,'imag_error_percent',im_pct, ...
            'frequency_Hz',abs(imag(z))/(2*pi),'damping_ratio',-real(z)/abs(z), ...
            'dominant_states',{names},'participation',participation, ...
            'pass',pass,'zero_absolute_distance',zero_distance); %#ok<AGROW>
    end
end
v_angle=zeros(size(ssa.Afull,1),1); v_angle(1:6:end)=1;
report = struct('reference',ref,'rows',rows,'rank_A',rank(ssa.Afull,1e-6), ...
    'rank_A2',rank(ssa.Afull*ssa.Afull,1e-6), ...
    'common_angle_residual',norm(ssa.Afull*v_angle), ...
    'all_nonzero_families_pass',all([rows(~strcmp({rows.family},'zero_jordan')).pass]));
end

function s = group(name,indices,reference,is_zero)
s=struct('name',name,'indices',indices,'reference',reference,'is_zero',is_zero);
end

function z = find_ref(ref,name)
i=find(strcmp({ref.families.name},name),1);
if isempty(i); error('kundur_e123_family_compare:reference','Missing %s.',name); end
z=ref.families(i).eigenvalues;
end

function order = best_assignment(computed,target)
n=numel(target); p=perms(1:n); costs=zeros(size(p,1),1);
for r=1:size(p,1)
    c=reshape(computed(p(r,:)),[],1);
    costs(r)=sum(abs(c-target(:)));
end
[~,i]=min(costs); order=p(i,:).';
end

function [names,part] = dominant_states(v,w,left_lam,z,state_names)
[~,iw]=min(abs(left_lam-conj(z)));
den=w(:,iw)'*v;
if abs(den)>eps; w=w(:,iw)/conj(den); else; w=w(:,iw); end
p=abs(v.*conj(w)); p=p/(sum(p)+eps);
[part,ix]=sort(p,'descend'); n=min(4,numel(ix));
part=part(1:n); names=state_names(ix(1:n));
end
