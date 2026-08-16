using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;

namespace YMM4SandSim.Diagnostics;

internal enum PluginLogLevel
{
    Debug,
    Information,
    Warning,
    Error,
}

internal static class PluginLog
{
    private const long MaximumFileBytes = 2 * 1024 * 1024;
    private const long RetainedFileBytes = 1024 * 1024;
    private const int MaximumMessageCharacters = 32 * 1024;
    private const string PluginName = "YMM4SandSim";
    private const string LogFileName = $"{PluginName}.log";
    private const string LogLevelEnvironmentVariable = "YMM4SANDSIM_LOG_LEVEL";

    private static readonly Lock InitializationSync = new();
    private static bool _initialized;
    private static BoundedLogFile? _file;
    private static PluginLogLevel _minimumLevel;

    internal static string? FilePath => _file?.Path;

    internal static void Initialize()
    {
        if (Volatile.Read(ref _initialized))
            return;

        lock (InitializationSync)
        {
            if (_initialized)
                return;

            try
            {
                var assembly = typeof(PluginLog).Assembly;
                var pluginDirectory = Path.GetDirectoryName(assembly.Location) ?? AppContext.BaseDirectory;
                _file = new BoundedLogFile(
                    Path.Combine(pluginDirectory, LogFileName),
                    MaximumFileBytes,
                    RetainedFileBytes);
                _minimumLevel = ResolveMinimumLevel();

                var versionInfo = FileVersionInfo.GetVersionInfo(assembly.Location);
                var informationalVersion =
                    assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion ??
                    string.Empty;
                var message =
                    $"{PluginName} support metadata. " +
                    $"assemblyVersion={assembly.GetName().Version}, " +
                    $"fileVersion={versionInfo.FileVersion}, " +
                    $"informationalVersion={informationalVersion}, " +
                    $"processArchitecture={RuntimeInformation.ProcessArchitecture}, " +
                    $"assemblyPath={assembly.Location}, " +
                    $"configuredLogLevel={_minimumLevel}";

                // Always keep one startup record. Release filters all subsequent
                // non-error diagnostics, while Debug retains lifecycle details.
                WriteCore(PluginLogLevel.Information, message, null, bypassMinimumLevel: true);
            }
            catch (IOException)
            {
                _file = null;
            }
            catch (UnauthorizedAccessException)
            {
                _file = null;
            }
            catch (System.Security.SecurityException)
            {
                _file = null;
            }
            catch (ArgumentException)
            {
                _file = null;
            }
            catch (NotSupportedException)
            {
                _file = null;
            }
            catch (InvalidOperationException)
            {
                _file = null;
            }
            finally
            {
                Volatile.Write(ref _initialized, true);
            }
        }
    }

    internal static bool IsEnabled(PluginLogLevel level)
    {
        EnsureInitialized();
        return _file != null && level >= _minimumLevel;
    }

    internal static void Debug(string message) => Write(PluginLogLevel.Debug, message, null);

    internal static void Information(string message) => Write(PluginLogLevel.Information, message, null);

    internal static void Warning(string message, Exception? exception = null) =>
        Write(PluginLogLevel.Warning, message, exception);

    internal static void Error(string message, Exception? exception = null) =>
        Write(PluginLogLevel.Error, message, exception);

    internal static string FormatLine(
        DateTimeOffset timestamp,
        PluginLogLevel level,
        string message,
        Exception? exception)
    {
        var builder = new StringBuilder();
        builder.Append(timestamp.ToString("yyyy-MM-dd HH:mm:ss.fff", CultureInfo.InvariantCulture));
        builder.Append(' ');
        builder.Append(ToLevelText(level));
        builder.Append(' ');
        builder.Append(PluginName);
        builder.Append(' ');
        AppendClean(builder, message);

        if (exception != null)
        {
            builder.Append(level >= PluginLogLevel.Error ? ", exceptionDetail " : ", exception ");
            AppendClean(builder, level >= PluginLogLevel.Error ? exception.ToString() : exception.Message);
        }

        builder.Append('.');
        return builder.Length <= MaximumMessageCharacters
            ? builder.ToString()
            : string.Concat(builder.ToString(0, MaximumMessageCharacters - 4), "...");
    }

    private static void Write(PluginLogLevel level, string message, Exception? exception)
    {
        EnsureInitialized();
        WriteCore(level, message, exception);
    }

    private static void WriteCore(
        PluginLogLevel level,
        string message,
        Exception? exception,
        bool bypassMinimumLevel = false)
    {
        if (_file == null || (!bypassMinimumLevel && level < _minimumLevel))
            return;

        try
        {
            _file.WriteLine(FormatLine(DateTimeOffset.Now, level, message, exception));
        }
        catch (IOException)
        {
            // Diagnostics must never affect rendering or plugin loading.
        }
        catch (UnauthorizedAccessException)
        {
            // Diagnostics must never affect rendering or plugin loading.
        }
        catch (System.Security.SecurityException)
        {
            // Diagnostics must never affect rendering or plugin loading.
        }
        catch (ArgumentException)
        {
            // Diagnostics must never affect rendering or plugin loading.
        }
        catch (NotSupportedException)
        {
            // Diagnostics must never affect rendering or plugin loading.
        }
        catch (InvalidOperationException)
        {
            // Diagnostics must never affect rendering or plugin loading.
        }
    }

    private static void EnsureInitialized()
    {
        if (!Volatile.Read(ref _initialized))
            Initialize();
    }

    private static PluginLogLevel ResolveMinimumLevel()
    {
        // Keep Release quiet by default, but let support/performance sessions
        // explicitly opt in without requiring a Debug plugin build.
        var configured = Environment.GetEnvironmentVariable(LogLevelEnvironmentVariable);
        if (Enum.TryParse<PluginLogLevel>(configured, ignoreCase: true, out var parsed))
            return parsed;

#if DEBUG
        return PluginLogLevel.Information;
#else
        return PluginLogLevel.Error;
#endif
    }

    private static string ToLevelText(PluginLogLevel level) => level switch
    {
        PluginLogLevel.Debug => "debug",
        PluginLogLevel.Information => "info",
        PluginLogLevel.Warning => "warn",
        PluginLogLevel.Error => "error",
        _ => "info",
    };

    private static void AppendClean(StringBuilder builder, string text)
    {
        foreach (var character in text)
        {
            builder.Append(character switch
            {
                '{' or '}' or '[' or ']' or '"' or '\r' or '\n' or '\t' => ' ',
                _ => character,
            });
        }
    }
}
