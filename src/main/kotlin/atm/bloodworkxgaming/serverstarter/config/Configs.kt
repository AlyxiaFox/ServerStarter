package atm.bloodworkxgaming.serverstarter.config

import atm.bloodworkxgaming.serverstarter.ServerStarter
import java.util.*

/**
 * Logs without assuming [ServerStarter] finished initialising, since this runs while its
 * companion object is still being constructed.
 */
private fun warn(message: String) {
    try {
        ServerStarter.LOGGER.warn(message)
    } catch (t: Throwable) {
        System.err.println("[WARNING] $message")
    }
}

/**
 * Replaces `${ENV_VAR}` references with the matching environment variable.
 *
 * An unset variable resolves to an empty string instead of aborting. This runs against
 * curseForgeApiKey during config load for every pack format, so throwing here meant a zip pack
 * that never touches CurseForge still refused to start whenever the shipped
 * `${CURSE_FORGE_API_KEY}` default was left in place, and it surfaced as an unexplained
 * "Failed to load Yaml" with the real cause buried in the stack trace.
 */
fun processString(s: String): String {
        var str = s
        val regex = Regex("\\\$\\{(.+)}")
        for (matchResult in regex.findAll(str)) {
            val res = matchResult.groupValues.getOrNull(0) ?: continue
            val inner = matchResult.groupValues.getOrNull(1) ?: continue

            val value = System.getenv(inner)
            if (value == null) {
                warn("The environment variable '$inner' is not set, substituting an empty string.")
            }

            str = str.replace(res, value ?: "")
        }

        return str

}

data class AdditionalFile(
    var url: String = "",
    var destination: String = ""
)

data class LocalFile(
    var from: String = "",
    var to: String = ""
)

data class ModpackConfig(
    var name: String = "",
    var description: String = ""
)

data class LaunchSettings(
    var spongefix: Boolean = false,
    var ramDisk: Boolean = false,
    var checkOffline: Boolean = false,
    var checkUrls: List<String> = Collections.emptyList(),
    var maxRam: String = "",
    var minRam: String = "",

    var startFile: String = "",
    var startCommand: List<String> = Collections.emptyList(),
    var javaArgs: List<String> = Collections.emptyList(),
    var autoRestart: Boolean = false,
    var crashLimit: Int = 0,
    var crashTimer: String = "",
    var preJavaArgs: String = "",

    var forcedJavaPath: String = "",

    var supportedJavaVersions: List<String> = Collections.emptyList()

    ) {
    val processedForcedJavaPath: String
        get() = processString(forcedJavaPath)
}

data class InstallConfig(
    var curseForgeApiKey: String = "",

    var mcVersion: String = "",

    var loaderVersion: String = "",
    var installerUrl: String = "",
    var installerArguments: List<String> = Collections.emptyList(),

    var modpackUrl: String = "",
    var modpackFormat: String = "",
    var formatSpecific: Map<String, Any> = Collections.emptyMap(),

    var baseInstallPath: String = "",
    var ignoreFiles: List<String> = Collections.emptyList(),
    var additionalFiles: List<AdditionalFile> = Collections.emptyList(),
    var localFiles: List<LocalFile> = Collections.emptyList(),

    var checkFolder: Boolean = false,
    var installLoader: Boolean = false,

    var spongeBootstrapper: String = "",
    var connectTimeout: Long = 30,
    var readTimeout: Long = 30,
) {


    @Suppress("UNCHECKED_CAST")
    fun <T> getFormatSpecificSettingOrDefault(name: String, fallback: T?): T? {
        return formatSpecific.getOrDefault(name, fallback) as T?
    }
}

data class ConfigFile(
    var _specver: Int = 0,
    var modpack: ModpackConfig = ModpackConfig(),
    var install: InstallConfig = InstallConfig(),
    var launch: LaunchSettings = LaunchSettings()
) {
    fun postProcess() {
        install.curseForgeApiKey = processString(install.curseForgeApiKey)
    }
}
