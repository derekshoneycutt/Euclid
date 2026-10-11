#:property TargetFramework=net10.0-windows
#:property UseWPF=true
#:property PublishAot=false

using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Automation;
using System.Windows.Automation.Text;

internal static class Program
{
    private const string RestartLabel = "Restart animation";
    private const string PauseLabel = "Pause animation";
    private const string ResumeLabel = "Resume animation";
    private const string SettingsLabel = "Settings";
    private const string CheckboxLabel = "Display FPS";
    private const string SliderLabel = "Maximum Dust particles";
    private const string VerticalSplitterLabel = "Resize left and right panes";
    private const string HorizontalSplitterLabel = "Resize upper and lower panes";
    private const string GifHeaderLabel = "Save GIF";
    private const string GifStatusLabel = "GIF capture idle";
    private const string SearchLabel = "Search animations";
    private const string TreeLabel = "Animation library";
    private const string SearchQuery = "Elements";
    private const string MultibyteSearchQuery = "a\u03b2c";
    private const string RetirementQuery = "algebra";
    private const string SurvivingItemLabel = "Euclid's Elements";
    private const string FirstRetiredItemLabel = "Terminal";
    private const string RetirementResultLabel = "Algebra";

    [STAThread]
    private static int Main(string[] arguments)
    {
        try
        {
            Run(arguments);
            return 0;
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine(exception.Message);
            return 1;
        }
    }

    private static void Run(string[] arguments)
    {
        if (!Environment.UserInteractive)
        {
            throw new InvalidOperationException(
                "accessibility-windows requires a logged-in interactive desktop session.");
        }

        string root = Directory.GetCurrentDirectory();
        string binary = ResolveBinary(root, arguments);
        string defaultBinary = Path.Combine(root, ".build", "debug", "euclid.exe");
        bool scenarioEnabled = Path.GetFullPath(binary) == Path.GetFullPath(defaultBinary);
        string scenario = Path.Combine(
            "tools", "accessibility", "accessibility-windows.jsonl");
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
            InvokeEuclidSession(
                1, root, binary, scenario, artifactRoot, scenarioEnabled),
            InvokeEuclidSession(
                2, root, binary, scenario, artifactRoot, scenarioEnabled),
        ];
        var report = new Report(
            SchemaVersion: 3,
            Platform: "windows",
            OperatingSystem: RuntimeInformation.OSDescription,
            Architecture: RuntimeInformation.OSArchitecture.ToString(),
            AccessKitWindowsVersion: "0.35.1",
            AutomatedScope: "phase_3_search_and_tree",
            Result: "pass",
            Limitations:
            [
                "inbox_managed_uia_controller_for_property_unavailable",
                "accesskit_windows_0_35_1_partial_text_range_select_is_noop",
                "selected_text_replacement_not_exposed_by_inbox_managed_uia",
                "accesskit_windows_0_35_1_tree_range_value_is_read_only",
                "transient_gif_busy_and_disabled_states_not_yet_automated",
                "multi_dpi_and_resize_bounds_not_yet_automated",
            ],
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

    private static string ResolveBinary(string root, string[] arguments)
    {
        if (arguments.Length == 0)
        {
            return Path.Combine(root, ".build", "debug", "euclid.exe");
        }
        const string prefix = "--binary=";
        if (arguments.Length != 1 ||
            !arguments[0].StartsWith(prefix, StringComparison.Ordinal) ||
            arguments[0].Length == prefix.Length)
        {
            throw new ArgumentException(
                "Usage: accesskit_windows_tree_probe.cs [--binary=PATH]");
        }
        string candidate = arguments[0][prefix.Length..];
        return Path.GetFullPath(candidate, root);
    }

    private static SessionRecord InvokeEuclidSession(
        int index, string root, string binary, string scenario, string artifactRoot,
        bool scenarioEnabled)
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
        if (scenarioEnabled)
        {
            process.StartInfo.ArgumentList.Add($"--scenario={scenario}");
            process.StartInfo.ArgumentList.Add(
                $"--scenario-artifacts=.build/accessibility-windows/session-{index}");
        }
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

            string[] initialChildren = GetChildNames(rootElement);
            LibrarySnapshotRecord library = CaptureLibrarySnapshot(
                rootElement, process, index);
            AutomationElement survivingItem = WaitForNamedControl(
                rootElement, process, SurvivingItemLabel, ControlType.TreeItem, index);
            AutomationElement retirementItem = WaitForNamedControl(
                rootElement, process, FirstRetiredItemLabel,
                ControlType.TreeItem, index);
            TreeInteractionRecord treeInteraction = ExerciseInitialTree(
                rootElement, process, index, survivingItem);
            SearchActionRecord search = ExerciseSearch(rootElement, process, index);
            TreeFilterRecord treeFilter = ExerciseTreeFiltering(
                rootElement, process, index, survivingItem, retirementItem);
            RangeFactsRecord verticalSplitter = GetRangeFacts(
                WaitForNamedControl(rootElement, process, VerticalSplitterLabel,
                    ControlType.Slider, index), index);
            RangeFactsRecord horizontalSplitter = GetRangeFacts(
                WaitForNamedControl(rootElement, process, HorizontalSplitterLabel,
                    ControlType.Slider, index), index);
            ButtonActionRecord pause = ExercisePause(rootElement, process, index);
            AccordionRecord settings = ExerciseSettings(rootElement, process, index);
            ToggleActionRecord checkbox = ExerciseCheckbox(rootElement, process, index);
            RangeActionRecord slider = ExerciseSlider(rootElement, process, index);

            button.SetFocus();
            WaitFor(
                () => button.Current.HasKeyboardFocus,
                process,
                TimeSpan.FromSeconds(3),
                $"Session {index} did not publish Restart keyboard focus.");
            AutomationElement focusTarget = WaitForNamedControl(
                rootElement, process, CheckboxLabel, ControlType.CheckBox, index);
            if (!focusTarget.Current.IsKeyboardFocusable)
            {
                throw new InvalidOperationException(
                    $"Session {index} did not expose a focusable Display FPS control.");
            }
            focusTarget.SetFocus();
            WaitFor(
                () => !button.Current.HasKeyboardFocus,
                process,
                TimeSpan.FromSeconds(3),
                $"Session {index} retained stale Restart keyboard focus.");
            GifIdleRecord gif = ExerciseGifIdle(rootElement, process, index);

            if (!button.TryGetCurrentPattern(
                    InvokePattern.Pattern, out object pattern) ||
                pattern is not InvokePattern invokePattern)
            {
                throw new InvalidOperationException(
                    $"Session {index} Restart button has no UIA Invoke pattern.");
            }
            invokePattern.Invoke();
            bool resetObserved = scenarioEnabled;
            if (scenarioEnabled && !process.WaitForExit(60_000))
            {
                throw new TimeoutException(
                    $"Session {index} did not observe reset and shut down.");
            }
            if (!scenarioEnabled)
            {
                process.CloseMainWindow();
                if (!process.WaitForExit(20_000))
                {
                    throw new TimeoutException(
                        $"Session {index} release window did not close.");
                }
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
                InitialChildren: initialChildren,
                Library: library,
                Search: search,
                TreeInteraction: treeInteraction,
                TreeFilter: treeFilter,
                PauseButton: pause,
                VerticalSplitter: verticalSplitter,
                HorizontalSplitter: horizontalSplitter,
                Settings: settings,
                Checkbox: checkbox,
                Slider: slider,
                Gif: gif,
                FocusGain: true,
                FocusLoss: true,
                InvokeCount: 1,
                ResetObserved: resetObserved,
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

    private static ButtonActionRecord ExercisePause(
        AutomationElement root, Process process, int index)
    {
        AutomationElement pause = WaitForNamedControl(
            root, process, PauseLabel, ControlType.Button, index);
        ElementRecord before = GetElementRecord(pause);
        Invoke(pause, $"Session {index} Pause button");
        AutomationElement resume = WaitForNamedControl(
            root, process, ResumeLabel, ControlType.Button, index);
        ElementRecord invoked = GetElementRecord(resume);
        if (!RuntimeIdentityEqual(before.RuntimeId, invoked.RuntimeId))
        {
            throw new InvalidOperationException(
                $"Session {index} Pause button changed runtime identity.");
        }
        Invoke(resume, $"Session {index} Resume button");
        AutomationElement restored = WaitForNamedControl(
            root, process, PauseLabel, ControlType.Button, index);
        ElementRecord after = GetElementRecord(restored);
        if (!RuntimeIdentityEqual(before.RuntimeId, after.RuntimeId))
        {
            throw new InvalidOperationException(
                $"Session {index} resumed button changed runtime identity.");
        }
        return new ButtonActionRecord(before, invoked, after, 2);
    }

    private static LibrarySnapshotRecord CaptureLibrarySnapshot(
        AutomationElement root, Process process, int index)
    {
        AutomationElement search = WaitForNamedElement(
            root, process, SearchLabel, index);
        AutomationElement tree = WaitForNamedElement(
            root, process, TreeLabel, index);
        ElementRecord[] descendants = tree.FindAll(
                TreeScope.Descendants, Condition.TrueCondition)
            .Cast<AutomationElement>()
            .Take(64)
            .Select(GetElementRecord)
            .ToArray();
        return new LibrarySnapshotRecord(
            GetElementRecord(search), GetElementRecord(tree), descendants);
    }

    private static SearchActionRecord ExerciseSearch(
        AutomationElement root, Process process, int index)
    {
        AutomationElement search = WaitForNamedElement(
            root, process, SearchLabel, index);
        ElementRecord element = GetElementRecord(search);
        SearchTextRecord initial = GetSearchTextRecord(search, index);
        SetSearchValue(search, MultibyteSearchQuery, index);
        SearchTextRecord multibyte = WaitForSearchValue(
            root, process, index, MultibyteSearchQuery);
        search = WaitForNamedElement(root, process, SearchLabel, index);
        SelectSearchRange(search, 2, 2, index);
        SearchTextRecord collapsed = WaitForSearchSelection(
            root, process, index, "", 2, 2);
        search = WaitForNamedElement(root, process, SearchLabel, index);
        SelectSearchRange(search, 1, 2, index);
        PartialTextSelectionRecord partialSelection =
            WaitForPartialSearchSelection(
                root, process, index, collapsed, "\u03b2", 1, 2);
        search = WaitForNamedElement(root, process, SearchLabel, index);
        SetSearchValue(search, SearchQuery, index);
        SearchTextRecord filtered = WaitForSearchValue(
            root, process, index, SearchQuery);
        search = WaitForNamedElement(root, process, SearchLabel, index);
        SelectSearchDocument(search, index);
        SearchTextRecord selected = WaitForSearchSelection(
            root, process, index, SearchQuery, 0, SearchQuery.Length);
        if (!RuntimeIdentityEqual(element.RuntimeId, GetRuntimeId(search)))
        {
            throw new InvalidOperationException(
                $"Session {index} Search changed runtime identity.");
        }
        return new SearchActionRecord(
            element, initial, multibyte, collapsed,
            partialSelection, filtered, selected);
    }

    private static TreeInteractionRecord ExerciseInitialTree(
        AutomationElement root, Process process, int index,
        AutomationElement branch)
    {
        ElementRecord branchBefore = GetElementRecord(branch);
        string[] topLevelBefore = GetChildNames(WaitForNamedElement(
            root, process, TreeLabel, index));
        ExpandCollapseState initialState = GetExpandCollapseState(
            branch, index, SurvivingItemLabel);
        if (initialState == ExpandCollapseState.Expanded)
        {
            GetExpandCollapsePattern(branch, index, SurvivingItemLabel).Collapse();
            _ = WaitForExpandCollapseState(
                root, process, index, SurvivingItemLabel,
                ExpandCollapseState.Collapsed);
        }
        branch = WaitForNamedControl(
            root, process, SurvivingItemLabel, ControlType.TreeItem, index);
        GetExpandCollapsePattern(branch, index, SurvivingItemLabel).Expand();
        _ = WaitForExpandCollapseState(
            root, process, index, SurvivingItemLabel,
            ExpandCollapseState.Expanded);
        branch = WaitForNamedControl(
            root, process, SurvivingItemLabel, ControlType.TreeItem, index);
        string[] branchChildren = GetChildNames(branch);
        GetExpandCollapsePattern(branch, index, SurvivingItemLabel).Collapse();
        _ = WaitForExpandCollapseState(
            root, process, index, SurvivingItemLabel,
            ExpandCollapseState.Collapsed);
        branch = WaitForNamedControl(
            root, process, SurvivingItemLabel, ControlType.TreeItem, index);
        GetExpandCollapsePattern(branch, index, SurvivingItemLabel).Expand();
        ExpandCollapseState restoredState = WaitForExpandCollapseState(
            root, process, index, SurvivingItemLabel,
            ExpandCollapseState.Expanded);

        branch = WaitForNamedControl(
            root, process, SurvivingItemLabel, ControlType.TreeItem, index);
        if (!branch.TryGetCurrentPattern(
                SelectionItemPattern.Pattern, out object selectionObject) ||
            selectionObject is not SelectionItemPattern selection)
        {
            throw new InvalidOperationException(
                $"Session {index} {SurvivingItemLabel} has no SelectionItem pattern.");
        }
        selection.Select();
        WaitFor(
            () =>
            {
                AutomationElement current = WaitForNamedControl(
                    root, process, SurvivingItemLabel, ControlType.TreeItem, index);
                return ((SelectionItemPattern)current.GetCurrentPattern(
                    SelectionItemPattern.Pattern)).Current.IsSelected;
            },
            process,
            TimeSpan.FromSeconds(5),
            $"Session {index} did not select {SurvivingItemLabel}.");

        AutomationElement tree = WaitForNamedElement(root, process, TreeLabel, index);
        RangeFactsRecord rangeBefore = GetRangeFacts(tree, index);
        double requested = rangeBefore.Value;
        double observed = rangeBefore.Value;
        if (rangeBefore.Maximum > rangeBefore.Minimum)
        {
            requested = rangeBefore.Value < rangeBefore.Maximum
                ? Math.Min(rangeBefore.Maximum,
                    rangeBefore.Value + Math.Max(rangeBefore.SmallChange, 1))
                : Math.Max(rangeBefore.Minimum,
                    rangeBefore.Value - Math.Max(rangeBefore.SmallChange, 1));
            var range = (RangeValuePattern)tree.GetCurrentPattern(
                RangeValuePattern.Pattern);
            range.SetValue(requested);
            observed = WaitForTreeRangeValue(root, process, index, requested);
            tree = WaitForNamedElement(root, process, TreeLabel, index);
            ((RangeValuePattern)tree.GetCurrentPattern(
                RangeValuePattern.Pattern)).SetValue(rangeBefore.Value);
            _ = WaitForTreeRangeValue(root, process, index, rangeBefore.Value);
        }
        return new TreeInteractionRecord(
            branchBefore, initialState.ToString(), restoredState.ToString(),
            topLevelBefore, branchChildren, true, rangeBefore, requested, observed);
    }

    private static TreeFilterRecord ExerciseTreeFiltering(
        AutomationElement root, Process process, int index,
        AutomationElement survivingItem, AutomationElement retirementItem)
    {
        int[] survivingRuntimeId = GetRuntimeId(survivingItem);
        string[] filteredNames = WaitForTreeTopology(
            root, process, index, SurvivingItemLabel, "Terminal");
        TreeScrollRecord scroll = ExerciseFilteredTreeScroll(
            root, process, index);
        AutomationElement currentSurvivor = WaitForNamedControl(
            root, process, SurvivingItemLabel, ControlType.TreeItem, index);
        bool survivingIdentityContinuous = RuntimeIdentityEqual(
            survivingRuntimeId, GetRuntimeId(currentSurvivor));
        if (!survivingIdentityContinuous)
        {
            throw new InvalidOperationException(
                $"Session {index} surviving TreeItem changed runtime identity.");
        }
        RetainedElementRecord firstRetired = ProbeRetainedTreeItem(
            root, retirementItem, FirstRetiredItemLabel, index);

        AutomationElement search = WaitForNamedElement(
            root, process, SearchLabel, index);
        SetSearchValue(search, RetirementQuery, index);
        SearchTextRecord retirementText = WaitForSearchValue(
            root, process, index, RetirementQuery);
        string[] retirementNames = WaitForTreeTopology(
            root, process, index, RetirementResultLabel, SurvivingItemLabel);
        RetainedElementRecord survivorRetired = ProbeRetainedTreeItem(
            root, currentSurvivor, SurvivingItemLabel, index);
        search = WaitForNamedElement(root, process, SearchLabel, index);
        SetSearchValue(search, "", index);
        SearchTextRecord restoredText = WaitForSearchValue(
            root, process, index, "");
        string[] restoredNames = WaitForTreeTopology(
            root, process, index, SurvivingItemLabel, "__absent_sentinel__");
        AutomationElement returnedRetirement = WaitForNamedControl(
            root, process, SurvivingItemLabel, ControlType.TreeItem, index);
        bool retiredIdWasNotReused = !RuntimeIdentityEqual(
            survivingRuntimeId, GetRuntimeId(returnedRetirement));
        if (!retiredIdWasNotReused)
        {
            throw new InvalidOperationException(
                $"Session {index} reused a retired Euclid runtime identity.");
        }
        return new TreeFilterRecord(
            filteredNames, retirementNames, restoredNames,
            survivingIdentityContinuous, scroll,
            firstRetired, survivorRetired,
            retiredIdWasNotReused, retirementText, restoredText);
    }

    private static TreeScrollRecord ExerciseFilteredTreeScroll(
        AutomationElement root, Process process, int index)
    {
        AutomationElement tree = WaitForNamedElement(root, process, TreeLabel, index);
        RangeFactsRecord before = GetRangeFacts(tree, index);
        double step = Math.Max(before.SmallChange, 1);
        double requested = before.Value < before.Maximum
            ? Math.Min(before.Maximum, before.Value + step)
            : Math.Max(before.Minimum, before.Value - step);
        if (before.Maximum <= before.Minimum)
        {
            return new TreeScrollRecord(
                before, requested, before.Value, before.Value, "no_positive_range");
        }
        try
        {
            ((RangeValuePattern)tree.GetCurrentPattern(
                RangeValuePattern.Pattern)).SetValue(requested);
        }
        catch (InvalidOperationException) when (before.IsReadOnly)
        {
            return new TreeScrollRecord(
                before, requested, before.Value, before.Value,
                "provider_rejected_read_only_range");
        }
        double observed = WaitForTreeRangeValue(root, process, index, requested);
        tree = WaitForNamedElement(root, process, TreeLabel, index);
        ((RangeValuePattern)tree.GetCurrentPattern(
            RangeValuePattern.Pattern)).SetValue(before.Value);
        double restored = WaitForTreeRangeValue(
            root, process, index, before.Value);
        return new TreeScrollRecord(before, requested, observed, restored, "operated");
    }

    private static ExpandCollapsePattern GetExpandCollapsePattern(
        AutomationElement element, int index, string name)
    {
        if (!element.TryGetCurrentPattern(
                ExpandCollapsePattern.Pattern, out object pattern) ||
            pattern is not ExpandCollapsePattern expandCollapse)
        {
            throw new InvalidOperationException(
                $"Session {index} {name} has no ExpandCollapse pattern.");
        }
        return expandCollapse;
    }

    private static ExpandCollapseState GetExpandCollapseState(
        AutomationElement element, int index, string name)
    {
        return GetExpandCollapsePattern(element, index, name)
            .Current.ExpandCollapseState;
    }

    private static ExpandCollapseState WaitForExpandCollapseState(
        AutomationElement root, Process process, int index,
        string name, ExpandCollapseState expected)
    {
        ExpandCollapseState observed = ExpandCollapseState.LeafNode;
        WaitFor(
            () =>
            {
                AutomationElement element = WaitForNamedControl(
                    root, process, name, ControlType.TreeItem, index);
                observed = GetExpandCollapseState(element, index, name);
                return observed == expected;
            },
            process,
            TimeSpan.FromSeconds(5),
            $"Session {index} {name} did not reach {expected}.");
        return observed;
    }

    private static double WaitForTreeRangeValue(
        AutomationElement root, Process process, int index, double expected)
    {
        double observed = double.NaN;
        WaitFor(
            () =>
            {
                AutomationElement tree = WaitForNamedElement(
                    root, process, TreeLabel, index);
                observed = GetRangeValue(tree, index);
                return Math.Abs(observed - expected) <= 0.001;
            },
            process,
            TimeSpan.FromSeconds(5),
            $"Session {index} Tree scroll did not reach {expected}.");
        return observed;
    }

    private static string[] WaitForTreeTopology(
        AutomationElement root, Process process, int index,
        string required, string absent)
    {
        string[] observed = [];
        WaitFor(
            () =>
            {
                AutomationElement tree = WaitForNamedElement(
                    root, process, TreeLabel, index);
                observed = tree.FindAll(
                        TreeScope.Descendants, Condition.TrueCondition)
                    .Cast<AutomationElement>()
                    .Take(256)
                    .Select(element => element.Current.Name)
                    .ToArray();
                return observed.Contains(required) && !observed.Contains(absent);
            },
            process,
            TimeSpan.FromSeconds(5),
            $"Session {index} Tree topology did not include {required} " +
            $"and remove {absent}.");
        return observed;
    }

    private static RetainedElementRecord ProbeRetainedTreeItem(
        AutomationElement root, AutomationElement element,
        string removedName, int index)
    {
        bool propertyAvailable = false;
        bool actionRejected = false;
        try
        {
            _ = element.Current.Name;
            propertyAvailable = true;
        }
        catch (ElementNotAvailableException)
        {
            actionRejected = true;
        }
        if (propertyAvailable)
        {
            try
            {
                ExpandCollapsePattern pattern = GetExpandCollapsePattern(
                    element, index, removedName);
                if (pattern.Current.ExpandCollapseState == ExpandCollapseState.Expanded)
                {
                    pattern.Collapse();
                }
                else
                {
                    pattern.Expand();
                }
            }
            catch (ElementNotAvailableException)
            {
                actionRejected = true;
            }
            catch (InvalidOperationException)
            {
                actionRejected = true;
            }
        }
        AutomationElement tree = root.FindFirst(
            TreeScope.Descendants,
            new PropertyCondition(AutomationElement.NameProperty, TreeLabel));
        ElementRecord[] currentItems = tree is null
            ? []
            : tree.FindAll(TreeScope.Descendants, Condition.TrueCondition)
                .Cast<AutomationElement>()
                .Take(256)
                .Select(GetElementRecord)
                .ToArray();
        bool removedFromTree = !currentItems.Any(item => item.Name == removedName);
        if (!removedFromTree)
        {
            AutomationElement search = WaitForNamedElement(
                root, Process.GetProcessById(element.Current.ProcessId),
                SearchLabel, index);
            throw new InvalidOperationException(
                $"Session {index} stale {removedName} action changed current topology; " +
                $"search={GetSearchTextRecord(search, index).Value}, " +
                $"items=[{string.Join(", ", currentItems.Select(item =>
                    $"{item.Name}:{string.Join('.', item.RuntimeId)}"))}].");
        }
        return new RetainedElementRecord(
            propertyAvailable, actionRejected, removedFromTree);
    }

    private static void SetSearchValue(
        AutomationElement search, string value, int index)
    {
        if (!search.TryGetCurrentPattern(
                ValuePattern.Pattern, out object pattern) ||
            pattern is not ValuePattern valuePattern)
        {
            throw new InvalidOperationException(
                $"Session {index} Search has no Value pattern.");
        }
        valuePattern.SetValue(value);
    }

    private static SearchTextRecord WaitForSearchValue(
        AutomationElement root, Process process, int index, string expected)
    {
        SearchTextRecord observed = new("", "", "", [], []);
        WaitFor(
            () =>
            {
                AutomationElement search = WaitForNamedElement(
                    root, process, SearchLabel, index);
                observed = GetSearchTextRecord(search, index);
                return observed.Value == expected && observed.Text == expected;
            },
            process,
            TimeSpan.FromSeconds(5),
            $"Session {index} Search did not reach {expected}.");
        return observed;
    }

    private static void SelectSearchDocument(
        AutomationElement search, int index)
    {
        if (!search.TryGetCurrentPattern(
                TextPattern.Pattern, out object pattern) ||
            pattern is not TextPattern textPattern)
        {
            throw new InvalidOperationException(
                $"Session {index} Search has no Text pattern.");
        }
        textPattern.DocumentRange.Select();
    }

    private static void SelectSearchRange(
        AutomationElement search, int start, int end, int index)
    {
        if (!search.TryGetCurrentPattern(
                TextPattern.Pattern, out object pattern) ||
            pattern is not TextPattern textPattern)
        {
            throw new InvalidOperationException(
                $"Session {index} Search has no Text pattern.");
        }
        var range = textPattern.DocumentRange.Clone();
        var startBoundary = textPattern.DocumentRange.Clone();
        var endBoundary = textPattern.DocumentRange.Clone();
        int movedStart = startBoundary.MoveEndpointByUnit(
            TextPatternRangeEndpoint.Start, TextUnit.Character, start);
        int movedEnd = endBoundary.MoveEndpointByUnit(
            TextPatternRangeEndpoint.Start, TextUnit.Character, end);
        range.MoveEndpointByRange(
            TextPatternRangeEndpoint.Start,
            startBoundary,
            TextPatternRangeEndpoint.Start);
        range.MoveEndpointByRange(
            TextPatternRangeEndpoint.End,
            endBoundary,
            TextPatternRangeEndpoint.Start);
        if (start != end && range.GetText(-1) != MultibyteSearchQuery[start..end])
        {
            throw new InvalidOperationException(
                $"Session {index} UIA range construction mismatch: " +
                $"moved_start={movedStart}, moved_end={movedEnd}, " +
                $"text={range.GetText(-1)}.");
        }
        range.Select();
    }

    private static SearchTextRecord WaitForSearchSelection(
        AutomationElement root, Process process, int index,
        string expected, int expectedStart, int expectedEnd)
    {
        SearchTextRecord observed = new("", "", "", [], []);
        WaitFor(
            () =>
            {
                AutomationElement search = WaitForNamedElement(
                    root, process, SearchLabel, index);
                observed = GetSearchTextRecord(search, index);
                return observed.SelectionRanges.Any(selection =>
                    selection.Text == expected &&
                    selection.Start == expectedStart &&
                    selection.End == expectedEnd);
            },
            process,
            TimeSpan.FromSeconds(5),
            $"Session {index} Search selection did not reach {expected}; " +
            $"value={observed.Value}, ranges=[{string.Join(", ",
                observed.SelectionRanges.Select(selection =>
                    $"{selection.Text}:{selection.Start}-{selection.End}"))}].");
        return observed;
    }

    private static PartialTextSelectionRecord WaitForPartialSearchSelection(
        AutomationElement root, Process process, int index,
        SearchTextRecord before, string expected, int expectedStart,
        int expectedEnd)
    {
        SearchTextRecord observed = before;
        string outcome = "";
        var observation = Stopwatch.StartNew();
        WaitFor(
            () =>
            {
                AutomationElement search = WaitForNamedElement(
                    root, process, SearchLabel, index);
                observed = GetSearchTextRecord(search, index);
                if (observed.SelectionRanges.Any(selection =>
                        selection.Text == expected &&
                        selection.Start == expectedStart &&
                        selection.End == expectedEnd))
                {
                    outcome = "selected";
                    return true;
                }
                if (observed.Value != before.Value || observed.Text != before.Text)
                {
                    outcome = "provider_mutated_value";
                    return true;
                }
                bool rangeChanged = !observed.SelectionRanges.SequenceEqual(
                    before.SelectionRanges);
                if (rangeChanged)
                {
                    outcome = "provider_returned_different_range";
                    return true;
                }
                if (observation.Elapsed >= TimeSpan.FromMilliseconds(500))
                {
                    outcome = "provider_noop";
                    return true;
                }
                return false;
            },
            process,
            TimeSpan.FromSeconds(5),
            $"Session {index} partial Search selection was neither applied " +
            $"nor rejected with an observable value mutation; value={observed.Value}, " +
            $"text={observed.Text}, ranges=[{string.Join(", ",
                observed.SelectionRanges.Select(selection =>
                    $"{selection.Text}:{selection.Start}-{selection.End}"))}].");
        return new PartialTextSelectionRecord(
            expectedStart, expectedEnd, expected, before, observed, outcome);
    }

    private static SearchTextRecord GetSearchTextRecord(
        AutomationElement search, int index)
    {
        if (!search.TryGetCurrentPattern(
                ValuePattern.Pattern, out object valueObject) ||
            valueObject is not ValuePattern valuePattern ||
            !search.TryGetCurrentPattern(
                TextPattern.Pattern, out object textObject) ||
            textObject is not TextPattern textPattern)
        {
            throw new InvalidOperationException(
                $"Session {index} Search lacks Value or Text support.");
        }
        var document = textPattern.DocumentRange;
        var selections = textPattern.GetSelection();
        TextSelectionRecord[] ranges = selections
            .Select((_, selectionIndex) =>
                GetTextSelectionRecord(textPattern, selectionIndex))
            .ToArray();
        return new SearchTextRecord(
            valuePattern.Current.Value,
            document.GetText(-1),
            search.Current.HelpText,
            ranges.Select(range => range.Text).ToArray(),
            ranges);
    }

    private static TextSelectionRecord GetTextSelectionRecord(
        TextPattern textPattern, int selectionIndex)
    {
        var document = textPattern.DocumentRange;
        var selection = textPattern.GetSelection()[selectionIndex];
        var startPrefix = document.Clone();
        startPrefix.MoveEndpointByRange(
            TextPatternRangeEndpoint.End,
            selection,
            TextPatternRangeEndpoint.Start);
        var endPrefix = document.Clone();
        endPrefix.MoveEndpointByRange(
            TextPatternRangeEndpoint.End,
            selection,
            TextPatternRangeEndpoint.End);
        return new TextSelectionRecord(
            selection.GetText(-1),
            startPrefix.GetText(-1).Length,
            endPrefix.GetText(-1).Length);
    }

    private static AccordionRecord ExerciseSettings(
        AutomationElement root, Process process, int index)
    {
        AutomationElement header = WaitForNamedControl(
            root, process, SettingsLabel, ControlType.Button, index);
        ElementRecord before = GetElementRecord(header);
        string beforeState = GetExpandCollapseState(header, index).ToString();
        Expand(header, index);
        _ = WaitForNamedControl(
            root, process, CheckboxLabel, ControlType.CheckBox, index);
        AutomationElement expanded = WaitForNamedControl(
            root, process, SettingsLabel, ControlType.Button, index);
        ElementRecord after = GetElementRecord(expanded);
        string afterState = GetExpandCollapseState(expanded, index).ToString();
        AutomationElement panel = WaitForNamedControl(
            root, process, SettingsLabel, ControlType.Pane, index);
        ElementRecord panelRecord = GetElementRecord(panel);
        string[] controlledNames = ControllerForNames(expanded, out string relationType);
        bool controlsPanel = controlledNames.Contains(SettingsLabel);
        return new AccordionRecord(
            before, after, panelRecord, beforeState, afterState,
            controlsPanel, relationType, controlledNames);
    }

    private static ToggleActionRecord ExerciseCheckbox(
        AutomationElement root, Process process, int index)
    {
        AutomationElement checkbox = WaitForNamedControl(
            root, process, CheckboxLabel, ControlType.CheckBox, index);
        ToggleState before = GetToggleState(checkbox, index);
        ElementRecord record = GetElementRecord(checkbox);
        Toggle(checkbox, index);
        ToggleState toggled = WaitForToggleState(
            root, process, index, before == ToggleState.On ? ToggleState.Off : ToggleState.On);
        AutomationElement updated = WaitForNamedControl(
            root, process, CheckboxLabel, ControlType.CheckBox, index);
        if (!RuntimeIdentityEqual(record.RuntimeId, GetRuntimeId(updated)))
        {
            throw new InvalidOperationException(
                $"Session {index} Display FPS changed runtime identity.");
        }
        Toggle(updated, index);
        ToggleState restored = WaitForToggleState(root, process, index, before);
        return new ToggleActionRecord(record, before.ToString(), toggled.ToString(),
            restored.ToString(), 2);
    }

    private static RangeActionRecord ExerciseSlider(
        AutomationElement root, Process process, int index)
    {
        AutomationElement slider = WaitForNamedControl(
            root, process, SliderLabel, ControlType.Slider, index);
        if (!slider.TryGetCurrentPattern(
                RangeValuePattern.Pattern, out object pattern) ||
            pattern is not RangeValuePattern range)
        {
            throw new InvalidOperationException(
                $"Session {index} Maximum Dust slider has no RangeValue pattern.");
        }
        ElementRecord elementRecord = GetElementRecord(slider);
        RangeValuePattern.RangeValuePatternInformation initial = range.Current;
        bool isReadOnly = initial.IsReadOnly;
        double initialValue = initial.Value;
        double minimum = initial.Minimum;
        double maximum = initial.Maximum;
        double smallChange = initial.SmallChange;
        if (isReadOnly || !double.IsFinite(initialValue) ||
            !double.IsFinite(minimum) || !double.IsFinite(maximum) ||
            minimum > initialValue || initialValue > maximum)
        {
            throw new InvalidOperationException(
                $"Session {index} Maximum Dust exposed an incoherent range.");
        }

        double step = smallChange > 0 ? smallChange : 1;
        bool stepIncreases = initialValue + step <= maximum;
        double first = stepIncreases ? initialValue + step : initialValue - step;
        range.SetValue(first);
        double stepped = WaitForRangeValue(root, process, index, first);
        slider = WaitForNamedControl(root, process, SliderLabel, ControlType.Slider, index);
        range = (RangeValuePattern)slider.GetCurrentPattern(RangeValuePattern.Pattern);
        range.SetValue(initialValue);
        double returned = WaitForRangeValue(root, process, index, initialValue);

        double direct = minimum + (maximum - minimum) / 2;
        slider = WaitForNamedControl(root, process, SliderLabel, ControlType.Slider, index);
        range = (RangeValuePattern)slider.GetCurrentPattern(RangeValuePattern.Pattern);
        range.SetValue(direct);
        double directlySet = WaitForRangeValue(root, process, index, direct);

        bool exceptionRejected = false;
        slider = WaitForNamedControl(root, process, SliderLabel, ControlType.Slider, index);
        range = (RangeValuePattern)slider.GetCurrentPattern(RangeValuePattern.Pattern);
        try
        {
            range.SetValue(maximum + Math.Max(step, 1));
        }
        catch (ArgumentOutOfRangeException)
        {
            exceptionRejected = true;
        }
        catch (InvalidOperationException)
        {
            exceptionRejected = true;
        }
        slider = WaitForNamedControl(root, process, SliderLabel, ControlType.Slider, index);
        double afterInvalid = GetRangeValue(slider, index);
        bool ownerUnchanged = Math.Abs(afterInvalid - directlySet) <= 0.001;
        if (!ownerUnchanged)
        {
            throw new InvalidOperationException(
                $"Session {index} Maximum Dust accepted an out-of-range value.");
        }

        range.SetValue(initialValue);
        double restored = WaitForRangeValue(root, process, index, initialValue);
        AutomationElement finalSlider = WaitForNamedControl(
            root, process, SliderLabel, ControlType.Slider, index);
        if (!RuntimeIdentityEqual(elementRecord.RuntimeId, GetRuntimeId(finalSlider)))
        {
            throw new InvalidOperationException(
                $"Session {index} Maximum Dust changed runtime identity.");
        }
        return new RangeActionRecord(
            elementRecord, minimum, maximum, initialValue, step,
            stepIncreases ? "increment" : "decrement", stepped, returned, directlySet,
            exceptionRejected ? "provider_exception" : "owner_unchanged",
            afterInvalid, restored);
    }

    private static GifIdleRecord ExerciseGifIdle(
        AutomationElement root, Process process, int index)
    {
        AutomationElement header = root.FindAll(
                TreeScope.Descendants,
                new PropertyCondition(AutomationElement.NameProperty, GifHeaderLabel))
            .Cast<AutomationElement>()
            .First(element => element.TryGetCurrentPattern(
                ExpandCollapsePattern.Pattern, out _));
        ExpandNamedHeader(header, index, GifHeaderLabel);
        AutomationElement status = WaitForNamedElement(
            root, process, GifStatusLabel, index);
        AutomationElement capture = WaitForPatternElement(
            root, process, GifHeaderLabel, InvokePattern.Pattern, index);
        if (!capture.Current.IsEnabled)
        {
            throw new InvalidOperationException(
                $"Session {index} idle Save GIF action was disabled.");
        }
        return new GifIdleRecord(
            Header: GetElementRecord(header),
            CaptureButton: GetElementRecord(capture),
            Status: GetElementRecord(status),
            Downsample: GetRangeFacts(WaitForNamedControl(
                root, process, "Downsample", ControlType.Slider, index), index),
            CaptureEvery: GetRangeFacts(WaitForNamedControl(
                root, process, "Capture every", ControlType.Slider, index), index),
            AnimationTiming: GetElementRecord(WaitForNamedControl(
                root, process, "Use animation timing", ControlType.Button, index)),
            RecordedTiming: GetElementRecord(WaitForNamedControl(
                root, process, "Use recorded timing", ControlType.Button, index)));
    }

    private static RangeFactsRecord GetRangeFacts(
        AutomationElement element, int index)
    {
        if (!element.TryGetCurrentPattern(
                RangeValuePattern.Pattern, out object pattern) ||
            pattern is not RangeValuePattern range)
        {
            throw new InvalidOperationException(
                $"Session {index} {element.Current.Name} has no RangeValue pattern.");
        }
        RangeValuePattern.RangeValuePatternInformation current = range.Current;
        return new RangeFactsRecord(
            GetElementRecord(element), current.Minimum, current.Maximum,
            current.Value, current.SmallChange, current.LargeChange,
            current.IsReadOnly);
    }

    private static AutomationElement WaitForNamedControl(
        AutomationElement root, Process process, string name,
        ControlType controlType, int index)
    {
        var condition = new AndCondition(
            new PropertyCondition(AutomationElement.NameProperty, name),
            new PropertyCondition(AutomationElement.ControlTypeProperty, controlType));
        return WaitForElement(
            () => root.FindFirst(TreeScope.Descendants, condition),
            process,
            TimeSpan.FromSeconds(20),
            $"Session {index} did not expose {name} as {controlType.ProgrammaticName}.");
    }

    private static AutomationElement WaitForNamedElement(
        AutomationElement root, Process process, string name, int index)
    {
        var condition = new PropertyCondition(AutomationElement.NameProperty, name);
        return WaitForElement(
            () => root.FindFirst(TreeScope.Descendants, condition),
            process,
            TimeSpan.FromSeconds(20),
            $"Session {index} did not expose {name} through UIA.");
    }

    private static AutomationElement WaitForPatternElement(
        AutomationElement root, Process process, string name,
        AutomationPattern requiredPattern, int index)
    {
        return WaitForElement(
            () => root.FindAll(
                    TreeScope.Descendants,
                    new PropertyCondition(AutomationElement.NameProperty, name))
                .Cast<AutomationElement>()
                .FirstOrDefault(element => element.TryGetCurrentPattern(
                    requiredPattern, out _)),
            process,
            TimeSpan.FromSeconds(20),
            $"Session {index} did not expose {name} with {requiredPattern.ProgrammaticName}.");
    }

    private static void Invoke(AutomationElement element, string description)
    {
        if (!element.TryGetCurrentPattern(
                InvokePattern.Pattern, out object pattern) ||
            pattern is not InvokePattern invoke)
        {
            throw new InvalidOperationException($"{description} has no Invoke pattern.");
        }
        invoke.Invoke();
    }

    private static void Toggle(AutomationElement element, int index)
    {
        if (!element.TryGetCurrentPattern(
                TogglePattern.Pattern, out object pattern) ||
            pattern is not TogglePattern toggle)
        {
            throw new InvalidOperationException(
                $"Session {index} Display FPS has no Toggle pattern.");
        }
        toggle.Toggle();
    }

    private static void Expand(AutomationElement element, int index)
    {
        ExpandNamedHeader(element, index, SettingsLabel);
    }

    private static void ExpandNamedHeader(
        AutomationElement element, int index, string name)
    {
        if (!element.TryGetCurrentPattern(
                ExpandCollapsePattern.Pattern, out object pattern) ||
            pattern is not ExpandCollapsePattern expandCollapse)
        {
            throw new InvalidOperationException(
                $"Session {index} {name} header has no ExpandCollapse pattern.");
        }
        expandCollapse.Expand();
    }

    private static ExpandCollapseState GetExpandCollapseState(
        AutomationElement element, int index)
    {
        if (!element.TryGetCurrentPattern(
                ExpandCollapsePattern.Pattern, out object pattern) ||
            pattern is not ExpandCollapsePattern expandCollapse)
        {
            throw new InvalidOperationException(
                $"Session {index} Settings header has no ExpandCollapse pattern.");
        }
        return expandCollapse.Current.ExpandCollapseState;
    }

    private static ToggleState GetToggleState(AutomationElement element, int index)
    {
        if (!element.TryGetCurrentPattern(
                TogglePattern.Pattern, out object pattern) ||
            pattern is not TogglePattern toggle)
        {
            throw new InvalidOperationException(
                $"Session {index} Display FPS has no Toggle pattern.");
        }
        return toggle.Current.ToggleState;
    }

    private static ToggleState WaitForToggleState(
        AutomationElement root, Process process, int index, ToggleState expected)
    {
        ToggleState observed = ToggleState.Indeterminate;
        WaitFor(
            () =>
            {
                AutomationElement element = WaitForNamedControl(
                    root, process, CheckboxLabel, ControlType.CheckBox, index);
                observed = GetToggleState(element, index);
                return observed == expected;
            },
            process,
            TimeSpan.FromSeconds(5),
            $"Session {index} Display FPS did not reach {expected}.");
        return observed;
    }

    private static double WaitForRangeValue(
        AutomationElement root, Process process, int index, double expected)
    {
        double observed = double.NaN;
        WaitFor(
            () =>
            {
                AutomationElement element = WaitForNamedControl(
                    root, process, SliderLabel, ControlType.Slider, index);
                observed = GetRangeValue(element, index);
                return Math.Abs(observed - expected) <= 0.001;
            },
            process,
            TimeSpan.FromSeconds(5),
            $"Session {index} Maximum Dust did not reach {expected}.");
        return observed;
    }

    private static double GetRangeValue(AutomationElement element, int index)
    {
        if (!element.TryGetCurrentPattern(
                RangeValuePattern.Pattern, out object pattern) ||
            pattern is not RangeValuePattern range)
        {
            throw new InvalidOperationException(
                $"Session {index} Maximum Dust has no RangeValue pattern.");
        }
        return range.Current.Value;
    }

    private static string[] GetChildNames(AutomationElement root)
    {
        return root.FindAll(TreeScope.Children, Condition.TrueCondition)
            .Cast<AutomationElement>()
            .Select(element => element.Current.Name)
            .ToArray();
    }

    private static string[] ControllerForNames(
        AutomationElement element, out string relationType)
    {
        object value = element.GetCurrentPropertyValue(
            AutomationElementIdentifiers.ControllerForProperty,
            ignoreDefaultValue: true);
        relationType = value?.GetType().FullName ?? "null";
        if (value is AutomationElement target)
        {
            return [target.Current.Name];
        }
        if (value is AutomationElement[] targets)
        {
            return targets.Select(candidate => candidate.Current.Name).ToArray();
        }
        if (value is AutomationElementCollection collection)
        {
            return collection.Cast<AutomationElement>()
                .Select(candidate => candidate.Current.Name)
                .ToArray();
        }
        return [];
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
            RuntimeId: GetRuntimeId(element),
            Patterns: element.GetSupportedPatterns()
                .Select(pattern => pattern.ProgrammaticName)
                .OrderBy(name => name)
                .ToArray(),
            Orientation: element.Current.Orientation.ToString(),
            Enabled: element.Current.IsEnabled,
            KeyboardFocusable: element.Current.IsKeyboardFocusable,
            HasKeyboardFocus: element.Current.HasKeyboardFocus,
            Bounds: new BoundsRecord(
                X: bounds.X,
                Y: bounds.Y,
                Width: bounds.Width,
                Height: bounds.Height));
    }

    private static int[] GetRuntimeId(AutomationElement element)
    {
        return element.GetRuntimeId() ?? [];
    }

    private static bool RuntimeIdentityEqual(int[] left, int[] right)
    {
        return left.SequenceEqual(right);
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
    int[] RuntimeId,
    string[] Patterns,
    string Orientation,
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
    string[] InitialChildren,
    LibrarySnapshotRecord Library,
    SearchActionRecord Search,
    TreeInteractionRecord TreeInteraction,
    TreeFilterRecord TreeFilter,
    ButtonActionRecord PauseButton,
    RangeFactsRecord VerticalSplitter,
    RangeFactsRecord HorizontalSplitter,
    AccordionRecord Settings,
    ToggleActionRecord Checkbox,
    RangeActionRecord Slider,
    GifIdleRecord Gif,
    bool FocusGain,
    bool FocusLoss,
    int InvokeCount,
    bool ResetObserved,
    int ExitCode,
    bool ProviderRemoved);

internal sealed record LibrarySnapshotRecord(
    ElementRecord Search,
    ElementRecord Tree,
    ElementRecord[] Descendants);

internal sealed record SearchActionRecord(
    ElementRecord Element,
    SearchTextRecord Initial,
    SearchTextRecord Multibyte,
    SearchTextRecord Collapsed,
    PartialTextSelectionRecord PartialSelection,
    SearchTextRecord Filtered,
    SearchTextRecord Selected);

internal sealed record PartialTextSelectionRecord(
    int RequestedStart,
    int RequestedEnd,
    string ExpectedText,
    SearchTextRecord Before,
    SearchTextRecord After,
    string Outcome);

internal sealed record SearchTextRecord(
    string Value,
    string Text,
    string HelpText,
    string[] Selections,
    TextSelectionRecord[] SelectionRanges);

internal sealed record TextSelectionRecord(
    string Text,
    int Start,
    int End);

internal sealed record TreeInteractionRecord(
    ElementRecord Branch,
    string InitialState,
    string RestoredState,
    string[] TopLevelChildren,
    string[] ExpandedChildren,
    bool Selected,
    RangeFactsRecord RangeBefore,
    double RequestedScrollValue,
    double ObservedScrollValue);

internal sealed record TreeFilterRecord(
    string[] FilteredNames,
    string[] RetirementNames,
    string[] RestoredNames,
    bool SurvivingIdentityContinuous,
    TreeScrollRecord Scroll,
    RetainedElementRecord FirstRetired,
    RetainedElementRecord SurvivorRetired,
    bool RetiredIdWasNotReused,
    SearchTextRecord RetirementText,
    SearchTextRecord RestoredText);

internal sealed record TreeScrollRecord(
    RangeFactsRecord Before,
    double Requested,
    double Observed,
    double Restored,
    string Outcome);

internal sealed record RetainedElementRecord(
    bool PropertyAvailable,
    bool ActionRejected,
    bool RemovedFromTree);

internal sealed record ButtonActionRecord(
    ElementRecord Before,
    ElementRecord Invoked,
    ElementRecord Restored,
    int InvokeCount);

internal sealed record AccordionRecord(
    ElementRecord Before,
    ElementRecord After,
    ElementRecord Panel,
    string BeforeState,
    string AfterState,
    bool ControlsPanel,
    string RelationValueType,
    string[] ControlledNames);

internal sealed record ToggleActionRecord(
    ElementRecord Element,
    string Before,
    string Toggled,
    string Restored,
    int ToggleCount);

internal sealed record RangeActionRecord(
    ElementRecord Element,
    double Minimum,
    double Maximum,
    double Initial,
    double Step,
    string StepDirection,
    double Stepped,
    double Returned,
    double DirectlySet,
    string OutOfRangeRejection,
    double AfterInvalid,
    double Restored);

internal sealed record RangeFactsRecord(
    ElementRecord Element,
    double Minimum,
    double Maximum,
    double Value,
    double SmallChange,
    double LargeChange,
    bool IsReadOnly);

internal sealed record GifIdleRecord(
    ElementRecord Header,
    ElementRecord CaptureButton,
    ElementRecord Status,
    RangeFactsRecord Downsample,
    RangeFactsRecord CaptureEvery,
    ElementRecord AnimationTiming,
    ElementRecord RecordedTiming);

internal sealed record Report(
    int SchemaVersion,
    string Platform,
    string OperatingSystem,
    string Architecture,
    string AccessKitWindowsVersion,
    string AutomatedScope,
    string Result,
    string[] Limitations,
    int SessionCount,
    bool RepeatedTeardown,
    SessionRecord[] Sessions);
