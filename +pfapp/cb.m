function app = cb(fig, action_fn, takes_fig)
%CB Central GUI callback dispatcher.
%   Wired as the callback for every interactive widget. It fetches the live
%   app struct from FIG.UserData.app, invokes the action function (which may
%   modify app and/or need fig), and writes the (possibly new) app back.
%   Capturing only the stable FIG handle — never the app struct — is what
%   keeps the wiring valid across an in-place theme rebuild.

app = fig.UserData.app;
if takes_fig
    app = action_fn(app, fig);
else
    app = action_fn(app);
end
fig.UserData.app = app;
end
