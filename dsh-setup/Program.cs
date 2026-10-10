using System.Diagnostics;
using System.IO.Compression;

const string marker = "DSHSETUP_PAYLOAD_V1";
string self = Environment.ProcessPath ?? throw new InvalidOperationException("Cannot locate this executable.");
string home = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".dsh");
string desktopProfile = Path.Combine(home, "profiles", "desktop");
string stamp = DateTime.Now.ToString("yyyyMMdd-HHmmss");

try
{
    if (!OperatingSystem.IsWindows()) throw new InvalidOperationException("This setup runs on Windows only.");
    if (args.Contains("--self-test")) { TestInstaller(); Console.WriteLine("SELF_TEST_OK"); return; }
    if (MessageBox("Install this machine's DSH desktop settings, gateway key, and Med adapter?\n\nExisting files will be backed up first.", true) != true) return;

    var running = Process.GetProcessesByName("DeepSeek Harness");
    if (running.Length > 0)
    {
        if (MessageBox($"DeepSeek Harness is running ({running.Length} processes). Close it before continuing?", true) != true) return;
        foreach (var process in running) process.Kill(entireProcessTree: true);
        if (!SpinWait.SpinUntil(() => Process.GetProcessesByName("DeepSeek Harness").Length == 0, TimeSpan.FromSeconds(20)))
            throw new InvalidOperationException("DeepSeek Harness is still running. Close it and run setup again.");
    }

    byte[] payload = ReadPayload(self, marker);
    string staging = Path.Combine(Path.GetTempPath(), "dsh-setup-" + Guid.NewGuid().ToString("N"));
    Directory.CreateDirectory(staging);
    try
    {
        ZipFile.ExtractToDirectory(new MemoryStream(payload), staging, overwriteFiles: true);
        Directory.CreateDirectory(desktopProfile);
        CopyReplacing(Path.Combine(staging, "credentials.yaml"), Path.Combine(home, ".credentials.yaml"), Path.Combine(home, ".credentials.yaml.setup-backup-" + stamp));
        CopyReplacing(Path.Combine(staging, "cordis.patch.yml"), Path.Combine(desktopProfile, "cordis.patch.yml"), Path.Combine(desktopProfile, "cordis.patch.yml.setup-backup-" + stamp));
        CopyReplacing(Path.Combine(staging, "package.json"), Path.Combine(desktopProfile, "package.json"), Path.Combine(desktopProfile, "package.json.setup-backup-" + stamp));
        string plugin = Path.Combine(desktopProfile, "plugins", "gpt-sol-med");
        if (Directory.Exists(plugin)) Directory.Move(plugin, plugin + ".setup-backup-" + stamp);
        CopyDirectory(Path.Combine(staging, "gpt-sol-med"), plugin);
        string link = Path.Combine(desktopProfile, "node_modules", "@deepseek-ai", "dsh-llm-deepseek-api-key");
        Directory.CreateDirectory(Path.GetDirectoryName(link)!);
        if (Directory.Exists(link) || File.Exists(link)) Directory.Delete(link);
        CreateJunction(link, plugin);
    }
    finally { try { Directory.Delete(staging, recursive: true); } catch { } }

    MessageBox("Setup complete.\n\nOpen DeepSeek Harness and start a new chat.\nBackups use the suffix .setup-backup-" + stamp + ".", false);
}
catch (Exception error)
{
    MessageBox("Setup failed.\n\n" + error.Message, false);
    Environment.ExitCode = 1;
}

static void TestInstaller()
{
    string root = Path.Combine(Path.GetTempPath(), "dsh-setup-test-" + Guid.NewGuid().ToString("N"));
    string home = Path.Combine(root, ".dsh");
    string profile = Path.Combine(home, "profiles", "desktop");
    string plugin = Path.Combine(profile, "plugins", "gpt-sol-med");
    Directory.CreateDirectory(plugin);
    File.WriteAllText(Path.Combine(plugin, "package.json"), "{}");
    string link = Path.Combine(profile, "node_modules", "@deepseek-ai", "dsh-llm-deepseek-api-key");
    Directory.CreateDirectory(Path.GetDirectoryName(link)!);
    CreateJunction(link, plugin);
    if ((File.GetAttributes(link) & FileAttributes.ReparsePoint) == 0) throw new InvalidOperationException("Adapter link test failed.");
    Directory.Delete(link);
    Directory.Delete(root, recursive: true);
}

static byte[] ReadPayload(string executable, string marker)
{
    byte[] needle = System.Text.Encoding.ASCII.GetBytes(marker);
    using FileStream stream = File.OpenRead(executable);
    long position = FindLast(stream, needle);
    if (position < 0) throw new InvalidOperationException("Setup payload is missing.");
    stream.Position = position + needle.Length;
    using var output = new MemoryStream();
    stream.CopyTo(output);
    return output.ToArray();
}

static long FindLast(Stream stream, byte[] needle)
{
    byte[] buffer = new byte[1024 * 1024];
    long found = -1;
    long basePosition = 0;
    int kept = 0;
    byte[] window = new byte[needle.Length - 1 + buffer.Length];
    int read;
    while ((read = stream.Read(buffer, 0, buffer.Length)) > 0)
    {
        Buffer.BlockCopy(window, 0, window, 0, kept);
        Buffer.BlockCopy(buffer, 0, window, kept, read);
        int available = kept + read;
        for (int index = 0; index <= available - needle.Length; index++)
            if (window.AsSpan(index, needle.Length).SequenceEqual(needle)) found = basePosition + index;
        kept = Math.Min(needle.Length - 1, available);
        Buffer.BlockCopy(window, available - kept, window, 0, kept);
        basePosition += read;
    }
    return found;
}

static void CopyReplacing(string source, string destination, string backup)
{
    Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
    if (File.Exists(destination)) File.Copy(destination, backup, overwrite: false);
    File.Copy(source, destination, overwrite: true);
}

static void CopyDirectory(string source, string destination)
{
    Directory.CreateDirectory(destination);
    foreach (string directory in Directory.GetDirectories(source, "*", SearchOption.AllDirectories))
        Directory.CreateDirectory(directory.Replace(source, destination));
    foreach (string file in Directory.GetFiles(source, "*", SearchOption.AllDirectories))
        File.Copy(file, file.Replace(source, destination), overwrite: false);
}

static void CreateJunction(string link, string target)
{
    using Process process = Process.Start(new ProcessStartInfo("cmd.exe", "/c mklink /J \"" + link + "\" \"" + target + "\"")
    {
        CreateNoWindow = true,
        UseShellExecute = false,
        RedirectStandardError = true
    }) ?? throw new InvalidOperationException("Cannot create the adapter link.");
    string error = process.StandardError.ReadToEnd();
    process.WaitForExit();
    if (process.ExitCode != 0 || !Directory.Exists(link)) throw new InvalidOperationException(string.IsNullOrWhiteSpace(error) ? "Cannot create the adapter link." : error.Trim());
}

static bool? MessageBox(string text, bool question)
{
    [System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
    static extern int MessageBoxW(IntPtr owner, string text, string caption, uint type);
    int result = MessageBoxW(IntPtr.Zero, text, "DSH Setup", question ? 0x00000004u | 0x00000020u : 0x00000040u);
    return question ? result == 6 : null;
}
