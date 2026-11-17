package redhot.core;

/**
 * One key=value pair from a Flat KV file (Handoff.md §4.2).
 */
public record ConfigPair(String key, String value) {
}
