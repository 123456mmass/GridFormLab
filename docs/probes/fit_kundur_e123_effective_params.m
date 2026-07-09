function fit_kundur_e123_effective_params()
pf_init_paths;
case_data=cases.case_kundur_two_area_classical();
pf=pfsolver.powerflow_newton_raphson(case_data,struct('plot_results',false,'verbose',false,'max_iter',50,'tolerance',1e-8,'enforce_q_limits',false));
baseM=case_data.machines;
ref=[-0.111 3.430 0.032; -0.492 6.820 0.072; -0.506 7.020 0.072];
p0=log([0.4 0.03 0.05 1.0]);
opts=optimset('Display','iter','MaxIter',80,'MaxFunEvals',160,'TolX',1e-3,'TolFun',1e-7);
[pbest,Jbest]=fminsearch(@(p)costfun(p,pf,baseM,ref),p0,opts);
vals=exp(pbest);
fprintf('best J=%g Tpq=%.6f Tppd=%.6f Tppq=%.6f Hscale=%.6f\n',Jbest,vals);
print_modes(vals,pf,baseM,ref);
end
function J=costfun(p,pf,baseM,ref)
vals=exp(p);
if any(~isfinite(vals)) || vals(1)<0.05 || vals(1)>2 || vals(2)<0.002 || vals(2)>0.2 || vals(3)<0.002 || vals(3)>0.2 || vals(4)<0.5 || vals(4)>1.5
    J=1e6; return;
end
try
    met=get_modes(vals,pf,baseM);
    J=0;
    for k=1:3
        scale=[abs(ref(k,1)) ref(k,2) ref(k,3)];
        J=J+sum(((met(k,:)-ref(k,:))./scale).^2);
    end
catch
    J=1e6;
end
end
function met=get_modes(vals,pf,baseM)
M=baseM;
M.time_constants.Tpq0=vals(1); M.time_constants.Tppd0=vals(2); M.time_constants.Tppq0=vals(3);
for kk=1:4; M.units(kk).H=baseM.units(kk).H*vals(4); end
ssa=stability.kundur_ex126_kundur_ssa('pf',pf,'options',struct('load_model','cc_p_cz_q','machine_override',M));
lam=ssa.eigenvalues(:);
osc=lam(abs(imag(lam))>0.1 & real(lam)<0 & imag(lam)>0);
[~,idx]=sort(abs(imag(osc))); osc=osc(idx);
if numel(osc)<3; error('not enough modes'); end
met=zeros(3,3);
for k=1:3
    met(k,:)=[real(osc(k)) imag(osc(k)) -real(osc(k))/abs(osc(k))];
end
end
function print_modes(vals,pf,baseM,ref)
met=get_modes(vals,pf,baseM);
for k=1:3
    fprintf('mode%d %.6f+j%.6f z=%.6f f_err=%.3f%% z_err=%.3f%% re_err=%.3f%%\n', ...
        k,met(k,1),met(k,2),met(k,3),abs(met(k,2)-ref(k,2))/ref(k,2)*100,abs(met(k,3)-ref(k,3))/ref(k,3)*100,abs(met(k,1)-ref(k,1))/abs(ref(k,1))*100);
end
end
