function [severity, components] = ne39_weighted_severity(terms, weights, bases)
%NE39_WEIGHTED_SEVERITY PROJECT_DERIVED study design; not a certificate.
arguments
    terms (1,1) struct
    weights (1,4) double
    bases (1,4) double
end
fields={'V_pu','V_ref_pu','f_hz','rocof_hz_s','rocov_pu_s'};
if ~all(isfield(terms,[fields {'f0_Hz'}])) || ...
        ~isnumeric(terms.f0_Hz) || ~isreal(terms.f0_Hz) || ...
        ~isscalar(terms.f0_Hz) || ~isfinite(terms.f0_Hz) || terms.f0_Hz<=0
    error('stability:ne39_weighted_severity:badTerms','Incomplete or invalid signals.');
end
n=numel(terms.V_pu);
for k=1:numel(fields)
    a=terms.(fields{k});
    if ~isnumeric(a) || ~isreal(a) || (~isvector(a) && ~isempty(a)) || ...
            numel(a)~=n || any(~isfinite(a(:)))
        error('stability:ne39_weighted_severity:badTerms','Invalid signal vector.');
    end
end
if ~isreal(weights) || any(~isfinite(weights)) || any(weights<0) || abs(sum(weights)-1)>1e-9
    error('stability:ne39_weighted_severity:badWeights','Weights must be nonnegative and sum to one.');
end
if ~isreal(bases) || any(~isfinite(bases)) || any(bases<=0)
    error('stability:ne39_weighted_severity:badBases','Bases must be positive.');
end
Jv=abs(terms.V_pu(:).'-terms.V_ref_pu(:).')/bases(1);
Jf=abs(terms.f_hz(:).'-terms.f0_Hz)/bases(2);
Jrf=abs(terms.rocof_hz_s(:).')/bases(3);
Jrv=abs(terms.rocov_pu_s(:).')/bases(4);
severity=min(1,max(0,weights(1)*Jv+weights(2)*Jf+weights(3)*Jrf+weights(4)*Jrv));
components=struct('Jv',Jv,'Jf',Jf,'Jrocof',Jrf,'Jrocov',Jrv, ...
    'weights',weights,'bases',bases,'frequency_basis','LOCAL_DEVICE', ...
    'classification','PROJECT_DERIVED_UNVALIDATED');
end
