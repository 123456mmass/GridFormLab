function start_ai_service()
%START_AI_SERVICE  Start the Python AI service if not already running.
%Writes PID to ai_service/ai_service.pid for cleanup on GUI close.

aidir = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'ai_service');
pidfile = fullfile(aidir, 'ai_service.pid');

try
    webread('http://127.0.0.1:8000/health', weboptions('Timeout', 2));
    disp('AI service already running.');
    return;
catch
end

disp('Starting AI service...');

if ispc
    ps_cmd = sprintf(['powershell -Command "' ...
        '$p = Start-Process python -ArgumentList ''server.py'' -PassThru -WindowStyle Hidden -WorkingDirectory ''%s''; ' ...
        '$p.Id | Out-File -FilePath ''%s'' -NoNewline"'], aidir, pidfile);
    [status, msg] = system(ps_cmd);
else
    cmd = sprintf('cd "%s" && python server.py & echo $! > "%s"', aidir, pidfile);
    [status, msg] = system(cmd);
end

if status ~= 0
    warning('Failed to start AI service: %s', msg);
    return;
end

pause(2);
try
    webread('http://127.0.0.1:8000/health', weboptions('Timeout', 3));
    disp('AI service started successfully.');
catch
    disp('AI service may still be starting. It will be available shortly.');
end
end
