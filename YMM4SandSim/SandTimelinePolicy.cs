namespace YMM4SandSim;

internal enum SandTimelineAccessKind
{
    Initial,
    Continuous,
    Random,
}

/// <summary>
/// Classifies YMM4's access to the stateful simulation and determines whether
/// the existing GPU state can be reused.
/// </summary>
internal static class SandTimelinePolicy
{
    public static bool ExtractionDefinesPersistentState(SandSourceMode sourceMode)
        => sourceMode == SandSourceMode.Snapshot;

    public static SandTimelineAccessKind Classify(
        bool isFirst,
        long frame,
        long lastFrame)
    {
        if (isFirst)
            return SandTimelineAccessKind.Initial;

        if (frame == lastFrame ||
            (lastFrame != long.MaxValue && frame == lastFrame + 1))
        {
            return SandTimelineAccessKind.Continuous;
        }

        return SandTimelineAccessKind.Random;
    }

    public static Decision Decide(
        bool isFirst,
        long frame,
        long lastFrame,
        bool resourcesChanged,
        bool stateKeyChanged,
        bool simulationParametersChanged,
        SandSourceMode sourceMode)
    {
        var accessKind = Classify(isFirst, frame, lastFrame);
        var sameFrame = accessKind == SandTimelineAccessKind.Continuous &&
                        frame == lastFrame;

        var sameFrameParameterReset = sameFrame && simulationParametersChanged;
        var reset = resourcesChanged ||
                    accessKind is SandTimelineAccessKind.Initial or SandTimelineAccessKind.Random ||
                    stateKeyChanged || sameFrameParameterReset;

        // Source modes inject once per timeline frame, not once per YMM render
        // evaluation. A single frame may be evaluated repeatedly by the editor or
        // exporter; advancing AddEveryFrame again would make the state depend on
        // evaluation count instead of frame index. A same-frame parameter change
        // still resets explicitly above because the old output is no longer valid.
        var needsInput = reset || (!sameFrame && sourceMode != SandSourceMode.Snapshot);
        var needsAdvance = !sameFrame || reset;

        return new Decision(
            AccessKind: accessKind,
            SameFrame: sameFrame,
            Reset: reset,
            NeedsInput: needsInput,
            NeedsAdvance: needsAdvance);
    }

    internal readonly record struct Decision(
        SandTimelineAccessKind AccessKind,
        bool SameFrame,
        bool Reset,
        bool NeedsInput,
        bool NeedsAdvance);
}
