package redhot.core;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.channels.FileChannel;
import java.nio.channels.FileLock;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.nio.file.StandardOpenOption;
import java.util.ArrayList;
import java.util.List;

/**
 * Atomic state write and recent-files management (Handoff.md §4.3).
 * Mirrors {@code writeAtomic} in {@code infra.d} and the
 * current_dir / current_file / recent_files helpers in {@code services.d}.
 */
public final class RState {

    private static final int RECENT_FILES_MAX = 50;

    private RState() {
    }

    /**
     * Write {@code data} to {@code targetPath} atomically.
     *
     * <p>Sequence: {@code FileChannel.lock()} on {@code <target>.lock} →
     * temp file via {@link Files#createTempFile} → write →
     * {@link FileChannel#force force(true)} → {@link Files#move} with
     * {@link StandardCopyOption#ATOMIC_MOVE} → best-effort parent fsync →
     * release lock.
     */
    public static ExitCode writeAtomic(Path targetPath, String data) {
        if (targetPath == null || data == null) {
            return ExitCode.USAGE;
        }
        Path parentDirectory = targetPath.getParent();
        if (parentDirectory == null || !Files.exists(parentDirectory)) {
            return ExitCode.IO_ERROR;
        }

        Path lockPath = Path.of(targetPath.toString() + ".lock");

        try (FileChannel lockChannel = FileChannel.open(lockPath,
                StandardOpenOption.CREATE, StandardOpenOption.WRITE);
             FileLock ignoredLock = lockChannel.lock()) {

            Path temporaryPath = Files.createTempFile(
                    parentDirectory, ".redhot-state.", null);
            boolean renameCompleted = false;

            try {
                byte[] payloadBytes = data.getBytes(StandardCharsets.UTF_8);
                try (FileChannel temporaryChannel = FileChannel.open(temporaryPath,
                        StandardOpenOption.WRITE)) {
                    temporaryChannel.write(ByteBuffer.wrap(payloadBytes));
                    temporaryChannel.force(true);
                }

                Files.move(temporaryPath, targetPath,
                        StandardCopyOption.REPLACE_EXISTING,
                        StandardCopyOption.ATOMIC_MOVE);
                renameCompleted = true;

                // Best-effort parent fsync. FileChannel may refuse to open a
                // directory on some platforms; if that happens we skip it.
                // ATOMIC_MOVE already guarantees a durable rename on Linux
                // and FreeBSD, so this is belt-and-suspenders.
                try (FileChannel parentChannel = FileChannel.open(parentDirectory,
                        StandardOpenOption.READ)) {
                    parentChannel.force(true);
                } catch (IOException ignoredFsync) {
                    // best effort
                }

                return ExitCode.OK;
            } finally {
                if (!renameCompleted) {
                    try {
                        Files.deleteIfExists(temporaryPath);
                    } catch (IOException ignoredDelete) {
                    }
                }
            }
        } catch (IOException ioException) {
            return ExitCode.IO_ERROR;
        }
    }

    /**
     * Read {@code ~/.local/state/redhot/current_dir}, or {@code null} if
     * absent or empty.
     */
    public static String readCurrentDirectory(Path stateDirectory) {
        return readSingleLineFile(stateDirectory.resolve("current_dir"));
    }

    public static ExitCode writeCurrentDirectory(Path stateDirectory,
                                                 String directoryPath) {
        if (stateDirectory == null) return ExitCode.PRECONDITION;
        return writeAtomic(stateDirectory.resolve("current_dir"),
                directoryPath + "\n");
    }

    public static String readCurrentFile(Path stateDirectory) {
        return readSingleLineFile(stateDirectory.resolve("current_file"));
    }

    public static ExitCode writeCurrentFile(Path stateDirectory,
                                            String filePath) {
        if (stateDirectory == null) return ExitCode.PRECONDITION;
        return writeAtomic(stateDirectory.resolve("current_file"),
                filePath + "\n");
    }

    public static List<String> readRecentFiles(Path stateDirectory) {
        if (stateDirectory == null) return List.of();
        Path targetPath = stateDirectory.resolve("recent_files");
        if (!Files.exists(targetPath)) return List.of();
        try {
            return Files.readAllLines(targetPath).stream()
                    .map(String::strip)
                    .filter(line -> !line.isEmpty())
                    .toList();
        } catch (IOException ioException) {
            return List.of();
        }
    }

    /**
     * Prepend {@code filePath} to recent_files, deduplicate, truncate to
     * {@link #RECENT_FILES_MAX}, and write atomically.
     */
    public static ExitCode appendRecentFile(Path stateDirectory,
                                            String filePath) {
        if (stateDirectory == null) return ExitCode.PRECONDITION;
        if (filePath == null || filePath.isEmpty()) return ExitCode.USAGE;

        List<String> updatedEntries = new ArrayList<>();
        updatedEntries.add(filePath);
        for (String existingEntry : readRecentFiles(stateDirectory)) {
            if (existingEntry.equals(filePath)) continue;
            if (updatedEntries.size() >= RECENT_FILES_MAX) break;
            updatedEntries.add(existingEntry);
        }

        StringBuilder serialized = new StringBuilder();
        for (String entry : updatedEntries) {
            serialized.append(entry).append('\n');
        }

        return writeAtomic(stateDirectory.resolve("recent_files"),
                serialized.toString());
    }

    private static String readSingleLineFile(Path targetPath) {
        if (!Files.exists(targetPath)) return null;
        try {
            String content = Files.readString(targetPath).strip();
            return content.isEmpty() ? null : content;
        } catch (IOException ioException) {
            return null;
        }
    }
}
