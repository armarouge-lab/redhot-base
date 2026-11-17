package redhot.core;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.channels.FileChannel;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

/**
 * Siren FIFO notification (Handoff.md §4.4). Mirrors {@code notifySiren}
 * in {@code infra.d}.
 *
 * <p><strong>Design note.</strong> Java's {@link FileChannel#open} has no
 * portable equivalent of {@code O_NONBLOCK}. Opening a FIFO for writing
 * without a reader would block the calling thread indefinitely. To honour
 * the fail-silent contract (return {@link ExitCode#OK} even without a
 * reader), we run the write in a daemon thread and give up after
 * {@code OPEN_TIMEOUT_MILLISECONDS}. The thread may leak when no reader is
 * present; this is bounded and acceptable for short-lived processes like
 * Imp. Long-running TUI apps should call the D implementation in
 * {@code libredhot.a} instead.
 */
public final class RSiren {

    private static final int MAX_PAYLOAD_BYTES = 512;
    private static final long OPEN_TIMEOUT_MILLISECONDS = 100L;

    private RSiren() {
    }

    public static ExitCode notifySiren(Path fifoPath, String level,
                                       String appName, String title,
                                       String message) {
        if (fifoPath == null || !Files.exists(fifoPath)) {
            return ExitCode.OK;
        }

        String sanitizedPayload = sanitizeSirenField(level) + "|"
                + sanitizeSirenField(appName) + "|"
                + sanitizeSirenField(title) + "|"
                + sanitizeSirenField(message) + "\n";

        if (sanitizedPayload.length() > MAX_PAYLOAD_BYTES) {
            sanitizedPayload = sanitizedPayload.substring(0, MAX_PAYLOAD_BYTES - 1) + "\n";
        }
        byte[] payloadBytes = sanitizedPayload.getBytes(StandardCharsets.UTF_8);

        AtomicReference<ExitCode> resultCode = new AtomicReference<>(ExitCode.OK);
        CountDownLatch completionLatch = new CountDownLatch(1);

        Thread writerThread = new Thread(() -> {
            try (FileChannel channel = FileChannel.open(fifoPath, StandardOpenOption.WRITE)) {
                channel.write(ByteBuffer.wrap(payloadBytes));
                resultCode.set(ExitCode.OK);
            } catch (IOException ioException) {
                resultCode.set(ExitCode.IO_ERROR);
            } finally {
                completionLatch.countDown();
            }
        }, "redhot-siren-writer");
        writerThread.setDaemon(true);
        writerThread.start();

        try {
            if (completionLatch.await(OPEN_TIMEOUT_MILLISECONDS, TimeUnit.MILLISECONDS)) {
                return resultCode.get();
            }
        } catch (InterruptedException interruptedException) {
            Thread.currentThread().interrupt();
        }
        return ExitCode.OK;
    }

    private static String sanitizeSirenField(String field) {
        if (field == null) {
            return "";
        }
        StringBuilder sanitized = new StringBuilder(field.length());
        for (int characterIndex = 0; characterIndex < field.length(); characterIndex++) {
            char character = field.charAt(characterIndex);
            switch (character) {
                case '\n':
                case '\r':
                case '\t':
                case '|':
                    sanitized.append(' ');
                    break;
                default:
                    sanitized.append(character);
                    break;
            }
        }
        return sanitized.toString();
    }
}
