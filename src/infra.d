// Ring 4 — syscalls. Owns flock(2), mkstemp, fsync(2), rename(2), and
// non-blocking writes to the Siren FIFO.
//
// Design note (On-Rails): this ring returns ExitCode values only. It never
// formats user-facing messages — that is Ring 1's job.
module infra;

import core.stdc.errno : errno, EINTR, ENOENT, ENXIO;
import core.sys.posix.fcntl : open, O_CREAT, O_NONBLOCK, O_RDONLY, O_RDWR,
                              O_WRONLY;
import core.sys.posix.stdio : rename;
import core.sys.posix.stdlib : mkstemp;
import core.sys.posix.sys.types : ssize_t;
import core.sys.posix.unistd : close, fsync, unlink, write;

import std.conv : octal;
import std.path : dirName;
import std.string : fromStringz, toStringz;

// flock(2) declared extern(C) because druntime's `core.sys.posix.sys.file`
// does not exist on modern LDC. The libc symbol resolves on Linux and FreeBSD.
extern(C) int flock(int fileDescriptor, int operation);

enum LOCK_EX = 2;
enum LOCK_NB = 4;
enum LOCK_UN = 8;

// Canonical exit codes (Handoff.md §4.6).
enum ExitCode : int
{
    ok           = 0,
    runtime      = 1,
    usage        = 2,
    config       = 3,
    ioError      = 4,
    precondition = 5,
    security     = 6,
    canceled     = 7,
    noHandler    = 8,
    internal     = 64
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

private bool writeAllBytes(int fileDescriptor, const(char)[] data)
{
    size_t written = 0;
    while (written < data.length) {
        ssize_t result = write(fileDescriptor, data.ptr + written,
                               data.length - written);
        if (result < 0) {
            if (errno == EINTR) continue;
            return false;
        }
        written += cast(size_t)result;
    }
    return true;
}

private void removeDirectoryBestEffort(string directoryPath)
{
    import std.file : rmdirRecurse;
    try {
        rmdirRecurse(directoryPath);
    } catch (Exception) {
        // nothing actionable; the directory may already be gone
    }
}

// Replace characters that would break the Siren wire format:
// newlines, carriage returns, tabs, and the field separator itself.
private string sanitizeSirenField(string field)
{
    char[] mutableField = field.dup;
    foreach (ref char character; mutableField) {
        switch (character) {
            case '\n': case '\r': case '\t': case '|':
                character = ' ';
                break;
            default:
                break;
        }
    }
    return mutableField.idup;
}

// ---------------------------------------------------------------------------
// Atomic write (Handoff.md §4.3)
// ---------------------------------------------------------------------------

/**
 * Write `data` to `targetPath` atomically.
 *
 * Sequence:
 *   1. flock(2) exclusive on <targetPath>.lock
 *   2. mkstemp in dirname(targetPath)
 *   3. write + fsync(fd) + close(fd)
 *   4. rename(temp, target)
 *   5. fsync(parent directory) — makes the rename itself durable
 *   6. release lock
 */
int writeAtomic(string targetPath, string data)
{
    string lockPath = targetPath ~ ".lock";
    int lockFileDescriptor = open(toStringz(lockPath), O_CREAT | O_RDWR,
                                  octal!"600");
    if (lockFileDescriptor < 0) {
        return cast(int)ExitCode.ioError;
    }

    if (flock(lockFileDescriptor, LOCK_EX) != 0) {
        close(lockFileDescriptor);
        return cast(int)ExitCode.ioError;
    }

    scope(exit) {
        flock(lockFileDescriptor, LOCK_UN);
        close(lockFileDescriptor);
    }

    string parentDirectory = dirName(targetPath);
    string temporaryTemplate = parentDirectory ~ "/.redhot-state.XXXXXX";

    char[] mutableTemplate;
    mutableTemplate.length = temporaryTemplate.length + 1;
    mutableTemplate[0 .. temporaryTemplate.length] = temporaryTemplate[];
    mutableTemplate[temporaryTemplate.length] = '\0';

    int temporaryFileDescriptor = mkstemp(mutableTemplate.ptr);
    if (temporaryFileDescriptor < 0) {
        return cast(int)ExitCode.ioError;
    }

    string temporaryPath = fromStringz(mutableTemplate.ptr).idup;

    bool renameCompleted = false;
    scope(exit) {
        if (!renameCompleted) {
            unlink(toStringz(temporaryPath));
        }
    }

    if (!writeAllBytes(temporaryFileDescriptor, data)) {
        close(temporaryFileDescriptor);
        return cast(int)ExitCode.ioError;
    }

    if (fsync(temporaryFileDescriptor) != 0) {
        close(temporaryFileDescriptor);
        return cast(int)ExitCode.ioError;
    }

    if (close(temporaryFileDescriptor) != 0) {
        return cast(int)ExitCode.ioError;
    }

    if (rename(toStringz(temporaryPath), toStringz(targetPath)) != 0) {
        return cast(int)ExitCode.ioError;
    }
    renameCompleted = true;

    int parentFileDescriptor = open(toStringz(parentDirectory), O_RDONLY);
    if (parentFileDescriptor >= 0) {
        fsync(parentFileDescriptor);
        close(parentFileDescriptor);
    }

    return cast(int)ExitCode.ok;
}

// ---------------------------------------------------------------------------
// Siren FIFO notification (Handoff.md §4.4)
// ---------------------------------------------------------------------------

/**
 * Send a notification to the Siren FIFO at `fifoPath`.
 *
 * Wire format (per line, terminated with '\n'):
 *   <level>|<appName>|<title>|<message>
 *
 * Fields are sanitized: '\n', '\r', '\t', and '|' are replaced with ' '.
 * The payload is truncated to 512 bytes (PIPE_BUF) if longer.
 *
 * Fail-silent contract:
 *   - ENXIO (no reader)    → ExitCode.ok, nothing written
 *   - ENOENT (FIFO absent) → ExitCode.ok, nothing written
 *   - any other error      → ExitCode.ioError
 *
 * This function never blocks: the FIFO is opened with O_NONBLOCK.
 */
int notifySiren(string fifoPath, string level, string appName,
                string title, string message)
{
    string payload = sanitizeSirenField(level) ~ "|"
                   ~ sanitizeSirenField(appName) ~ "|"
                   ~ sanitizeSirenField(title) ~ "|"
                   ~ sanitizeSirenField(message) ~ "\n";

    if (payload.length > 512) {
        payload = payload[0 .. 511] ~ "\n";
    }

    int fifoFileDescriptor = open(toStringz(fifoPath),
                                  O_WRONLY | O_NONBLOCK);
    if (fifoFileDescriptor < 0) {
        if (errno == ENXIO || errno == ENOENT) {
            return cast(int)ExitCode.ok;
        }
        return cast(int)ExitCode.ioError;
    }

    scope(exit) close(fifoFileDescriptor);

    if (!writeAllBytes(fifoFileDescriptor, payload)) {
        return cast(int)ExitCode.ioError;
    }

    return cast(int)ExitCode.ok;
}

// ---------------------------------------------------------------------------
// Tests — writeAtomic
// ---------------------------------------------------------------------------

unittest
{
    import core.sys.posix.unistd : getpid;
    import std.algorithm.searching : startsWith;
    import std.conv : to;
    import std.file : dirEntries, mkdirRecurse, readText, SpanMode;
    import std.path : baseName;
    import std.random : uniform;

    string testDirectory = "/tmp/.redhot-atomic-"
        ~ to!string(getpid()) ~ "-" ~ to!string(uniform(0, 1000000));
    mkdirRecurse(testDirectory);
    scope(exit) removeDirectoryBestEffort(testDirectory);

    string targetPath = testDirectory ~ "/state";

    assert(writeAtomic(targetPath, "hello=world\n") == cast(int)ExitCode.ok);
    assert(readText(targetPath) == "hello=world\n");

    assert(writeAtomic(targetPath, "second=write\n") == cast(int)ExitCode.ok);
    assert(readText(targetPath) == "second=write\n");

    size_t strayCount = 0;
    foreach (entry; dirEntries(testDirectory, SpanMode.shallow)) {
        if (baseName(entry.name).startsWith(".redhot-state.")) {
            strayCount++;
        }
    }
    assert(strayCount == 0, "stray temp files remained");
}

unittest
{
    int result = writeAtomic("/nonexistent/redhot/path/state", "data");
    assert(result == cast(int)ExitCode.ioError);
}

unittest
{
    import core.sys.posix.unistd : getpid;
    import core.thread : Thread;
    import std.conv : to;
    import std.file : exists, mkdirRecurse, readText;
    import std.random : uniform;

    string testDirectory = "/tmp/.redhot-concurrent-"
        ~ to!string(getpid()) ~ "-" ~ to!string(uniform(0, 1000000));
    mkdirRecurse(testDirectory);
    scope(exit) removeDirectoryBestEffort(testDirectory);

    string targetPath = testDirectory ~ "/state";
    assert(writeAtomic(targetPath, "seed") == cast(int)ExitCode.ok);

    enum int childCount = 20;
    string[] payloads;
    foreach (index; 0 .. childCount) {
        payloads ~= "child-" ~ to!string(index) ~ "-payload-data";
    }

    Thread[] threads;
    foreach (index; 0 .. childCount) {
        int capturedIndex = index;
        auto thread = new Thread({
            writeAtomic(targetPath, payloads[capturedIndex]);
        });
        thread.start();
        threads ~= thread;
    }
    foreach (thread; threads) {
        thread.join();
    }

    assert(exists(targetPath), "target file was not created");
    string finalContent = readText(targetPath);
    bool matched = false;
    foreach (payload; payloads) {
        if (finalContent == payload) {
            matched = true;
            break;
        }
    }
    assert(matched, "concurrent write corruption — final content: " ~ finalContent);
}

// ---------------------------------------------------------------------------
// Tests — notifySiren
// ---------------------------------------------------------------------------

// FIFO has a reader: payload arrives intact.
//
// Technique: open the FIFO with O_RDWR from the test. That handle counts as
// a reader for the other side's O_WRONLY open, so notifySiren's non-blocking
// open succeeds. Reading from the same handle retrieves the bytes written.
// Fully deterministic — no sleeps, no threads.
unittest
{
    import core.sys.posix.fcntl : O_RDWR, open;
    import core.sys.posix.sys.stat : mkfifo;
    import core.sys.posix.unistd : close, getpid, read;
    import std.conv : to;
    import std.file : mkdirRecurse;
    import std.random : uniform;

    string testDirectory = "/tmp/.redhot-siren-"
        ~ to!string(getpid()) ~ "-" ~ to!string(uniform(0, 1000000));
    mkdirRecurse(testDirectory);
    scope(exit) removeDirectoryBestEffort(testDirectory);

    string fifoPath = testDirectory ~ "/siren.fifo";
    assert(mkfifo(toStringz(fifoPath), octal!"600") == 0);

    int fifoFileDescriptor = open(toStringz(fifoPath), O_RDWR);
    assert(fifoFileDescriptor >= 0, "could not open FIFO for the test");
    scope(exit) close(fifoFileDescriptor);

    int result = notifySiren(fifoPath, "info", "test-app", "Hello", "World");
    assert(result == cast(int)ExitCode.ok);

    char[1024] readBuffer;
    ssize_t readCount = read(fifoFileDescriptor, readBuffer.ptr,
                             readBuffer.length);
    assert(readCount > 0, "no data received from FIFO");

    string receivedPayload = readBuffer[0 .. cast(size_t)readCount].idup;
    assert(receivedPayload == "info|test-app|Hello|World\n",
           "unexpected payload: " ~ receivedPayload);
}

// FIFO does not exist: fail-silent, must not block.
unittest
{
    import core.time : MonoTime;

    auto startTime = MonoTime.currTime();
    int result = notifySiren("/nonexistent/redhot/siren.fifo",
                             "info", "app", "t", "m");
    auto elapsedMilliseconds =
        (MonoTime.currTime() - startTime).total!"msecs";

    assert(result == cast(int)ExitCode.ok);
    assert(elapsedMilliseconds < 100,
           "notifySiren blocked despite missing FIFO");
}

// FIFO exists but no reader: fail-silent on ENXIO.
unittest
{
    import core.sys.posix.sys.stat : mkfifo;
    import core.sys.posix.unistd : getpid;
    import core.time : MonoTime;
    import std.conv : to;
    import std.file : mkdirRecurse;
    import std.random : uniform;

    string testDirectory = "/tmp/.redhot-siren-noreader-"
        ~ to!string(getpid()) ~ "-" ~ to!string(uniform(0, 1000000));
    mkdirRecurse(testDirectory);
    scope(exit) removeDirectoryBestEffort(testDirectory);

    string fifoPath = testDirectory ~ "/siren.fifo";
    assert(mkfifo(toStringz(fifoPath), octal!"600") == 0);

    auto startTime = MonoTime.currTime();
    int result = notifySiren(fifoPath, "info", "app", "t", "m");
    auto elapsedMilliseconds =
        (MonoTime.currTime() - startTime).total!"msecs";

    assert(result == cast(int)ExitCode.ok);
    assert(elapsedMilliseconds < 100,
           "notifySiren blocked without reader");
}

// Field separators and control characters in inputs are sanitized, so the
// wire format stays parseable with exactly four fields.
unittest
{
    import core.sys.posix.fcntl : O_RDWR, open;
    import core.sys.posix.sys.stat : mkfifo;
    import core.sys.posix.unistd : close, getpid, read;
    import std.conv : to;
    import std.file : mkdirRecurse;
    import std.random : uniform;

    string testDirectory = "/tmp/.redhot-siren-sanitize-"
        ~ to!string(getpid()) ~ "-" ~ to!string(uniform(0, 1000000));
    mkdirRecurse(testDirectory);
    scope(exit) removeDirectoryBestEffort(testDirectory);

    string fifoPath = testDirectory ~ "/siren.fifo";
    assert(mkfifo(toStringz(fifoPath), octal!"600") == 0);

    int fifoFileDescriptor = open(toStringz(fifoPath), O_RDWR);
    assert(fifoFileDescriptor >= 0);
    scope(exit) close(fifoFileDescriptor);

    notifySiren(fifoPath, "info", "app|with|pipes",
                "title\nwith\nnewlines", "message\twith\ttabs");

    char[1024] readBuffer;
    ssize_t readCount = read(fifoFileDescriptor, readBuffer.ptr,
                             readBuffer.length);
    assert(readCount > 0);

    string receivedPayload = readBuffer[0 .. cast(size_t)readCount].idup;

    size_t pipeCount = 0;
    foreach (char character; receivedPayload) {
        if (character == '|') pipeCount++;
    }
    assert(pipeCount == 3,
           "expected exactly 3 field separators, got "
           ~ to!string(pipeCount));
}

// Payload longer than PIPE_BUF is truncated to 512 bytes (including '\n').
unittest
{
    import core.sys.posix.fcntl : O_RDWR, open;
    import core.sys.posix.sys.stat : mkfifo;
    import core.sys.posix.unistd : close, getpid, read;
    import std.conv : to;
    import std.file : mkdirRecurse;
    import std.random : uniform;

    string testDirectory = "/tmp/.redhot-siren-truncate-"
        ~ to!string(getpid()) ~ "-" ~ to!string(uniform(0, 1000000));
    mkdirRecurse(testDirectory);
    scope(exit) removeDirectoryBestEffort(testDirectory);

    string fifoPath = testDirectory ~ "/siren.fifo";
    assert(mkfifo(toStringz(fifoPath), octal!"600") == 0);

    int fifoFileDescriptor = open(toStringz(fifoPath), O_RDWR);
    assert(fifoFileDescriptor >= 0);
    scope(exit) close(fifoFileDescriptor);

    char[] mutableMessage;
    mutableMessage.length = 1000;
    mutableMessage[] = 'x';
    string longMessage = mutableMessage.idup;

    int result = notifySiren(fifoPath, "info", "app", "title", longMessage);
    assert(result == cast(int)ExitCode.ok);

    char[2048] readBuffer;
    ssize_t readCount = read(fifoFileDescriptor, readBuffer.ptr,
                             readBuffer.length);
    assert(readCount > 0);
    assert(cast(size_t)readCount <= 512,
           "payload exceeded PIPE_BUF: " ~ to!string(readCount) ~ " bytes");
    assert(readBuffer[cast(size_t)readCount - 1] == '\n',
           "truncated payload must end with newline");
}
