namespace YMM4SandSim.Tests;

public sealed class ExplosionTriggerPolicyTests
{
    [Theory]
    [InlineData(false, 10, 10, 9, false, false, false)]
    [InlineData(true, 10, 9, 8, false, false, false)]
    [InlineData(true, 10, 10, 9, false, false, true)]
    [InlineData(true, 10, 10, 10, false, false, false)]
    [InlineData(true, 10, 11, 10, false, false, false)]
    [InlineData(true, 10, 30, 12, false, true, true)]
    [InlineData(true, 0, 0, long.MinValue, true, true, true)]
    public void TriggerDecisionIsDeterministic(
        bool enabled,
        int triggerFrame,
        long frame,
        long lastFrame,
        bool isFirst,
        bool reset,
        bool expected)
        => Assert.Equal(
            expected,
            SandExplosionTriggerPolicy.ShouldTrigger(
                enabled,
                triggerFrame,
                frame,
                lastFrame,
                isFirst,
                reset));
}
