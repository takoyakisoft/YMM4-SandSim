namespace YMM4SandSim;

/// <summary>
/// Snapshot mode keeps the extraction rectangle stable while YMM4 evaluates
/// the same frame repeatedly or advances sequentially. A seek/jump starts a
/// new snapshot and is allowed to capture new input geometry.
/// </summary>
internal static class SandSnapshotGeometryPolicy
{
    public static bool CanReuse(
        SandSourceMode sourceMode,
        bool hasSnapshotGeometry,
        bool isFirst,
        long frame,
        long lastFrame)
    {
        if (sourceMode != SandSourceMode.Snapshot || !hasSnapshotGeometry)
            return false;

        return SandTimelinePolicy.Classify(isFirst, frame, lastFrame) ==
               SandTimelineAccessKind.Continuous;
    }
}
