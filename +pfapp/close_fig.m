function close_fig(fig)
%CLOSE_FIG Window close handler — drop the cached app and delete the figure.
try
    fig.UserData.app = [];
catch
end
delete(fig);
end
