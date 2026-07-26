using System.Globalization;
using YukkuriMovieMaker.Plugin;

namespace YMM4SandSim.Localization;

public sealed class TranslateLocalizePlugin : ILocalizePlugin
{
    public string Name => Translate.Plugin_Name;

    public void SetCulture(CultureInfo cultureInfo)
    {
        Translate.Culture = cultureInfo;
    }
}
