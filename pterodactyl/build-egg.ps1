# Regenerates egg-serverstarter.json, embedding install.sh as a JSON string.
# Edit install.sh (and the metadata below), then run:  pwsh ./pterodactyl/build-egg.ps1

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

$installScript = (Get-Content -Raw -Path "$here\install.sh") -replace "`r`n", "`n"

# config.files / config.startup / config.logs are stored as JSON-encoded strings inside the egg.
$configFiles = @'
{
    "server.properties": {
        "parser": "properties",
        "find": {
            "server-ip": "0.0.0.0",
            "server-port": "{{server.build.default.port}}",
            "query.port": "{{server.build.default.port}}"
        }
    }
}
'@ -replace "`r`n", "`n"

$configStartup = '{
    "done": ")! For help, type \""
}' -replace "`r`n", "`n"

function New-Var {
    param($Name, $Description, $Env, $Default, $Rules)
    return [ordered]@{
        name          = $Name
        description   = $Description
        env_variable  = $Env
        default_value = $Default
        user_viewable = $true
        user_editable = $true
        rules         = $Rules
        field_type    = "text"
    }
}

$egg = [ordered]@{
    "_comment"    = "ServerStarter egg - https://github.com/AlyxiaFox/ServerStarter - jar pinned to release v2.4.2"
    meta          = [ordered]@{ version = "PTDL_v2"; update_url = $null }
    exported_at   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    name          = "ServerStarter"
    author        = "alyxiafox@gmail.com"
    description   = "Runs a zip-distributed Forge, NeoForge or Fabric modpack through ServerStarter, which installs the pack and the mod loader on first boot and then supervises the Minecraft process. Uses a patched fork (AlyxiaFox/ServerStarter v2.4.2) that propagates the server's exit code so the panel sees real crashes, and that can accept the EULA non-interactively instead of hanging on a stdin prompt. Only the 'zip' modpack format is supported; ServerStarter's CurseForge API path is unmaintained and broken upstream."
    features      = @("eula", "java_version", "pid_limit")
    docker_images = [ordered]@{
        "Java 17" = "ghcr.io/pterodactyl/yolks:java_17"
        "Java 21" = "ghcr.io/pterodactyl/yolks:java_21"
        "Java 25" = "ghcr.io/pterodactyl/yolks:java_25"
        "Java 11" = "ghcr.io/pterodactyl/yolks:java_11"
        "Java 8"  = "ghcr.io/pterodactyl/yolks:java_8"
    }
    file_denylist = @()
    # The yolks entrypoint runs this with `exec env <command>`, not through a shell,
    # so it has to stay a single command: no ;, &&, || or redirection.
    startup       = "java -Xms16M -Xmx512M -jar serverstarter.jar"
    config        = [ordered]@{
        files   = $configFiles
        startup = $configStartup
        logs    = "{}"
        stop    = "stop"
    }
    scripts       = [ordered]@{
        installation = [ordered]@{
            script     = $installScript
            container  = "ghcr.io/pterodactyl/installers:debian"
            entrypoint = "bash"
        }
    }
    variables     = @(
        (New-Var "Modpack zip URL" "Direct download URL of the server modpack, as a .zip. Must be a direct link, not a landing page. Changing this reinstalls the pack on the next boot." "MODPACK_URL" "" "required|string|max:1024"),
        (New-Var "Minecraft version" "Exact Minecraft version, for example 1.20.1." "MC_VERSION" "1.20.1" "required|string|max:20"),
        (New-Var "Loader type" "forge for Minecraft 1.17 and newer, neoforge for 1.20.2 and newer, forge-legacy for 1.16 and older, or fabric. This picks how the server is launched, so getting it wrong stops the server from starting." "LOADER_TYPE" "forge" "required|string|in:forge,neoforge,forge-legacy,fabric"),
        (New-Var "Loader version" "Exact mod loader version. For Forge this is the Forge build, for example 47.4.1. For NeoForge it is the NeoForge version, for example 21.1.242, which already encodes the Minecraft version. For Fabric it is the Fabric loader version, for example 0.15.11." "LOADER_VERSION" "47.4.1" "required|string|max:32"),
        (New-Var "Maximum RAM" "Heap given to the Minecraft process, for example 4G or 4096M. Leave roughly 1G of the server's memory limit free for the launcher and JVM overhead, or the container gets OOM killed." "MAX_RAM" "4G" "required|string|regex:/^[0-9]+[MmGg]$/"),
        (New-Var "Minimum RAM" "Initial heap for the Minecraft process, for example 1G." "MIN_RAM" "1G" "required|string|regex:/^[0-9]+[MmGg]$/"),
        (New-Var "Auto restart" "false lets Wings own restart-on-crash, so the panel records crashes and its restart policy applies. true makes ServerStarter restart the server itself, which hides crashes from the panel." "AUTO_RESTART" "false" "required|string|in:true,false"),
        (New-Var "Accept Minecraft EULA" "Set to true to accept the Minecraft EULA (https://aka.ms/MinecraftEULA). The server will not start while this is false." "EULA" "false" "required|string|in:true,false"),
        (New-Var "Extra Java arguments" "Optional extra JVM flags for the Minecraft process, space separated. Aikar's flags are already applied. Only takes effect on reinstall." "JAVA_ARGS" "" "nullable|string|max:512")
    )
}

$json = ($egg | ConvertTo-Json -Depth 12) -replace '\\u0027', "'"
$out = "$here\egg-serverstarter.json"
[System.IO.File]::WriteAllText($out, $json + "`n", (New-Object System.Text.UTF8Encoding($false)))
Write-Output "wrote $out"
