function close_request(fig)
%CLOSE_REQUEST  Wizard figure close request: resume uiwait and delete.
%   wizard.close_request(fig) is the figure CloseRequestFcn. It resumes any
%   pending uiwait so the wizard.show call can return, then deletes the figure.
uiresume(fig);
delete(fig);
end
