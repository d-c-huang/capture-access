import Darwin
import Foundation
import PageCaptureCore

// Map the parent's standard pipes to Chromium's private CDP descriptors.
// The process then becomes the installed client, so the parent owns its PID.
guard CommandLine.arguments.count == 2,
      let application = try? PageApplication(url: URL(fileURLWithPath: CommandLine.arguments[1])),
      dup2(STDIN_FILENO, 3) == 3, dup2(STDOUT_FILENO, 4) == 4 else { exit(70) }
let executable = application.executableURL.path
let null = open("/dev/null", O_RDWR)
guard null >= 0, dup2(null, STDIN_FILENO) >= 0, dup2(null, STDOUT_FILENO) >= 0 else { exit(71) }
if null > 4 { close(null) }
unsetenv("ELECTRON_RUN_AS_NODE")
unsetenv("NODE_OPTIONS")
var arguments = [strdup(executable), strdup("--remote-debugging-pipe"), nil]
arguments.withUnsafeMutableBufferPointer { buffer in
    _ = execv(executable, buffer.baseAddress!)
}
exit(72)
