package redhot.core;

/**
 * Canonical exit codes (Handoff.md §4.6). Mirrors the {@code ExitCode} enum
 * in {@code libredhot.a}'s {@code infra.d}.
 */
public enum ExitCode {
    OK(0),
    RUNTIME(1),
    USAGE(2),
    CONFIG(3),
    IO_ERROR(4),
    PRECONDITION(5),
    SECURITY(6),
    CANCELED(7),
    NO_HANDLER(8),
    INTERNAL(64);

    private final int numericValue;

    ExitCode(int numericValue) {
        this.numericValue = numericValue;
    }

    public int getNumericValue() {
        return numericValue;
    }
}
