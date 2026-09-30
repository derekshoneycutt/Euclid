#:property TargetFramework=net10.0-windows
#:property UseWPF=true
#:property PublishAot=false

using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Automation;

internal static class Program
{
    private const string RestartLabel = "Restart animation";
    private const string SearchLabel = "Search animations";

    [STAThread]
    private static int Main()
    {
        try
        {
            Run();
            return 0;
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine(exception.Message);
            return 1;
        }
    }

    private static void Run()
    {
        if (!Environment.UserInteractive)
        {
            throw new InvalidOperationException(
                "accessibility-windows requires a logged-in interactive desktop session.");
        }

        string root = Directory.GetCurrentDirectory();
        string binary = Path.Combine(root, ".build", "debug", "euclid.exe");
        string scenario = Path.Combine(
            "tools", "accessibility", "accessibility-windows-phase1.jsonl");
        string artifactRoot = Path.Combine(root, ".build", "accessibility-windows");
        string reportPath = Path.Combine(artifactRoot, "uia.json");
        if (!File.Exists(binary))
        {
            throw new FileNotFoundException(
                $"Missing debug application: {binary}. " +
                "Build with cmake --build --preset debug.", binary);
        }

        Directory.CreateDirectory(artifactRoot);
        SessionRecord[] sessions =
        [
            InvokeEuclidSession(1, root, binary, scenario, artifactRoot),
            InvokeEuclidSession(2, root, binary, scenario, artifactRoot),
        ];
        var report = new Report(
            SchemaVersion: 1,
            Platform: "windows",
            SessionCount: sessions.Length,
            RepeatedTeardown: sessions.All(session => session.ProviderRemoved),
            Sessions: sessions);
        var options = new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
            WriteIndented = true,
        };
        string json = JsonSerializer.Serialize(report, options);
        File.WriteAllText(reportPath, json + Environment.NewLine);
        Console.WriteLine(json);
    }

    private static SessionRecord InvokeEuclidSession(
        int index, string root, string binary, string scenario, string artifactRoot)
    {
        string sessionDirectory = Path.Combine(artifactRoot, $"session-{index}");
        if (Directory.Exists(sessionDirectory))
        {
            Directory.Delete(sessionDirectory, recursive: true);
        }
        Directory.CreateDirectory(sessionDirectory);
        string stdoutPath = Path.Combine(sessionDirectory, "stdout.log");
        string stderrPath = Path.Combine(sessionDirectory, "stderr.log");

        using var process = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = binary,
                WorkingDirectory = root,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
            },
        };
        process.StartInfo.ArgumentList.Add($"--scenario={scenario}");
        process.StartInfo.ArgumentList.Add(
            $"--scenario-artifacts=.build/accessibility-windows/session-{index}");
        if (!process.Start())
        {
            throw new InvalidOperationException($"Session {index} did not start.");
        }
        Task<string> stdout = process.StandardOutput.ReadToEndAsync();
        Task<string> stderr = process.StandardError.ReadToEndAsync();

        try
        {
            IntPtr hwnd = WaitForWindow(process, index, TimeSpan.FromSeconds(30));
            AutomationElement rootElement = AutomationElement.FromHandle(hwnd);
            var buttonCondition = new AndCondition(
                new PropertyCondition(
                    AutomationElement.ControlTypeProperty, ControlType.Button),
                new PropertyCondition(
                    AutomationElement.NameProperty, RestartLabel));
            AutomationElement button = WaitForElement(
                () => rootElement.FindFirst(TreeScope.Descendants, buttonCondition),
                process,
                TimeSpan.FromSeconds(20),
                $"Session {index} did not expose {RestartLabel} through UIA.");
            ElementRecord rootRecord = GetElementRecord(rootElement);
            ElementRecord buttonRecord = GetElementRecord(button);
            if (!buttonRecord.Enabled || !buttonRecord.KeyboardFocusable ||
                buttonRecord.Bounds.Width <= 0 || buttonRecord.Bounds.Height <= 0)
            {
                throw new InvalidOperationException(
                    $"Session {index} exposed incoherent Restart button facts.");
            }

            button.SetFocus();
            WaitFor(
                () => button.Current.HasKeyboardFocus,
                process,
                TimeSpan.FromSeconds(3),
                $"Session {index} did not publish Restart keyboard focus.");
            var searchCondition = new PropertyCondition(
                AutomationElement.NameProperty, SearchLabel);
            AutomationElement? search = rootElement.FindFirst(
                TreeScope.Descendants, searchCondition);
            if (search is null || !search.Current.IsKeyboardFocusable)
            {
                throw new InvalidOperationException(
                    $"Session {index} did not expose a focusable Search control.");
            }
            search.SetFocus();
            WaitFor(
                () => !button.Current.HasKeyboardFocus,
                process,
                TimeSpan.FromSeconds(3),
                $"Session {index} retained stale Restart keyboard focus.");

            if (!button.TryGetCurrentPattern(
                    InvokePattern.Pattern, out object pattern) ||
                pattern is not InvokePattern invokePattern)
            {
                throw new InvalidOperationException(
                    $"Session {index} Restart button has no UIA Invoke pattern.");
            }
            invokePattern.Invoke();
            if (!process.WaitForExit(60_000))
            {
                throw new TimeoutException(
                    $"Session {index} did not observe reset and shut down.");
            }
            process.WaitForExit();
            if (process.ExitCode != 0)
            {
                throw new InvalidOperationException(
                    $"Session {index} exited with code {process.ExitCode}.");
            }

            bool providerRemoved = ProviderWasRemoved(hwnd);
            if (!providerRemoved)
            {
                throw new InvalidOperationException(
                    $"Session {index} UIA provider remained available after shutdown.");
            }
            return new SessionRecord(
                Session: index,
                ProcessId: process.Id,
                Hwnd: hwnd.ToInt64(),
                Root: rootRecord,
                RestartButton: buttonRecord,
                FocusGain: true,
                FocusLoss: true,
                InvokeCount: 1,
                ResetObserved: true,
                ExitCode: process.ExitCode,
                ProviderRemoved: true);
        }
        finally
        {
            if (!process.HasExited)
            {
                process.CloseMainWindow();
                if (!process.WaitForExit(5_000))
                {
                    process.Kill(entireProcessTree: true);
                    process.WaitForExit();
                }
            }
            File.WriteAllText(stdoutPath, stdout.GetAwaiter().GetResult());
            File.WriteAllText(stderrPath, stderr.GetAwaiter().GetResult());
        }
    }

    private static IntPtr WaitForWindow(
        Process process, int index, TimeSpan timeout)
    {
        var timer = Stopwatch.StartNew();
        while (timer.Elapsed < timeout)
        {
            if (process.HasExited)
            {
                throw new InvalidOperationException(
                    $"Session {index} exited before creating a window.");
            }
            process.Refresh();
            if (process.MainWindowHandle != IntPtr.Zero)
            {
                return process.MainWindowHandle;
            }
            Thread.Sleep(50);
        }
        throw new TimeoutException(
            $"Session {index} did not create a visible HWND.");
    }

    private static AutomationElement WaitForElement(
        Func<AutomationElement?> query,
        Process process,
        TimeSpan timeout,
        string failure)
    {
        var timer = Stopwatch.StartNew();
        while (timer.Elapsed < timeout)
        {
            if (process.HasExited)
            {
                throw new InvalidOperationException(
                    "Euclid exited before the expected UIA element appeared.");
            }
            AutomationElement? element = query();
            if (element is not null)
            {
                return element;
            }
            Thread.Sleep(50);
        }
        throw new TimeoutException(failure);
    }

    private static void WaitFor(
        Func<bool> predicate,
        Process process,
        TimeSpan timeout,
        string failure)
    {
        var timer = Stopwatch.StartNew();
        while (timer.Elapsed < timeout)
        {
            if (process.HasExited)
            {
                throw new InvalidOperationException(
                    "Euclid exited before the expected UIA transition.");
            }
            if (predicate())
            {
                return;
            }
            Thread.Sleep(50);
        }
        throw new TimeoutException(failure);
    }

    private static ElementRecord GetElementRecord(AutomationElement element)
    {
        System.Windows.Rect bounds = element.Current.BoundingRectangle;
        return new ElementRecord(
            Name: element.Current.Name,
            ControlType: element.Current.ControlType.ProgrammaticName,
            Enabled: element.Current.IsEnabled,
            KeyboardFocusable: element.Current.IsKeyboardFocusable,
            HasKeyboardFocus: element.Current.HasKeyboardFocus,
            Bounds: new BoundsRecord(
                X: bounds.X,
                Y: bounds.Y,
                Width: bounds.Width,
                Height: bounds.Height));
    }

    private static bool ProviderWasRemoved(IntPtr hwnd)
    {
        try
        {
            return AutomationElement.FromHandle(hwnd) is null;
        }
        catch (ArgumentException)
        {
            return true;
        }
        catch (ElementNotAvailableException)
        {
            return true;
        }
    }
}

internal sealed record BoundsRecord(double X, double Y, double Width, double Height);

internal sealed record ElementRecord(
    string Name,
    string ControlType,
    bool Enabled,
    bool KeyboardFocusable,
    bool HasKeyboardFocus,
    BoundsRecord Bounds);

internal sealed record SessionRecord(
    int Session,
    int ProcessId,
    long Hwnd,
    ElementRecord Root,
    ElementRecord RestartButton,
    bool FocusGain,
    bool FocusLoss,
    int InvokeCount,
    bool ResetObserved,
    int ExitCode,
    bool ProviderRemoved);

internal sealed record Report(
    int SchemaVersion,
    string Platform,
    int SessionCount,
    bool RepeatedTeardown,
    SessionRecord[] Sessions);
