namespace YMM4SandSim.Tests;

public sealed class ShaderBytecodeTests
{
    [Fact]
    public void LoadIsSafeForParallelCalls()
    {
        var bytecodes = Enumerable.Range(0, 32)
            .AsParallel()
            .Select(_ => ShaderBytecode.Load("SandInitialize"))
            .ToArray();

        Assert.All(bytecodes, bytecode =>
        {
            Assert.True(bytecode.Length >= 4);
            Assert.Equal("DXBC"u8.ToArray(), bytecode[..4]);
        });
    }
}
