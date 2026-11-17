// Ring 3 — system adapters. Owns XDG path resolution, theme loading, and
// shared-state file access. Calls into Ring 4 (infra) for atomic writes.
module services;

import domain;
import infra;

import core.stdc.stdlib : getenv;
import std.file : exists, readText;
import std.string : fromStringz, splitLines, strip;

// --- XDG path resolution ---------------------------------------------------

string configDirectory()
{
    const(char)* xdgConfigHomeRaw = getenv("XDG_CONFIG_HOME");
    if (xdgConfigHomeRaw !is null) {
        string xdgConfigHome = fromStringz(xdgConfigHomeRaw).idup;
        if (xdgConfigHome.length > 0) {
            return xdgConfigHome ~ "/redhot";
        }
    }
    const(char)* homeRaw = getenv("HOME");
    if (homeRaw is null) {
        return null;
    }
    string homeDirectory = fromStringz(homeRaw).idup;
    if (homeDirectory.length == 0) {
        return null;
    }
    return homeDirectory ~ "/.config/redhot";
}

string stateDirectory()
{
    const(char)* xdgStateHomeRaw = getenv("XDG_STATE_HOME");
    if (xdgStateHomeRaw !is null) {
        string xdgStateHome = fromStringz(xdgStateHomeRaw).idup;
        if (xdgStateHome.length > 0) {
            return xdgStateHome ~ "/redhot";
        }
    }
    const(char)* homeRaw = getenv("HOME");
    if (homeRaw is null) {
        return null;
    }
    string homeDirectory = fromStringz(homeRaw).idup;
    if (homeDirectory.length == 0) {
        return null;
    }
    return homeDirectory ~ "/.local/state/redhot";
}

string dataDirectory()
{
    const(char)* xdgDataHomeRaw = getenv("XDG_DATA_HOME");
    if (xdgDataHomeRaw !is null) {
        string xdgDataHome = fromStringz(xdgDataHomeRaw).idup;
        if (xdgDataHome.length > 0) {
            return xdgDataHome ~ "/redhot";
        }
    }
    const(char)* homeRaw = getenv("HOME");
    if (homeRaw is null) {
        return null;
    }
    string homeDirectory = fromStringz(homeRaw).idup;
    if (homeDirectory.length == 0) {
        return null;
    }
    return homeDirectory ~ "/.local/share/redhot";
}

// --- Theme loader (Handoff.md §4.5) ----------------------------------------

struct Theme
{
    string background;
    string foreground;
    string backgroundAlternative;
    string foregroundMuted;
    string accent;
    string accentForeground;
    string border;
    string borderFocused;
    string ok;
    string warn;
    string error;
}

private bool isBlank(string value)
{
    return value is null || value.length == 0;
}

/**
 * Load /etc/redhot/theme.conf (or a user override) into a Theme.
 *
 * Returns:
 *   ExitCode.ok       — all 11 required tokens present and non-empty
 *   ExitCode.config   — file missing, unreadable, or a token absent/empty
 *   ExitCode.ioError  — read(2) failed after existence check
 */
ExitCode loadTheme(string themePath, out Theme theme)
{
    theme = Theme.init;

    if (themePath is null || themePath.length == 0) {
        return ExitCode.usage;
    }
    if (!exists(themePath)) {
        return ExitCode.config;
    }

    string content;
    try {
        content = readText(themePath);
    } catch (Exception) {
        return ExitCode.ioError;
    }

    ConfigPair[][] layer = [parseFlatKeyValue(content)];

    theme.background             = resolveConfigValue("theme.bg", layer);
    theme.foreground             = resolveConfigValue("theme.fg", layer);
    theme.backgroundAlternative  = resolveConfigValue("theme.bg_alt", layer);
    theme.foregroundMuted        = resolveConfigValue("theme.fg_muted", layer);
    theme.accent                 = resolveConfigValue("theme.accent", layer);
    theme.accentForeground       = resolveConfigValue("theme.accent_fg", layer);
    theme.border                 = resolveConfigValue("theme.border", layer);
    theme.borderFocused          = resolveConfigValue("theme.border_focus", layer);
    theme.ok                     = resolveConfigValue("theme.ok", layer);
    theme.warn                   = resolveConfigValue("theme.warn", layer);
    theme.error                  = resolveConfigValue("theme.error", layer);

    if (isBlank(theme.background) ||
        isBlank(theme.foreground) ||
        isBlank(theme.backgroundAlternative) ||
        isBlank(theme.foregroundMuted) ||
        isBlank(theme.accent) ||
        isBlank(theme.accentForeground) ||
        isBlank(theme.border) ||
        isBlank(theme.borderFocused) ||
        isBlank(theme.ok) ||
        isBlank(theme.warn) ||
        isBlank(theme.error)) {
        return ExitCode.config;
    }

    return ExitCode.ok;
}

// --- Shared-state paths ----------------------------------------------------

private string currentDirectoryFilePath()
{
    string stateDir = stateDirectory();
    if (stateDir is null) return null;
    return stateDir ~ "/current_dir";
}

private string currentFilePath()
{
    string stateDir = stateDirectory();
    if (stateDir is null) return null;
    return stateDir ~ "/current_file";
}

private string recentFilesFilePath()
{
    string stateDir = stateDirectory();
    if (stateDir is null) return null;
    return stateDir ~ "/recent_files";
}

// --- current_dir -----------------------------------------------------------

ExitCode writeCurrentDirectory(string directoryPath)
{
    string targetPath = currentDirectoryFilePath();
    if (targetPath is null) {
        return ExitCode.precondition;
    }
    return cast(ExitCode)writeAtomic(targetPath, directoryPath ~ "\n");
}

string readCurrentDirectory()
{
    string targetPath = currentDirectoryFilePath();
    if (targetPath is null || !exists(targetPath)) {
        return null;
    }
    string content;
    try {
        content = readText(targetPath);
    } catch (Exception) {
        return null;
    }
    string stripped = content.strip;
    if (stripped.length == 0) {
        return null;
    }
    return stripped;
}

// --- current_file ----------------------------------------------------------

ExitCode writeCurrentFile(string filePath)
{
    string targetPath = currentFilePath();
    if (targetPath is null) {
        return ExitCode.precondition;
    }
    return cast(ExitCode)writeAtomic(targetPath, filePath ~ "\n");
}

string readCurrentFile()
{
    string targetPath = currentFilePath();
    if (targetPath is null || !exists(targetPath)) {
        return null;
    }
    string content;
    try {
        content = readText(targetPath);
    } catch (Exception) {
        return null;
    }
    string stripped = content.strip;
    if (stripped.length == 0) {
        return null;
    }
    return stripped;
}

// --- recent_files (FIFO, max 50 unique, most recent first) -----------------

enum size_t RECENT_FILES_MAX = 50;

string[] readRecentFiles()
{
    string targetPath = recentFilesFilePath();
    if (targetPath is null || !exists(targetPath)) {
        return [];
    }
    string content;
    try {
        content = readText(targetPath);
    } catch (Exception) {
        return [];
    }

    string[] entries;
    foreach (line; content.splitLines) {
        string strippedLine = line.strip;
        if (strippedLine.length > 0) {
            entries ~= strippedLine;
        }
    }
    return entries;
}

/**
 * Prepend `filePath` to recent_files, remove any earlier occurrence of the
 * same path, truncate to RECENT_FILES_MAX entries, and write atomically.
 */
ExitCode appendRecentFile(string filePath)
{
    string targetPath = recentFilesFilePath();
    if (targetPath is null) {
        return ExitCode.precondition;
    }
    if (filePath is null || filePath.length == 0) {
        return ExitCode.usage;
    }

    string[] updatedEntries;
    updatedEntries ~= filePath;
    foreach (entry; readRecentFiles()) {
        if (entry == filePath) continue;
        if (updatedEntries.length >= RECENT_FILES_MAX) break;
        updatedEntries ~= entry;
    }

    char[] serializedPayload;
    foreach (entry; updatedEntries) {
        serializedPayload ~= entry;
        serializedPayload ~= '\n';
    }

    return cast(ExitCode)writeAtomic(targetPath, serializedPayload.idup);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

// Helper: unique per-test temp directory.
private string makeTestDirectory(string prefix)
{
    import core.sys.posix.unistd : getpid;
    import std.conv : to;
    import std.file : mkdirRecurse;
    import std.random : uniform;

    string directory = "/tmp/" ~ prefix ~ "-"
        ~ to!string(getpid()) ~ "-" ~ to!string(uniform(0, 1000000));
    mkdirRecurse(directory);
    return directory;
}

private void removeTestDirectoryBestEffort(string directoryPath)
{
    import std.file : rmdirRecurse;
    try {
        rmdirRecurse(directoryPath);
    } catch (Exception) {
    }
}

private void writeTextFile(string path, string content)
{
    import std.file : write;
    write(path, content);
}

// XDG fallback behavior: $HOME → ~/.config/redhot, ~/.local/state/redhot,
// ~/.local/share/redhot.
unittest
{
    import core.sys.posix.stdlib : setenv, unsetenv;
    import std.string : toStringz;

    const(char)* originalXdgConfigHome = getenv("XDG_CONFIG_HOME");
    const(char)* originalXdgStateHome  = getenv("XDG_STATE_HOME");
    const(char)* originalXdgDataHome   = getenv("XDG_DATA_HOME");
    const(char)* originalHome          = getenv("HOME");

    scope(exit) {
        if (originalXdgConfigHome is null) unsetenv("XDG_CONFIG_HOME");
        else setenv("XDG_CONFIG_HOME", originalXdgConfigHome, 1);
        if (originalXdgStateHome is null) unsetenv("XDG_STATE_HOME");
        else setenv("XDG_STATE_HOME", originalXdgStateHome, 1);
        if (originalXdgDataHome is null) unsetenv("XDG_DATA_HOME");
        else setenv("XDG_DATA_HOME", originalXdgDataHome, 1);
        if (originalHome is null) unsetenv("HOME");
        else setenv("HOME", originalHome, 1);
    }

    setenv("HOME", toStringz("/tmp/fake-home"), 1);
    unsetenv("XDG_CONFIG_HOME");
    unsetenv("XDG_STATE_HOME");
    unsetenv("XDG_DATA_HOME");

    assert(configDirectory() == "/tmp/fake-home/.config/redhot");
    assert(stateDirectory()  == "/tmp/fake-home/.local/state/redhot");
    assert(dataDirectory()   == "/tmp/fake-home/.local/share/redhot");

    setenv("XDG_CONFIG_HOME", toStringz("/tmp/xdg-config"), 1);
    setenv("XDG_STATE_HOME",  toStringz("/tmp/xdg-state"),  1);
    setenv("XDG_DATA_HOME",   toStringz("/tmp/xdg-data"),   1);

    assert(configDirectory() == "/tmp/xdg-config/redhot");
    assert(stateDirectory()  == "/tmp/xdg-state/redhot");
    assert(dataDirectory()   == "/tmp/xdg-data/redhot");
}

// Valid theme: all 11 tokens present.
unittest
{
    string directory = makeTestDirectory("redhot-theme-valid");
    scope(exit) removeTestDirectoryBestEffort(directory);

    string themePath = directory ~ "/theme.conf";
    writeTextFile(themePath,
        "theme.bg=#1a1a1a\n" ~
        "theme.fg=#e0e0e0\n" ~
        "theme.bg_alt=#242424\n" ~
        "theme.fg_muted=#808080\n" ~
        "theme.accent=#c1272d\n" ~
        "theme.accent_fg=#ffffff\n" ~
        "theme.border=#333333\n" ~
        "theme.border_focus=#c1272d\n" ~
        "theme.ok=#4caf50\n" ~
        "theme.warn=#ff9800\n" ~
        "theme.error=#f44336\n");

    Theme theme;
    int result = loadTheme(themePath, theme);
    assert(result == cast(int)ExitCode.ok);
    assert(theme.background == "#1a1a1a");
    assert(theme.foreground == "#e0e0e0");
    assert(theme.accent == "#c1272d");
    assert(theme.borderFocused == "#c1272d");
    assert(theme.error == "#f44336");
}

// Missing token → ExitCode.config.
unittest
{
    string directory = makeTestDirectory("redhot-theme-missing");
    scope(exit) removeTestDirectoryBestEffort(directory);

    string themePath = directory ~ "/theme.conf";
    writeTextFile(themePath,
        "theme.bg=#1a1a1a\n" ~
        "theme.fg=#e0e0e0\n" ~
        "theme.bg_alt=#242424\n");
    // remaining 8 tokens missing

    Theme theme;
    int result = loadTheme(themePath, theme);
    assert(result == cast(int)ExitCode.config);
}

// Nonexistent theme → ExitCode.config.
unittest
{
    Theme theme;
    int result = loadTheme("/nonexistent/redhot/theme.conf", theme);
    assert(result == cast(int)ExitCode.config);
}

// current_dir and current_file round-trip through writeAtomic.
unittest
{
    import core.sys.posix.stdlib : setenv, unsetenv;
    import std.file : mkdirRecurse;
    import std.string : toStringz;

    string directory = makeTestDirectory("redhot-state");
    scope(exit) removeTestDirectoryBestEffort(directory);

    string xdgStateHome = directory;
    mkdirRecurse(xdgStateHome ~ "/redhot");

    const(char)* originalXdgStateHome = getenv("XDG_STATE_HOME");
    scope(exit) {
        if (originalXdgStateHome is null) unsetenv("XDG_STATE_HOME");
        else setenv("XDG_STATE_HOME", originalXdgStateHome, 1);
    }
    setenv("XDG_STATE_HOME", toStringz(xdgStateHome), 1);

    assert(readCurrentDirectory() is null);
    assert(readCurrentFile() is null);

    assert(writeCurrentDirectory("/home/user/projects")
           == cast(int)ExitCode.ok);
    assert(readCurrentDirectory() == "/home/user/projects");

    assert(writeCurrentFile("/home/user/projects/file.txt")
           == cast(int)ExitCode.ok);
    assert(readCurrentFile() == "/home/user/projects/file.txt");
}

// recent_files: append, dedupe, order.
unittest
{
    import core.sys.posix.stdlib : setenv, unsetenv;
    import std.file : mkdirRecurse;
    import std.string : toStringz;

    string directory = makeTestDirectory("redhot-recent");
    scope(exit) removeTestDirectoryBestEffort(directory);

    mkdirRecurse(directory ~ "/redhot");

    const(char)* originalXdgStateHome = getenv("XDG_STATE_HOME");
    scope(exit) {
        if (originalXdgStateHome is null) unsetenv("XDG_STATE_HOME");
        else setenv("XDG_STATE_HOME", originalXdgStateHome, 1);
    }
    setenv("XDG_STATE_HOME", toStringz(directory), 1);

    assert(readRecentFiles() == []);

    assert(appendRecentFile("/a") == cast(int)ExitCode.ok);
    assert(appendRecentFile("/b") == cast(int)ExitCode.ok);
    assert(appendRecentFile("/c") == cast(int)ExitCode.ok);

    string[] entries = readRecentFiles();
    assert(entries.length == 3);
    assert(entries[0] == "/c");
    assert(entries[1] == "/b");
    assert(entries[2] == "/a");

    // Re-appending /a promotes it to the top and dedupes.
    assert(appendRecentFile("/a") == cast(int)ExitCode.ok);
    entries = readRecentFiles();
    assert(entries.length == 3);
    assert(entries[0] == "/a");
    assert(entries[1] == "/c");
    assert(entries[2] == "/b");
}

// recent_files cap at 50.
unittest
{
    import core.sys.posix.stdlib : setenv, unsetenv;
    import std.conv : to;
    import std.file : mkdirRecurse;
    import std.string : toStringz;

    string directory = makeTestDirectory("redhot-recent-cap");
    scope(exit) removeTestDirectoryBestEffort(directory);

    mkdirRecurse(directory ~ "/redhot");

    const(char)* originalXdgStateHome = getenv("XDG_STATE_HOME");
    scope(exit) {
        if (originalXdgStateHome is null) unsetenv("XDG_STATE_HOME");
        else setenv("XDG_STATE_HOME", originalXdgStateHome, 1);
    }
    setenv("XDG_STATE_HOME", toStringz(directory), 1);

    foreach (index; 0 .. 60) {
        assert(appendRecentFile("/path-" ~ to!string(index))
               == cast(int)ExitCode.ok);
    }

    string[] entries = readRecentFiles();
    assert(entries.length == RECENT_FILES_MAX);
    assert(entries[0] == "/path-59");
    assert(entries[RECENT_FILES_MAX - 1] == "/path-10");
}
