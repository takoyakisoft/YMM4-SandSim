using System.IO;

namespace YMM4SandSim;

internal static class ShaderBytecode
{
    private const string ResourcePrefix = "YMM4SandSim.Shaders.";

    public static byte[] Load(string shaderName)
    {
        using var stream = typeof(ShaderBytecode).Assembly.GetManifestResourceStream(
            ResourcePrefix + shaderName + ".cso")
            ?? throw new InvalidOperationException($"Shader resource was not found: {shaderName}");

        if (stream.Length <= 0 || stream.Length > int.MaxValue)
            throw new InvalidDataException($"Invalid shader resource length: {shaderName}");

        var bytes = GC.AllocateUninitializedArray<byte>((int)stream.Length);
        stream.ReadExactly(bytes);
        return bytes;
    }
}
