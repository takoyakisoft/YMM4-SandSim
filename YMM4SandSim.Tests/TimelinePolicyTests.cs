namespace YMM4SandSim.Tests;

public sealed class TimelinePolicyTests
{
    [Fact]
    public void SnapshotExtractionDefinesPersistentState()
    {
        Assert.True(SandTimelinePolicy.ExtractionDefinesPersistentState(SandSourceMode.Snapshot));
        Assert.False(SandTimelinePolicy.ExtractionDefinesPersistentState(SandSourceMode.ContinuousEmitter));
        Assert.False(SandTimelinePolicy.ExtractionDefinesPersistentState(SandSourceMode.AddEveryFrame));
    }

    [Fact]
    public void FirstFrameInitializesSimulation()
    {
        var decision = Decide(true, 0, long.MinValue, SandSourceMode.Snapshot);

        Assert.Equal(SandTimelineAccessKind.Initial, decision.AccessKind);
        Assert.True(decision.Reset);
        Assert.True(decision.NeedsInput);
        Assert.True(decision.NeedsAdvance);
    }

    [Fact]
    public void SameFrameDoesNotDoubleAdvanceAddEveryFrame()
    {
        var decision = Decide(false, 10, 10, SandSourceMode.AddEveryFrame);

        Assert.Equal(SandTimelineAccessKind.Continuous, decision.AccessKind);
        Assert.True(decision.SameFrame);
        Assert.False(decision.Reset);
        Assert.False(decision.NeedsInput);
        Assert.False(decision.NeedsAdvance);
    }

    [Fact]
    public void SequentialFrameAdvancesOnce()
    {
        var snapshot = Decide(false, 11, 10, SandSourceMode.Snapshot);
        var addEveryFrame = Decide(false, 11, 10, SandSourceMode.AddEveryFrame);

        Assert.Equal(SandTimelineAccessKind.Continuous, snapshot.AccessKind);
        Assert.False(snapshot.Reset);
        Assert.False(snapshot.NeedsInput);
        Assert.True(snapshot.NeedsAdvance);
        Assert.Equal(SandTimelineAccessKind.Continuous, addEveryFrame.AccessKind);
        Assert.False(addEveryFrame.Reset);
        Assert.True(addEveryFrame.NeedsInput);
        Assert.True(addEveryFrame.NeedsAdvance);
    }

    [Theory]
    [InlineData(30, 10)]
    [InlineData(5, 10)]
    public void RandomAccessResetsFromCurrentInput(long frame, long lastFrame)
    {
        var decision = Decide(false, frame, lastFrame, SandSourceMode.Snapshot);

        Assert.Equal(SandTimelineAccessKind.Random, decision.AccessKind);
        Assert.True(decision.Reset);
        Assert.True(decision.NeedsInput);
        Assert.True(decision.NeedsAdvance);
    }

    [Fact]
    public void SameFrameParameterChangeInvalidatesWithoutChangingAccessKind()
    {
        var decision = SandTimelinePolicy.Decide(
            false,
            10,
            10,
            false,
            false,
            true,
            SandSourceMode.Snapshot);

        Assert.Equal(SandTimelineAccessKind.Continuous, decision.AccessKind);
        Assert.True(decision.SameFrame);
        Assert.True(decision.Reset);
        Assert.True(decision.NeedsInput);
        Assert.True(decision.NeedsAdvance);
    }

    [Fact]
    public void MaximumFrameDoesNotWrapIntoContinuousAccess()
    {
        var accessKind = SandTimelinePolicy.Classify(
            false,
            long.MinValue,
            long.MaxValue);

        Assert.Equal(SandTimelineAccessKind.Random, accessKind);
    }

    private static SandTimelinePolicy.Decision Decide(
        bool first,
        long frame,
        long lastFrame,
        SandSourceMode mode)
        => SandTimelinePolicy.Decide(first, frame, lastFrame, false, false, false, mode);
}
