function [x,fval,info] = nonlinear_newton(fun,x0,options)
%NONLINEAR_NEWTON In-house damped Newton solver for small nonlinear systems.
% No Optimization Toolbox dependency. The Jacobian is evaluated by central
% finite differences and each Newton step uses residual-norm backtracking.

if nargin<3 || isempty(options), options=struct(); end
if ~isfield(options,'tolerance'), options.tolerance=1e-11; end
if ~isfield(options,'max_iter'), options.max_iter=80; end
if ~isfield(options,'fd_eps'), options.fd_eps=1e-6; end
if ~isfield(options,'min_step'), options.min_step=2^-16; end

x=x0(:); fval=fun(x); fval=fval(:);
info=struct('converged',false,'iterations',0, ...
    'residual_inf',norm(fval,inf),'step_inf',Inf,'message','');
for it=1:options.max_iter
    nr=norm(fval,inf);
    if nr<=options.tolerance
        info.converged=true; info.iterations=it-1;
        info.residual_inf=nr; info.step_inf=0; info.message='converged';
        return;
    end
    n=numel(x); m=numel(fval); J=zeros(m,n);
    for j=1:n
        h=options.fd_eps*(1+abs(x(j)));
        xp=x; xm=x; xp(j)=xp(j)+h; xm(j)=xm(j)-h;
        J(:,j)=(fun(xp)-fun(xm))/(2*h);
    end
    if m==n && rcond(J)>1e-13
        step=-(J\fval);
    else
        step=-((J.'*J+1e-12*eye(n))\(J.'*fval));
    end
    if any(~isfinite(step))
        info.iterations=it; info.message='nonfinite Newton step'; return;
    end
    alpha=1; accepted=false;
    while alpha>=options.min_step
        trial=x+alpha*step; ft=fun(trial); ft=ft(:);
        if all(isfinite(ft)) && norm(ft,inf)<nr
            x=trial; fval=ft; accepted=true; break;
        end
        alpha=alpha/2;
    end
    info.iterations=it; info.step_inf=norm(alpha*step,inf);
    info.residual_inf=norm(fval,inf);
    if ~accepted
        info.message='line search failed'; return;
    end
end
info.message='maximum iterations reached';
end
