// Ring 1 — entry point. Parses CLI flags, dispatches to services, and is the
// only place in the program that formats user-facing messages. Every failure
// path emits the four-part WHAT / WHY / WHAT-TO-DO / WHERE contract from
// Handoff.md §2.
module entry;

import core.sys.posix.unistd : access, W_OK;
import std.file : exists, isDir, readText;
import std.stdio : stderr, writeln;
import std.string : strip, toStringz;

import domain;
import infra;
import services;

// Compile-time read of the VERSION file (repo root, via -J.).
enum REDHOT_VERSION = import("VERSION").strip;
enum REDHOT_PROGRAM_NAME = "redhot-base";

// ---------------------------------------------------------------------------
// Four-part error reporting (Handoff.md §2)
// ---------------------------------------------------------------------------

private void reportFailure(string what, string why, string whatToDo,
                           int exitCode)
{
    stderr.writeln("[FAIL] ", what);
    stderr.writeln("       WHY: ", why);
    stderr.writeln("       WHAT TO DO: ", whatToDo);
    stderr.writeln("       WHERE: r-help ", REDHOT_PROGRAM_NAME,
                   " (exit ", exitCode, ")");
}

private void printUsage()
{
    writeln("Usage: ", REDHOT_PROGRAM_NAME, " [option]");
    writeln();
    writeln("Options:");
    writeln("  --version         Print version and exit");
    writeln("  --check           Validate Redhot environment");
    writeln("  --notify-smoke    Send a test notification through the Siren FIFO");
    writeln("  -h, --help        Show this message and exit");
    writeln();
    writeln("Exit codes: 0=ok 2=usage 3=config 4=ioerror 5=precondition");
}

// ---------------------------------------------------------------------------
// Command handlers
// ---------------------------------------------------------------------------

private int handleVersion()
{
    writeln(REDHOT_VERSION);
    return cast(int)ExitCode.ok;
}

private int checkConfigurationFile()
{
    string configPath = "/etc/redhot/redhot.conf";
    if (!exists(configPath)) {
        writeln("[warn] config: ", configPath, " not found (skipped)");
        return cast(int)ExitCode.ok;
    }

    try {
        string content = readText(configPath);
        ConfigPair[] pairs = parseFlatKeyValue(content);
        writeln("[ OK ] config: ", configPath, " (", pairs.length, " keys)");
        return cast(int)ExitCode.ok;
    } catch (Exception exception) {
        reportFailure("config file is unreadable",
                      configPath ~ " (" ~ exception.msg ~ ")",
                      "check file permissions with 'ls -l " ~ configPath ~ "'",
                      cast(int)ExitCode.ioError);
        return cast(int)ExitCode.ioError;
    }
}

private int checkThemeFile()
{
    string themePath = "/etc/redhot/theme.conf";
    if (!exists(themePath)) {
        writeln("[warn] theme: ", themePath, " not found (skipped)");
        return cast(int)ExitCode.ok;
    }

    Theme theme;
    int themeResult = loadTheme(themePath, theme);
    if (themeResult != cast(int)ExitCode.ok) {
        reportFailure("theme file is invalid",
                      themePath ~ " is missing one or more required tokens",
                      "run 'ensure-base.sh' or edit " ~ themePath,
                      themeResult);
        return themeResult;
    }
    writeln("[ OK ] theme: ", themePath);
    return cast(int)ExitCode.ok;
}

private int checkStateDirectory()
{
    string stateDir = stateDirectory();
    if (stateDir is null) {
        reportFailure("cannot resolve state directory",
                      "$HOME and $XDG_STATE_HOME are both unset",
                      "export HOME or XDG_STATE_HOME before running",
                      cast(int)ExitCode.precondition);
        return cast(int)ExitCode.precondition;
    }
    if (!exists(stateDir) || !isDir(stateDir)) {
        writeln("[warn] state: ", stateDir, " not created yet (skipped)");
        return cast(int)ExitCode.ok;
    }
    if (access(toStringz(stateDir), W_OK) != 0) {
        reportFailure("state directory is not writable",
                      stateDir ~ " exists but is not writable by this user",
                      "run 'ensure-base.sh' or 'chmod u+w' on the directory",
                      cast(int)ExitCode.ioError);
        return cast(int)ExitCode.ioError;
    }
    writeln("[ OK ] state: ", stateDir, " (writable)");
    return cast(int)ExitCode.ok;
}

private int handleCheck()
{
    int firstFailure = cast(int)ExitCode.ok;

    int configResult = checkConfigurationFile();
    if (configResult != cast(int)ExitCode.ok && firstFailure == cast(int)ExitCode.ok) {
        firstFailure = configResult;
    }

    int themeResult = checkThemeFile();
    if (themeResult != cast(int)ExitCode.ok && firstFailure == cast(int)ExitCode.ok) {
        firstFailure = themeResult;
    }

    int stateResult = checkStateDirectory();
    if (stateResult != cast(int)ExitCode.ok && firstFailure == cast(int)ExitCode.ok) {
        firstFailure = stateResult;
    }

    return firstFailure;
}

private int handleNotifySmoke()
{
    string stateDir = stateDirectory();
    if (stateDir is null) {
        reportFailure("cannot resolve state directory",
                      "$HOME and $XDG_STATE_HOME are both unset",
                      "export HOME or XDG_STATE_HOME before running",
                      cast(int)ExitCode.precondition);
        return cast(int)ExitCode.precondition;
    }
    string fifoPath = stateDir ~ "/siren.fifo";
    int notifyResult = notifySiren(fifoPath, "info", REDHOT_PROGRAM_NAME,
                                   "Smoke test", "notifySiren is working");
    writeln("[ OK ] notify: sent (or silently skipped) to ", fifoPath);
    return notifyResult;
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

int main(string[] arguments)
{
    if (arguments.length == 1) {
        printUsage();
        return cast(int)ExitCode.ok;
    }

    string firstArgument = arguments[1];

    switch (firstArgument) {
        case "-h":
        case "--help":
            printUsage();
            return cast(int)ExitCode.ok;
        case "--version":
            return handleVersion();
        case "--check":
            return handleCheck();
        case "--notify-smoke":
            return handleNotifySmoke();
        default:
            reportFailure("unknown option '" ~ firstArgument ~ "'",
                          "redhot-base accepts only documented flags",
                          "run 'redhot-base --help' to see the available options",
                          cast(int)ExitCode.usage);
            return cast(int)ExitCode.usage;
    }
}
