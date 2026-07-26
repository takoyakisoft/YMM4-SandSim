namespace YMM4SandSim;

internal static class SandExplosionTriggerPolicy
{
    public static bool ShouldTrigger(
        bool enabled,
        int triggerFrame,
        long frame,
        long lastFrame,
        bool isFirst,
        bool reset)
    {
        if (!enabled || triggerFrame < 0 || frame < triggerFrame)
            return false;

        // Re-seed on a state reset so seeking or editing the controller after
        // the trigger frame rebuilds a visible deterministic blast instead of
        // leaving the pressure field in a stale pre-edit state.
        if (isFirst || reset)
            return true;

        return lastFrame < triggerFrame;
    }
}
