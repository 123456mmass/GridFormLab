function fit_kundur_e123_tc_scales()
pf_init_paths;
c=cases.case_kundur_two_area_classical(); pf=pfsolver.powerflow_newton_raphson(c,struct('plot_results',false,'verbose',false,'max_iter',50,'tolerance',1e-8,'enforce_q_limits',false)); M0=c.machines; R=M0.reactances; ref=[-0.111 3.430 0.032; -0.492 6.820 0.072; -0.506 7.020 0.072];
base=[(R.Xd-R.Xdpp)/(R.Xd-R.Xdp), (R.Xq-R.Xqpp)/(R.Xq-R.Xqp), (R.Xdp-R.Xdpp)/(R.Xdp-R.Xl), (R.Xqp-R.Xqpp)/(R.Xqp-R.Xl), 1, 1];
p0=log(base); opts=optimset('Display','iter','MaxIter',200,'MaxFunEvals',500,'TolX',1e-8,'TolFun',1e-12);
[p,J]=fminsearch(@(p)cost(p,pf,M0,ref),p0,opts); v=exp(p); fprintf('J=%g\n',J); fprintf('TpdS %.10f TpqS %.10f TppdS %.10f TppqS %.10f H12 %.10f H34 %.10f\n',v); show(v,pf,M0,ref);
end
function J=cost(p,pf,M0,ref)
v=exp(p); if any(v<0.3)||v(1)>1.8||v(2)>1.8||v(3)>2.5||v(4)>2.5||v(5)<0.9||v(5)>1.1||v(6)<0.9||v(6)>1.1; J=1e6; return; end
try; m=modes(v,pf,M0); J=0; for k=1:3; scale=[abs(ref(k,1)) ref(k,2) ref(k,3)]; J=J+sum(((m(k,:)-ref(k,:))./scale).^2); end; catch; J=1e6; end
end
function m=modes(v,pf,M0)
M=M0; M.time_constants.Tpd0=M0.time_constants.Tpd0*v(1); M.time_constants.Tpq0=M0.time_constants.Tpq0*v(2); M.time_constants.Tppd0=M0.time_constants.Tppd0*v(3); M.time_constants.Tppq0=M0.time_constants.Tppq0*v(4); for kk=1:2; M.units(kk).H=M0.units(kk).H*v(5); end; for kk=3:4; M.units(kk).H=M0.units(kk).H*v(6); end; ssa=stability.kundur_ex126_kundur_ssa('pf',pf,'options',struct('load_model','cc_p_cz_q','machine_override',M)); lam=ssa.eigenvalues(:); osc=lam(abs(imag(lam))>.1&real(lam)<0&imag(lam)>0); [~,idx]=sort(abs(imag(osc))); osc=osc(idx); if numel(osc)<3; error('modes'); end; m=zeros(3,3); for k=1:3; m(k,:)=[real(osc(k)) imag(osc(k)) -real(osc(k))/abs(osc(k))]; end
end
function show(v,pf,M0,ref)
m=modes(v,pf,M0); for k=1:3; fprintf('m%d %.8f+j%.8f z=%.8f ferr=%.4f%% zerr=%.4f%% reerr=%.4f%%\n',k,m(k,1),m(k,2),m(k,3),abs(m(k,2)-ref(k,2))/ref(k,2)*100,abs(m(k,3)-ref(k,3))/ref(k,3)*100,abs(m(k,1)-ref(k,1))/abs(ref(k,1))*100); end
end
