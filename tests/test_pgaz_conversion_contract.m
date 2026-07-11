function tests = test_pgaz_conversion_contract()
%TEST_PGAZ_CONVERSION_CONTRACT  Verify the PGAz case converter produces a network
%   identical to the in-house case (Ybus at machine precision). Guards the
%   AShunt fix (bus shunts Gs/Bs in MW/Mvar from mpc.bus, not dropped) and the
%   generator-bus mapping. PGAz is a reference tool; this test is filtered
%   (assumeFalse) when PGAz is not installed — it never becomes a silent pass.

tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths;
end

function c = attach_default_machines(c)
gbus = unique(c.mpc.gen(c.mpc.gen(:,8)~=0,1));
units = struct('gen_id',num2cell(gbus),'bus',num2cell(gbus), ...
    'H',num2cell(5*ones(numel(gbus),1)),'D',num2cell(zeros(numel(gbus),1)), ...
    'Xdp',num2cell(0.3*ones(numel(gbus),1)), ...
    'is_sync_condenser',num2cell(false(numel(gbus),1)));
c.machines = struct('units',units);
end

function pgaz_available(testCase)
pgaz_root = '/home/birds/Documents/PGAz_V1.1.1';
if ~exist(pgaz_root,'dir')
    testCase.assumeFalse(true, 'PGAz not installed; skipping PGAz contract test.');
end
addpath(pgaz_root);
end

function [Yours, bd, ld] = build_ours_ybus(c)
bd = c.bus_data; ld = c.line_data; nb = size(bd,1);
Yours = zeros(nb,nb);
for i = 1:size(ld,1)
    fr=ld(i,1); to=ld(i,2); R=ld(i,3); X=ld(i,4); Bh=ld(i,5);
    tap=ld(i,6); if tap==0, tap=1; end; ph=ld(i,7);
    ys=1/(R+1i*X); t=tap*exp(1i*deg2rad(ph)); ysht=1i*Bh;
    Yours(fr,fr)=Yours(fr,fr)+(ys+ysht)/(t*conj(t));
    Yours(to,to)=Yours(to,to)+ys+ysht;
    Yours(fr,to)=Yours(fr,to)-ys/conj(t);
    Yours(to,fr)=Yours(to,fr)-ys/t;
end
for k=1:nb, Yours(k,k)=Yours(k,k)+bd(k,9)+1i*bd(k,10); end
end

function test_case14_ybus_matches_pgaz(testCase)
pgaz_available(testCase);
c = attach_default_machines(cases.case_matpower6_case14());
[Yours,~,~] = build_ours_ybus(c);
sys = case_to_pgaz_sys(c);
[Ypgaz,~] = pgaz_ybus(sys); Ypgaz = full(Ypgaz);
[~,pord] = sort(sys.ABus(:,1)); Ypgaz = Ypgaz(pord,pord);
testCase.verifyEqual(max(abs(Yours(:)-Ypgaz(:))), 0, 'AbsTol', 1e-10, ...
    'case14 Ybus (Ours vs PGAz) must match at machine precision.');
end

function test_rts24_ybus_matches_pgaz(testCase)
pgaz_available(testCase);
c = attach_default_machines(cases.case_ieee_rts24_pgaz());
[Yours,~,~] = build_ours_ybus(c);
sys = case_to_pgaz_sys(c);
[Ypgaz,~] = pgaz_ybus(sys); Ypgaz = full(Ypgaz);
[~,pord] = sort(sys.ABus(:,1)); Ypgaz = Ypgaz(pord,pord);
testCase.verifyEqual(max(abs(Yours(:)-Ypgaz(:))), 0, 'AbsTol', 1e-10, ...
    'RTS-24 Ybus (Ours vs PGAz) must match at machine precision.');
end

function test_case14_shunt_not_dropped(testCase)
% Guards the AShunt fix: case14 bus 9 has Bs=0.19 pu (19 MVAr). The converter
% must place it in AShunt (MW/Mvar), not drop it.
pgaz_available(testCase);
c = attach_default_machines(cases.case_matpower6_case14());
sys = case_to_pgaz_sys(c);
testCase.verifyNotEmpty(sys.AShunt, 'AShunt must not be empty (case14 bus 9 shunt).');
b9 = find(sys.AShunt(:,1)==9,1);
testCase.verifyNotEmpty(b9, 'case14 bus 9 shunt must be present in AShunt.');
% Bs in MVAr = 0.19 pu * 100 baseMVA = 19
testCase.verifyEqual(sys.AShunt(b9,6), 19.0, 'AbsTol', 1e-9, ...
    'case14 bus 9 Bs must be 19 MVAr (0.19 pu * baseMVA).');
end

function test_generator_bus_mapping(testCase)
pgaz_available(testCase);
for nm = {'case_matpower6_case14','case_ieee_rts24_pgaz'}
    c = attach_default_machines(cases.(nm{1})());
    gbus_ours = unique(c.mpc.gen(c.mpc.gen(:,8)~=0,1));
    sys = case_to_pgaz_sys(c);
    testCase.verifyEqual(sort(sys.Gen(:,1)), sort(gbus_ours), ...
        sprintf('%s: PGAz Gen buses must match in-house gen buses.', nm{1}));
end
end
