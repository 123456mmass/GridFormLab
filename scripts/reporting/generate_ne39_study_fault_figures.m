function generate_ne39_study_fault_figures()
%GENERATE_NE39_STUDY_FAULT_FIGURES รูปรายอุปกรณ์จาก fault cache จริงเท่านั้น.
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
cache = fullfile(root,'output','diagnostics','ne39_tamu');
out = fullfile(root,'docs','figures','ne39_study_fault');
for ns = [5 1]
    stem = sprintf('study_fault_%dsg_%dibr',ns,10-ns);
    a = load(fullfile(cache,[stem '.mat']),'r','s');
    b = load(fullfile(cache,[stem '_metrics.mat']),'diag');
    r = a.r; d = b.diag;
    for k = 1:numel(d.resource_ids)
        id = d.resource_ids{k}; resource = a.s.resources(k);
        bus = find(a.s.case_data.mpc.bus(:,1)==resource.bus_id,1);
        f = pf_page_figure(7.0,8.4,10);
        tiles = tiledlayout(f,3,2,'TileSpacing','compact','Padding','compact');
        title(tiles,sprintf('%d SG + %d IBR: %s (fault-only, no switching)', ...
            ns,10-ns,id),'Interpreter','none');
        panels = {r.bus_voltage_magnitude(bus,:),d.f_Hz(k,:), ...
            d.severity(k,:),d.rocof_Hz_s(k,:),d.rocov_filtered_pu_s(k,:),d.Vdc_pu(k,:)};
        labels = {'$|V_{PCC}|$ (pu)','$f$ (Hz)','$SI$','$df/dt$ (Hz/s)', ...
            '$d|V|/dt$ (pu/s)','$V_{dc}$ (pu)'};
        if startsWith(id,'SG')
            panels{6} = r.device_P(k,:)*a.s.case_data.base_values.S_base_MVA;
            labels{6} = '$P$ (MW)';
        end
        for p = 1:6
            ax = nexttile(tiles);
            plot(ax,r.t,panels{p},'k-','LineWidth',1.2);
            if p==5
                hold(ax,'on');
                plot(ax,r.t,d.rocov_raw_pu_s(k,:),'Color',[.5 .5 .5], ...
                    'LineStyle','--','LineWidth',.8);
                legend(ax,{'filtered ($\tau=0.02$ s)','raw continuous'}, ...
                    'Interpreter','latex','Location','best','Box','off');
            end
            xlabel(ax,'$t$ (s)','Interpreter','latex');
            ylabel(ax,labels{p},'Interpreter','latex');
            title(ax,sprintf('(%c) %s','a'+p-1,id),'Interpreter','none');
            set(ax,'Box','off','TickDir','out','TickLabelInterpreter','latex', ...
                'XGrid','on','YGrid','on','XMinorGrid','on','YMinorGrid','on', ...
                'GridLineStyle','--','MinorGridLineStyle','--');
            xlim(ax,[r.t(1) r.t(end)]);
            xline(ax,.5,':','HandleVisibility','off');
            xline(ax,.7,':','HandleVisibility','off');
        end
        pf_page_export(f,string(fullfile(out,[stem '_' id '.png'])),200,true);
    end
end
end
