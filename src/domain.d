// Ring 2 — pure logic. Zero I/O.
//
// Contracts implemented here:
//   - Flat KV parsing (key.subkey = value, '#' comments, blank lines)
//   - Precedence resolution across layers (highest-first argument order)
//   - Home-prefix expansion (pure: caller supplies the home directory)
//
// ExitCode is re-exported from Ring 4 so callers can keep `import domain;`.
module domain;

import std.string : indexOf, splitLines, strip;

public import infra : ExitCode;

// --- Flat KV pair ----------------------------------------------------------

struct ConfigPair
{
    string key;
    string value;
}

// --- Line-level parser -----------------------------------------------------

/**
 * Parse a single line of Flat KV text.
 *
 * Returns `false` (without touching `pair`) for lines that must be skipped:
 *   - blank lines
 *   - lines whose first non-whitespace character is '#'
 *   - lines that do not contain '='
 *   - lines whose key portion is empty after trimming
 *
 * On success, `pair` receives the trimmed key and trimmed value. Only the
 * FIRST '=' splits the line — later '=' characters stay in the value.
 */
bool parseKeyValueLine(string line, out ConfigPair pair)
{
    string strippedLine = line.strip;

    if (strippedLine.length == 0) {
        return false;
    }
    if (strippedLine[0] == '#') {
        return false;
    }

    auto separatorIndex = strippedLine.indexOf('=');
    if (separatorIndex < 0) {
        return false;
    }

    string key = strippedLine[0 .. separatorIndex].strip;
    if (key.length == 0) {
        return false;
    }

    pair = ConfigPair(
        key,
        strippedLine[separatorIndex + 1 .. $].strip);
    return true;
}

// --- Text-level parser -----------------------------------------------------

/**
 * Parse a full Flat KV text into a ConfigPair array.
 *
 * Order is preserved as written in the source. Duplicate keys are kept in
 * the returned array; deciding which one wins is a resolution-time concern
 * (see `resolveConfigValue`).
 */
ConfigPair[] parseFlatKeyValue(string text)
{
    ConfigPair[] pairs;

    foreach (rawLine; text.splitLines) {
        ConfigPair parsedPair;
        if (parseKeyValueLine(rawLine, parsedPair)) {
            pairs ~= parsedPair;
        }
    }

    return pairs;
}

// --- Precedence resolution -------------------------------------------------

/**
 * Resolve `key` across an ordered chain of layers.
 *
 * `layers[0]` has the highest precedence (typically CLI flags).
 * `layers[layers.length - 1]` has the lowest (typically compiled defaults).
 * Within a single layer, the LAST occurrence of `key` wins.
 *
 * Returns `null` if the key is absent from every layer.
 */
string resolveConfigValue(string key, ConfigPair[][] layers)
{
    foreach (layer; layers) {
        bool foundInLayer = false;
        string foundValue = null;

        foreach (pair; layer) {
            if (pair.key == key) {
                foundValue = pair.value;
                foundInLayer = true;
            }
        }

        if (foundInLayer) {
            return foundValue;
        }
    }

    return null;
}

// --- Home-prefix expansion (pure) ------------------------------------------

/**
 * Expand a leading "~/" (or a bare "~") to `homeDirectory`.
 *
 * This function is pure: it never reads the environment. Callers in Ring 3
 * (`services.d`) read $HOME and pass it in. Values without a "~" prefix are
 * returned unchanged.
 */
string expandHomePrefix(string value, string homeDirectory)
{
    if (value.length == 0) {
        return value;
    }
    if (value == "~") {
        return homeDirectory;
    }
    if (value.length >= 2 && value[0] == '~' && value[1] == '/') {
        return homeDirectory ~ value[1 .. $];
    }
    return value;
}
