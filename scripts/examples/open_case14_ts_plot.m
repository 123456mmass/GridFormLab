cd('C:/Users/User/Desktop/IBR/Power-flow');
pf_init_paths;
clear functions;
res = run_case14_ts_demo();
set(gcf,'Visible','on');
figure(gcf);
