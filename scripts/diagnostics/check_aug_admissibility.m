function check_aug_admissibility()
%CHECK_AUG_ADMISSIBILITY  Is the displayed augmented trace physically possible?
%
% Read-only.  Rebuilds the bus-9 channels and the declared display
% augmentation with the CURRENT option defaults, then reports, per channel:
%   - the span of the simulation trace;
%   - the span of the augmented display trace;
%   - whether the augmented trace leaves the physically admissible set.
%
% Admissibility here is not a style question.  At bus 9 the load is a constant
% impedance, so P and Q drawn there cannot be negative: a negative value would
% mean the load exporting power.  And the converter-measured frequency of a
% surviving island cannot swing several Hz: the case's own protection envelope
% and every relay setting in it live inside a fraction of a Hz.  A displayed
% trace that crosses those limits is showing a state the model cannot reach.
pf_init_paths();
o = struct('cache_dir',"output/diagnostics/ieee14_gfm_lock_compare_zeta");
[~] = o;

% Rebuild exactly what the generator draws, by calling it with figures off is
% not possible, so mirror its two data steps here.
A = load(fullfile('output','diagnostics','ieee14_gfm_lock_compare_zeta','adaptive_250s.mat'));
F = load(fullfile('output','diagnostics','ieee14_locked_gfl_diag', ...
    'locked_gfl_diag_gauge_thevenin_fine_250s.mat'));
case_data = cases.case_ieee14bus_eecon49_switch();
mpc = case_data.mpc;
sys = ibr.build_ieee14_switch_system(index_mode='agsi_pp', ...
    case_profile='eecon49_figure4',sg_H=2.5,sg_D=1.0,T_d_on=0.10,T_d_off=1.0);
b9 = find(A.result.bus_ids(:)'==9,1);
row9 = find(mpc.bus(:,1)==9,1);
S9pf = (mpc.bus(row9,3)+1i*mpc.bus(row9,4))/mpc.baseMVA;
V9pf = abs(sys.pf.bus_voltage(b9));
y9 = conj(S9pf)/(V9pf^2);
Zf = A.result.sched.Zf;

names = {'adaptive','fixed'}; runs = {A.result,F.result};
% Option values the generator currently uses.
amp   = struct('P',0.20,'Q',0.25,'Vm',0.12,'f',0.60);
gain  = struct('adaptive',0.0,'fixed',1.5);
freqs = [0.3393 0.87 2.10]; wts = [1.00 0.55 0.30]; wts = wts/sum(wts);
mod_depth = 0.15; mod_rate = 0.043;
noise_strength = 0.55; band = [0.05 1.20]; tones = 24;
env = [0 20 0.6; 20 50 1.6; 50 85 1.3; 85 145 1.5; 145 250 0.8];
ramp = 2.0; seed0 = 20260831;

for ii = 1:2
    r = runs{ii}; t = r.t(:);
    V9 = abs(complex(r.y_traj(2*b9-1,:),r.y_traj(2*b9,:))).';
    infl = strcmp(r.topology_history(:),'fault');
    m = 1 + 0.20*(t>=r.sched.load_step);
    S = (V9.^2).*conj(m*y9 + infl*(1/Zf));
    ch = struct('P',real(S),'Q',imag(S),'Vm',V9);
    % converter frequency
    devs = r.equilibrium.devices; nx=[devs.nx]; nu=[devs.nu];
    xo=cumsum([0 nx(1:end-1)]); uo=cumsum([0 nu(1:end-1)]);
    cv = find(r.device_bus_ids(:)' ~= 1);
    fcv = nan(numel(t),numel(cv));
    for j = 1:numel(t)
        ec = r.event_context_history{j};
        for k2 = 1:numel(cv)
            k = cv(k2);
            oo = devs(k).reconstruct(t(j),r.x_traj(xo(k)+(1:nx(k)),j), ...
                r.y_traj(:,j),r.u_history(uo(k)+(1:nu(k)),j),ec);
            if isfield(oo,'gfm'), fcv(j,k2)=60*(1+oo.gfm.omega_m);
            elseif isfield(oo,'gfl'), fcv(j,k2)=60*oo.gfl.omega_PLL_pu; end
        end
    end
    ch.f = fcv;

    isl = t>=20 & t<=145;
    lvl = struct('P',mean(abs(ch.P(isl))),'Q',mean(abs(ch.Q(isl))), ...
                 'Vm',mean(abs(ch.Vm(isl))),'f',1);
    Aenv = env_gain(t,env,ramp);
    rs = RandStream('mt19937ar','Seed',seed0+ii-1);
    fprintf('\n=== %s  (gain %.2f) ===\n',names{ii},gain.(names{ii}));
    for cc = {'P','Q','Vm','f'}
        c = cc{1};
        a = gain.(names{ii})*amp.(c)*lvl.(c);
        Y = ch.(c); N = zeros(size(Y));
        for col = 1:size(Y,2)
            ph = 2*pi*rand(rs,numel(freqs),1);
            fm = 1 + mod_depth*sin(2*pi*mod_rate*t + 2*pi*rand(rs));
            osc = zeros(numel(t),1);
            for k = 1:numel(freqs)
                osc = osc + wts(k)*sin(2*pi*freqs(k)*fm.*t + ph(k));
            end
            tex = bl(rs,t,band(1),band(2),tones);
            n = a*(osc + noise_strength*tex);
            N(:,col) = Aenv.*n; N(:,col) = N(:,col)-mean(N(:,col));
        end
        Yp = Y + N;
        fprintf('  %-3s sim %8.4f .. %8.4f   displayed %8.4f .. %8.4f', ...
            c,min(Y(:)),max(Y(:)),min(Yp(:)),max(Yp(:)));
        switch c
            case {'P','Q'}
                if min(Yp(:)) < 0
                    fprintf('   <-- NEGATIVE: a constant-impedance load cannot export');
                end
            case 'f'
                if min(Yp(:)) < 57 || max(Yp(:)) > 63
                    fprintf('   <-- %.2f Hz swing on a surviving island', ...
                        max(Yp(:))-min(Yp(:)));
                end
        end
        fprintf('\n');
    end
    % Terminal-window check: both arms genuinely converge at t=250.  Does the
    % displayed band still show that?
    if ii == 2
        w = t >= 200;
        fprintf('  terminal window t>=200 s: sim %.4f..%.4f, displayed %.4f..%.4f\n', ...
            min(ch.Vm(w)),max(ch.Vm(w)),NaN,NaN);
    end
end
end

function A = env_gain(t,W,ramp)
t=t(:); A=zeros(numel(t),1); s=zeros(numel(t),1);
for k=1:size(W,1)
    m = ss(t,W(k,1)-ramp,W(k,1)+ramp).*(1-ss(t,W(k,2)-ramp,W(k,2)+ramp));
    A=A+W(k,3)*m; s=s+m;
end
g=s>1e-9; A(g)=A(g)./s(g); A(~g)=1;
end
function s = ss(t,a,b)
if b<=a, s=double(t>=b); return; end
u=min(1,max(0,(t-a)/(b-a))); s=0.5-0.5*cos(pi*u);
end
function c = bl(rs,t,lo,hi,n)
t=t(:); f=lo+(hi-lo)*rand(rs,n,1); p=2*pi*rand(rs,n,1);
c=zeros(numel(t),1);
for k=1:n, c=c+sin(2*pi*f(k)*t+p(k)); end
c=c-mean(c); s=std(c); if s>0, c=c/s; end
end
