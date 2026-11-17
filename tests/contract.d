// Black-box CLI contract tests. Each unittest invokes the compiled
// redhot-base binary and asserts on exit code and observable output.
//
// This LDC ships a Phobos whose `std.process.execute` returns
// Tuple!(int "status", string "output") — no "errout" field. To capture
// stderr we shell out with explicit redirection. Argument lists here are
// hardcoded literals (binary path + fixed flags), so shell metacharacters
// are not a concern.
module tests.contract;

import std.file : thisExePath;
import std.path : buildPath, dirName;

private string binaryPath()
{
    string repoRoot = dirName(dirName(thisExePath));
    return buildPath(repoRoot, "redhot-base");
}

// Capture stdout only; stderr discarded.
private int runStdoutOnly(string[] arguments, out string stdoutText)
{
    import std.array : join;
    import std.process : executeShell;

    string command = arguments.join(" ") ~ " 2>/dev/null";
    auto result = executeShell(command);
    stdoutText = result.output;
    return result.status;
}

// Capture stdout and stderr merged into a single stream.
private int runCombined(string[] arguments, out string combinedOutput)
{
    import std.array : join;
    import std.process : executeShell;

    string command = arguments.join(" ") ~ " 2>&1";
    auto result = executeShell(command);
    combinedOutput = result.output;
    return result.status;
}

private string toMsg(int value)
{
    import std.conv : to;
    return to!string(value);
}

// --version exits 0 and prints a non-empty version string.
unittest
{
    import std.string : strip;

    string output;
    int exitCode = runStdoutOnly([binaryPath(), "--version"], output);
    assert(exitCode == 0, "--version exit " ~ toMsg(exitCode));
    assert(output.strip.length > 0, "--version printed empty stdout");
}

// --help and -h exit 0 and print usage.
unittest
{
    import std.string : indexOf;

    foreach (flag; ["--help", "-h"]) {
        string output;
        int exitCode = runStdoutOnly([binaryPath(), flag], output);
        assert(exitCode == 0, flag ~ " exit " ~ toMsg(exitCode));
        assert(output.indexOf("Usage:") >= 0, flag ~ " missing Usage line");
    }
}

// No arguments prints usage and exits 0.
unittest
{
    import std.string : indexOf;

    string output;
    int exitCode = runStdoutOnly([binaryPath()], output);
    assert(exitCode == 0, "no-args exit " ~ toMsg(exitCode));
    assert(output.indexOf("Usage:") >= 0, "no-args missing Usage line");
}

// Unknown flag exits 2 and emits the four-part message.
unittest
{
    import std.string : indexOf;

    string combined;
    int exitCode = runCombined([binaryPath(), "--bogus"], combined);
    assert(exitCode == 2, "--bogus exit " ~ toMsg(exitCode) ~ " expected 2");
    assert(combined.indexOf("[FAIL]") >= 0, "missing [FAIL] prefix");
    assert(combined.indexOf("WHY:") >= 0, "missing WHY line");
    assert(combined.indexOf("WHAT TO DO:") >= 0, "missing WHAT TO DO line");
    assert(combined.indexOf("WHERE:") >= 0, "missing WHERE line");
    assert(combined.indexOf("exit 2") >= 0, "WHERE line missing exit code");
}

// --check passes (with warnings) or fails (with 4-part message). This test
// verifies the contract shape on either path; it does not require a
// particular environment state.
unittest
{
    import std.string : indexOf;

    string combined;
    int exitCode = runCombined([binaryPath(), "--check"], combined);
    if (exitCode != 0) {
        assert(combined.indexOf("WHY:") >= 0, "--check failure missing WHY line");
    } else {
        assert(combined.indexOf("[ OK ]") >= 0
               || combined.indexOf("[warn]") >= 0,
               "--check passed but printed no useful output");
    }
}

// --notify-smoke is fail-silent: exits 0 with or without a reader.
unittest
{
    string combined;
    int exitCode = runCombined([binaryPath(), "--notify-smoke"], combined);
    assert(exitCode == 0, "--notify-smoke exit " ~ toMsg(exitCode)
                          ~ " (should be fail-silent)");
}
