package redhot.core;

import java.util.List;

/**
 * Unit tests for the Java mirror. Runs via {@code make test-java}.
 * JUnit-free to keep the dependency graph at zero.
 */
public final class RParseTest {

    private static int passedCount = 0;
    private static int failedCount = 0;

    public static void main(String[] args) {
        testEmptyInput();
        testCommentsAndBlanks();
        testSimplePair();
        testWhitespaceTrim();
        testFirstEqualsSplits();
        testEmptyValue();
        testDuplicateKeysPreserved();
        testResolvePrecedence();
        testResolveLastWins();
        testResolveMissing();
        testExpandHomePrefix();
        testExpandTildeAlone();
        testExpandNoTilde();
        testExpandEmpty();

        System.out.println();
        System.out.println(passedCount + " passed, " + failedCount + " failed");
        System.exit(failedCount == 0 ? 0 : 1);
    }

    private static void recordPass(String label) {
        System.out.println("[ OK ] " + label);
        passedCount++;
    }

    private static void recordFailure(String label, String detail) {
        System.out.println("[FAIL] " + label + ": " + detail);
        failedCount++;
    }

    private static void assertEquals(String label, Object actual, Object expected) {
        if (actual == null && expected == null) {
            recordPass(label);
            return;
        }
        if (actual != null && actual.equals(expected)) {
            recordPass(label);
            return;
        }
        recordFailure(label, "expected " + expected + ", got " + actual);
    }

    private static void assertListSize(String label, List<?> list, int expectedSize) {
        assertEquals(label, list.size(), expectedSize);
    }

    private static void testEmptyInput() {
        assertListSize("empty input: zero pairs",
                RParse.parseFlatKeyValue(""), 0);
        assertListSize("null input: zero pairs",
                RParse.parseFlatKeyValue(null), 0);
    }

    private static void testCommentsAndBlanks() {
        assertListSize("comments and blanks: skipped",
                RParse.parseFlatKeyValue("# c\n\n   \n# another\n"), 0);
    }

    private static void testSimplePair() {
        List<ConfigPair> pairs = RParse.parseFlatKeyValue("general.theme=redhot\n");
        assertListSize("simple pair: one", pairs, 1);
        assertEquals("simple pair: key", pairs.get(0).key(), "general.theme");
        assertEquals("simple pair: value", pairs.get(0).value(), "redhot");
    }

    private static void testWhitespaceTrim() {
        List<ConfigPair> pairs = RParse.parseFlatKeyValue("  key  =  value  \n");
        assertListSize("whitespace: one", pairs, 1);
        assertEquals("whitespace: key", pairs.get(0).key(), "key");
        assertEquals("whitespace: value", pairs.get(0).value(), "value");
    }

    private static void testFirstEqualsSplits() {
        List<ConfigPair> pairs = RParse.parseFlatKeyValue("path=/a=b=c\n");
        assertListSize("first equals: one", pairs, 1);
        assertEquals("first equals: value keeps subsequent '='",
                pairs.get(0).value(), "/a=b=c");
    }

    private static void testEmptyValue() {
        List<ConfigPair> pairs = RParse.parseFlatKeyValue("key=\n");
        assertListSize("empty value: one", pairs, 1);
        assertEquals("empty value: value is empty",
                pairs.get(0).value(), "");
    }

    private static void testDuplicateKeysPreserved() {
        assertListSize("duplicates: preserved",
                RParse.parseFlatKeyValue("k=1\nk=2\nk=3\n"), 3);
    }

    private static void testResolvePrecedence() {
        List<ConfigPair> high = List.of(new ConfigPair("key", "high"));
        List<ConfigPair> low = List.of(new ConfigPair("key", "low"));
        assertEquals("resolve: high wins",
                RParse.resolveConfigValue("key", List.of(high, low)), "high");
    }

    private static void testResolveLastWins() {
        List<ConfigPair> layer = List.of(
                new ConfigPair("key", "first"),
                new ConfigPair("key", "second"));
        assertEquals("resolve: last wins within layer",
                RParse.resolveConfigValue("key", List.of(layer)), "second");
    }

    private static void testResolveMissing() {
        assertEquals("resolve: missing returns null",
                RParse.resolveConfigValue("missing",
                        List.of(List.of(new ConfigPair("other", "x")))),
                null);
    }

    private static void testExpandHomePrefix() {
        assertEquals("expand: ~/ prefix",
                RParse.expandHomePrefix("~/.config", "/home/user"),
                "/home/user/.config");
    }

    private static void testExpandTildeAlone() {
        assertEquals("expand: bare ~",
                RParse.expandHomePrefix("~", "/home/user"), "/home/user");
    }

    private static void testExpandNoTilde() {
        assertEquals("expand: absolute path unchanged",
                RParse.expandHomePrefix("/etc/redhot", "/home/user"),
                "/etc/redhot");
    }

    private static void testExpandEmpty() {
        assertEquals("expand: empty string",
                RParse.expandHomePrefix("", "/home/user"), "");
    }
}
