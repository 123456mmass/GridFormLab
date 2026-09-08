function verify_mode_switch_proof
% Reproducible local checks for the bilingual mode-switch proof.
% Calls production callbacks; does not change production code or study data.
outdir=fileparts(mfilename('fullpath'));
repo=fileparts(fileparts(fileparts(fileparts(outdir))));
addpath(repo); pf_init_paths();
rng(20260905,'twister');
V=1.02*exp(1i*0.08); y=[real(V);imag(V)];
p=struct('Sbase',100,'Mbase',100,'fbase',60, ...
    'dc_source',struct('Tdc',0.10,'source_state',true));
d=ibr.eecon49_dual_mode_model('IBR_TEST',2,1,2,V,p,0.45,0.08,abs(V),'gfl');
a=context('gfl'); b=context('GFM');
x=d.x0; x(1)=x(1)+0.07; x(2)=x(2)-0.03;
x(3)=1.03; x(4)=x(4)+0.12; x(5)=0.3; x(17)=0.95*x(17);
[z,~]=d.mode_transfer_state(x,y,d.u0,a,'GFM',b);
first=measure(d,x,z,y,a,b,1);
z(10)=z(10)-0.09; z(11)=1.005;
[w,~]=d.mode_transfer_state(z,y,d.u0,b,'gfl',a);
second=measure(d,z,w,y,b,a,1);

% A dense set of off-equilibrium states and unequal MVA bases.
maxerr=zeros(1,7); count=0;
for mb=[50 100 200]
    p.Mbase=mb; kappa=p.Sbase/p.Mbase;
    for q=1:100
        vv=(0.85+0.30*rand)*exp(1i*(-pi+2*pi*rand));
        yy=[real(vv);imag(vv)];
        dd=ibr.eecon49_dual_mode_model('IBR_TEST',2,1,2,vv,p,0.45,0.08,abs(vv),'gfl');
        for m=1:2
            if m==1, el=a; er=b; target='GFM'; else, el=b; er=a; target='gfl'; end
            xx=dd.x0;
            xx(1:2)=0.55*randn(2,1); xx(3)=0.97+0.06*rand;
            xx(4)=angle(vv)+0.4*(rand-0.5); xx(5)=rand-0.5;
            xx(6:9)=0.06*randn(4,1);
            xx(10)=angle(vv)+0.4*(rand-0.5); xx(11)=1+0.02*(rand-0.5);
            xx(12)=abs(vv)+0.05*(rand-0.5); xx(13:16)=0.06*randn(4,1);
            xx(17)=dd.x0(17)*(0.9+0.2*rand);
            [rr,~]=dd.mode_transfer_state(xx,yy,dd.u0,el,target,er);
            mm=measure(dd,xx,rr,yy,el,er,kappa);
            maxerr=max(maxerr,mm(1:7)); count=count+1;
        end
    end
end
assert(all(maxerr(1:3)<1e-10));
assert(all(maxerr(4:5)==0));
assert(maxerr(6)<1e-10 && maxerr(7)<1e-10);

% Counterexample: a bare mode-flag change leaves stale controller coordinates.
badI=abs(d.current_injection(0,x,y,d.u0,b)-d.current_injection(0,x,y,d.u0,a));
assert(badI>1e-4);

% Stacked field identity on the actual assembled 5-device DAE.
s=cases.scenario_ieee14_1sg_4ibr(struct('case_profile','eecon49_figure4'));
[devices,~]=stability.build_mixed_resource_devices(s.case_data,s.resources,s.scenario_opt);
dae=stability.composite_dae(s.case_data,devices,struct());
ec=struct(); xx=dae.x0; yy=dae.y0; uu=dae.u0;
ff=dae.dae_f(0,xx,yy,uu,ec); stacked=zeros(size(ff));
owner=zeros(size(xx));
for k=1:numel(devices)
    ix=dae.device_offsets(k)+(1:devices(k).nx);
    iu=dae.u_offsets(k)+(1:devices(k).nu);
    stacked(ix)=devices(k).f(0,xx(ix),yy,uu(iu),ec); owner(ix)=k;
end
stackerr=norm(ff-stacked,inf); offblock=0; foreignV=0; epsfd=1e-6;
for j=1:numel(xx)
    xp=xx; xm=xx; xp(j)=xp(j)+epsfd; xm(j)=xm(j)-epsfd;
    col=(dae.dae_f(0,xp,yy,uu,ec)-dae.dae_f(0,xm,yy,uu,ec))/(2*epsfd);
    offblock=max(offblock,max(abs(col(owner~=owner(j)))));
end
for j=1:numel(yy)
    yp=yy; ym=yy; yp(j)=yp(j)+epsfd; ym(j)=ym(j)-epsfd;
    col=(dae.dae_f(0,xx,yp,uu,ec)-dae.dae_f(0,xx,ym,uu,ec))/(2*epsfd);
    for k=1:numel(devices)
        if ceil(j/2)==devices(k).bus_position, continue; end
        ix=dae.device_offsets(k)+(1:devices(k).nx);
        foreignV=max(foreignV,max(abs(col(ix))));
    end
end
assert(stackerr==0 && offblock==0 && foreignV==0);

fid=fopen(fullfile(outdir,'verification.txt'),'w'); assert(fid>=0);
cleaner=onCleanup(@()fclose(fid));
fprintf(fid,'Local proof audit, 2026-09-05; RNG 20260905\n');
fprintf(fid,'No network trajectory was rerun or modified.\n');
fprintf(fid,'Metrics: |dI| |dP| |dQ| |dVdc| |dIdc| |df_Hz| |d_norm_dq_squared| |d_dq|_inf |dx|_inf |d_dI_dt| |d_dVdc_dt| |d_dIdc_dt|\n');
fprintf(fid,'GFL->GFM: '); fprintf(fid,'%.12g ',first); fprintf(fid,'\n');
fprintf(fid,'GFM->GFL: '); fprintf(fid,'%.12g ',second); fprintf(fid,'\n');
fprintf(fid,'Sweep: %d transfers, Mbase=[50 100 200] MVA\n',count);
fprintf(fid,'Sweep maxima (first 7 metrics): '); fprintf(fid,'%.12g ',maxerr); fprintf(fid,'\n');
fprintf(fid,'Bare mode change current jump: %.12g pu\n',badI);
fprintf(fid,'Assembled device dimensions: '); fprintf(fid,'%d ',[devices.nx]); fprintf(fid,'\n');
fprintf(fid,'Assembled state count: %d\n',sum([devices.nx]));
fprintf(fid,'Stack error %.12g; foreign-state sensitivity %.12g; foreign-voltage sensitivity %.12g\n',stackerr,offblock,foreignV);
disp(fileread(fullfile(outdir,'verification.txt')));

ftex=fopen(fullfile(outdir,'verification_values.tex'),'w'); assert(ftex>=0);
ct=onCleanup(@()fclose(ftex));
names={'Ia','Pa','Qa','Va','Da','Fa','Ea','Dqa','Xa','Dota','Dva','Dda'};
for k=1:numel(names), fprintf(ftex,'\\newcommand{\\%s}{%s}\n',names{k},latexnum(first(k))); end
names={'Ib','Pb','Qb','Vb','Db','Fb','Eb','Dqb','Xb','Dotb','Dvb','Ddb'};
for k=1:numel(names), fprintf(ftex,'\\newcommand{\\%s}{%s}\n',names{k},latexnum(second(k))); end
names={'MaxI','MaxP','MaxQ','MaxV','MaxD','MaxF','MaxE'};
for k=1:numel(names), fprintf(ftex,'\\newcommand{\\%s}{%s}\n',names{k},latexnum(maxerr(k))); end
fprintf(ftex,'\\newcommand{\\BadI}{%s}\n',latexnum(badI));
fprintf(ftex,'\\newcommand{\\TransferCount}{%d}\n',count);
fprintf(ftex,'\\newcommand{\\StackError}{%s}\n',latexnum(stackerr));
fprintf(ftex,'\\newcommand{\\OffBlockError}{%s}\n',latexnum(offblock));
fprintf(ftex,'\\newcommand{\\ForeignVError}{%s}\n',latexnum(foreignV));
end

function ec=context(mode)
ec=struct('hybrid_state',struct('device_modes',struct('IBR_TEST',mode), ...
    'device_online',struct('IBR_TEST',true)));
end

function r=measure(d,x,z,y,a,b,kappa)
ia=d.current_injection(0,x,y,d.u0,a); ib=d.current_injection(0,z,y,d.u0,b);
v=complex(y(1),y(2)); sa=v*conj(ia); sb=v*conj(ib);
fa=d.f(0,x,y,d.u0,a); fb=d.f(0,z,y,d.u0,b);
ra=d.reconstruct(0,x,y,d.u0,a); rb=d.reconstruct(0,z,y,d.u0,b);
if strcmpi(ra.mode,'gfl'), ta=4; hz_a=ra.gfl.f_hz; else, ta=10; hz_a=ra.gfm.f_hz; end
if strcmpi(rb.mode,'gfl'), tb=4; hz_b=rb.gfl.f_hz; else, tb=10; hz_b=rb.gfm.f_hz; end
dia=exp(1i*x(ta))/kappa*(complex(fa(1),fa(2))+1i*fa(ta)*complex(x(1),x(2)));
dib=exp(1i*z(tb))/kappa*(complex(fb(1),fb(2))+1i*fb(tb)*complex(z(1),z(2)));
r=[abs(ib-ia),abs(real(sb-sa)),abs(imag(sb-sa)),abs(z(3)-x(3)), ...
    abs(z(17)-x(17)),abs(hz_b-hz_a),abs(sum(z(1:2).^2)-sum(x(1:2).^2)), ...
    norm(z(1:2)-x(1:2),inf),norm(z-x,inf),abs(dib-dia),abs(fb(3)-fa(3)),abs(fb(17)-fa(17))];
end

function s=latexnum(x)
if x==0, s='0'; return; end
if abs(x)>=1e-3 && abs(x)<1e3, s=sprintf('%.5g',x); return; end
e=floor(log10(abs(x))); s=sprintf('%.3f\\times10^{%d}',x/10^e,e);
end
