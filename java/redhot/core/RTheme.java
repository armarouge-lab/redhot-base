package redhot.core;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

/**
 * Theme loader (Handoff.md §4.5). All eleven tokens are mandatory; any
 * missing or empty token makes the theme invalid. Mirrors the {@code Theme}
 * struct and {@code loadTheme} function in {@code services.d}.
 */
public final class RTheme {

    private RTheme() {
    }

    public record Theme(
            String background,
            String foreground,
            String backgroundAlternative,
            String foregroundMuted,
            String accent,
            String accentForeground,
            String border,
            String borderFocused,
            String ok,
            String warn,
            String error) {
    }

    public record LoadResult(ExitCode exitCode, Theme theme) {
        public boolean isSuccess() {
            return exitCode == ExitCode.OK;
        }
    }

    public static LoadResult loadTheme(Path themePath) {
        if (themePath == null || !Files.exists(themePath)) {
            return new LoadResult(ExitCode.CONFIG, null);
        }

        String content;
        try {
            content = Files.readString(themePath);
        } catch (IOException ioException) {
            return new LoadResult(ExitCode.IO_ERROR, null);
        }

        List<List<ConfigPair>> layers = List.of(RParse.parseFlatKeyValue(content));

        Theme theme = new Theme(
                RParse.resolveConfigValue("theme.bg", layers),
                RParse.resolveConfigValue("theme.fg", layers),
                RParse.resolveConfigValue("theme.bg_alt", layers),
                RParse.resolveConfigValue("theme.fg_muted", layers),
                RParse.resolveConfigValue("theme.accent", layers),
                RParse.resolveConfigValue("theme.accent_fg", layers),
                RParse.resolveConfigValue("theme.border", layers),
                RParse.resolveConfigValue("theme.border_focus", layers),
                RParse.resolveConfigValue("theme.ok", layers),
                RParse.resolveConfigValue("theme.warn", layers),
                RParse.resolveConfigValue("theme.error", layers));

        if (isBlank(theme.background())
                || isBlank(theme.foreground())
                || isBlank(theme.backgroundAlternative())
                || isBlank(theme.foregroundMuted())
                || isBlank(theme.accent())
                || isBlank(theme.accentForeground())
                || isBlank(theme.border())
                || isBlank(theme.borderFocused())
                || isBlank(theme.ok())
                || isBlank(theme.warn())
                || isBlank(theme.error())) {
            return new LoadResult(ExitCode.CONFIG, null);
        }

        return new LoadResult(ExitCode.OK, theme);
    }

    private static boolean isBlank(String value) {
        return value == null || value.isEmpty();
    }
}
