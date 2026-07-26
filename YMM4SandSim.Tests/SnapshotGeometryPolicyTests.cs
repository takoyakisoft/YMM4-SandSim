namespace YMM4SandSim.Tests;

public sealed class SnapshotGeometryPolicyTests
{
    [Theory]
    [InlineData(SandSourceMode.Snapshot, false, true, 0, long.MinValue, false)]
    [InlineData(SandSourceMode.Snapshot, true, false, 10, 10, true)]
    [InlineData(SandSourceMode.Snapshot, true, false, 11, 10, true)]
    [InlineData(SandSourceMode.Snapshot, true, false, 30, 10, false)]
    [InlineData(SandSourceMode.ContinuousEmitter, true, false, 11, 10, false)]
    public void SnapshotGeometryReuseFollowsTimeline(
        SandSourceMode mode,
        bool hasGeometry,
        bool isFirst,
        long frame,
        long lastFrame,
        bool expected)
        => Assert.Equal(
            expected,
            SandSnapshotGeometryPolicy.CanReuse(
                mode,
                hasGeometry,
                isFirst,
                frame,
                lastFrame));
}
