package redhot.core;

import java.nio.file.Path;
import java.util.List;

/**
 * Class-loading warmup for Application Class-Data Sharing (Handoff_2.md §2).
 * Called once at install time to dump {@code redhot.jsa}. Every public class
 * is referenced so the archive captures their loaded state.
 */
public final class WarmupMain {

    private WarmupMain() {
    }

    public static void main(String[] args) {
        RParse.parseFlatKeyValue("");
        RParse.resolveConfigValue("k", List.of(List.of()));
        RParse.expandHomePrefix("~/x", "/home/user");
        RTheme.loadTheme(Path.of("/nonexistent/theme.conf"));
        RState.writeAtomic(Path.of("/nonexistent/target"), "");
        RState.readRecentFiles(Path.of("/tmp"));
        RSiren.notifySiren(Path.of("/nonexistent/siren.fifo"),
                "info", "warmup", "t", "m");
        System.out.println("redhot-core warmup complete");
    }
}
