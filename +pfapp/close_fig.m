function close_fig(fig)
%DEPRECATED (Phase C): superseded by the Studio GUI (+studio/launch.m).
%   Header banner only; behavior unchanged.
%CLOSE_FIG Window close handler — drop the cached app and delete the figure.
try
    fig.UserData.app = [];
catch
end
delete(fig);
end
