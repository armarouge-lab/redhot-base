package redhot.core;

import java.util.List;

/**
 * Flat KV parser, precedence resolver, and home-prefix expansion
 * (Handoff.md §4.2). Pure logic, zero I/O. Mirrors {@code domain.d}.
 */
public final class RParse {

    private RParse() {
    }

    /**
     * Parse Flat KV text into an ordered list of pairs.
     *
     * Rules:
     *   - Lines starting with '#' are comments.
     *   - Blank lines are ignored.
     *   - The first '=' splits key from value.
     *   - Outer whitespace is trimmed from both key and value.
     *   - Lines without '=', or with an empty key, are silently skipped.
     *   - Duplicate keys are preserved in source order.
     */
    public static List<ConfigPair> parseFlatKeyValue(String text) {
        if (text == null || text.isEmpty()) {
            return List.of();
        }
        return text.lines()
                .map(RParse::parseLine)
                .filter(pair -> pair != null)
                .toList();
    }

    /**
     * Resolve a key across an ordered chain of layers.
     *
     * Layer 0 has the highest precedence. Within a single layer, the last
     * occurrence of the key wins. Returns {@code null} if the key is absent
     * from every layer.
     */
    public static String resolveConfigValue(String key,
                                            List<List<ConfigPair>> layers) {
        if (key == null || layers == null) {
            return null;
        }
        for (List<ConfigPair> layer : layers) {
            String foundValue = null;
            boolean foundInLayer = false;
            for (ConfigPair pair : layer) {
                if (pair.key().equals(key)) {
                    foundValue = pair.value();
                    foundInLayer = true;
                }
            }
            if (foundInLayer) {
                return foundValue;
            }
        }
        return null;
    }

    /**
     * Expand a leading "~/" (or a bare "~") to {@code homeDirectory}.
     * Pure: the caller supplies the home directory. Values without a "~"
     * prefix are returned unchanged.
     */
    public static String expandHomePrefix(String value, String homeDirectory) {
        if (value == null || value.isEmpty()) {
            return value;
        }
        if (value.equals("~")) {
            return homeDirectory;
        }
        if (value.length() >= 2 && value.charAt(0) == '~' && value.charAt(1) == '/') {
            return homeDirectory + value.substring(1);
        }
        return value;
    }

    private static ConfigPair parseLine(String rawLine) {
        String strippedLine = rawLine.strip();
        if (strippedLine.isEmpty()) {
            return null;
        }
        if (strippedLine.charAt(0) == '#') {
            return null;
        }
        int separatorIndex = strippedLine.indexOf('=');
        if (separatorIndex < 0) {
            return null;
        }
        String key = strippedLine.substring(0, separatorIndex).strip();
        if (key.isEmpty()) {
            return null;
        }
        String value = strippedLine.substring(separatorIndex + 1).strip();
        return new ConfigPair(key, value);
    }
}
