library dslink.system.utils;

import "dart:async";
import "dart:convert";
import "dart:io";

import "package:path/path.dart" as pathlib;

typedef void ProcessHandler(Process process);
typedef void OutputHandler(String str);

Stdin get _stdin => stdin;

class BetterProcessResult extends ProcessResult {
  final String output;

  BetterProcessResult(int pid, int exitCode, stdout, stderr, this.output)
  : super(pid, exitCode, stdout, stderr);
}

Future<BetterProcessResult> exec(String executable,
                                 {List<String> args: const [], String workingDirectory,
                                 Map<String, String> environment, bool includeParentEnvironment: true,
                                 bool runInShell: false, stdin, ProcessHandler handler,
                                 OutputHandler stdoutHandler, OutputHandler stderrHandler,
                                 OutputHandler outputHandler, File outputFile, bool inherit: false,
                                 bool writeToBuffer: false}) async {
  IOSink raf;

  if (outputFile != null) {
    if (!(await outputFile.exists())) {
      await outputFile.create(recursive: true);
    }

    raf = await outputFile.openWrite(mode: FileMode.APPEND);
  }

  try {
    Process process = await Process.start(executable, args,
    workingDirectory: workingDirectory,
    environment: environment,
    includeParentEnvironment: includeParentEnvironment,
    runInShell: runInShell);

    if (raf != null) {
      await raf.writeln(
        "[${currentTimestamp}] == Executing ${executable} with arguments ${args} (pid: ${process.pid}) ==");
    }

    var buff = new StringBuffer();
    var ob = new StringBuffer();
    var eb = new StringBuffer();

    process.stdout.transform(UTF8.decoder).listen((str) async {
      if (writeToBuffer) {
        ob.write(str);
        buff.write(str);
      }

      if (stdoutHandler != null) {
        stdoutHandler(str);
      }

      if (outputHandler != null) {
        outputHandler(str);
      }

      if (inherit) {
        stdout.write(str);
      }

      if (raf != null) {
        await raf.writeln("[${currentTimestamp}] ${str}");
      }
    });

    process.stderr.transform(UTF8.decoder).listen((str) async {
      if (writeToBuffer) {
        eb.write(str);
        buff.write(str);
      }

      if (stderrHandler != null) {
        stderrHandler(str);
      }

      if (outputHandler != null) {
        outputHandler(str);
      }

      if (inherit) {
        stderr.write(str);
      }

      if (raf != null) {
        await raf.writeln("[${currentTimestamp}] ${str}");
      }
    });

    if (handler != null) {
      handler(process);
    }

    if (stdin != null) {
      if (stdin is Stream) {
        stdin.listen(process.stdin.add, onDone: process.stdin.close);
      } else if (stdin is List) {
        process.stdin.add(stdin);
      } else {
        process.stdin.write(stdin);
        await process.stdin.close();
      }
    } else if (inherit) {
      _stdin.listen(process.stdin.add, onDone: process.stdin.close);
    }

    var code = await process.exitCode;
    var pid = process.pid;

    if (raf != null) {
      await raf
      .writeln("[${currentTimestamp}] == Exited with status ${code} ==");
      await raf.flush();
      await raf.close();
    }

    return new BetterProcessResult(
      pid, code, ob.toString(), eb.toString(), buff.toString());
  } finally {
    if (raf != null) {
      await raf.flush();
      await raf.close();
    }
  }
}

Future<String> findExecutable(String name) async {
  var paths =
  Platform.environment["PATH"].split(Platform.isWindows ? ";" : ":");
  var tryFiles = [name];

  if (Platform.isWindows) {
    tryFiles.addAll(["${name}.exe", "${name}.bat"]);
  }

  for (var p in paths) {
    if (Platform.environment.containsKey("HOME")) {
      p = p.replaceAll("~/", Platform.environment["HOME"]);
    }

    var dir = new Directory(pathlib.normalize(p));

    if (!(await dir.exists())) {
      continue;
    }

    for (var t in tryFiles) {
      var file = new File("${dir.path}/${t}");

      if (await file.exists()) {
        return file.path;
      }
    }
  }

  return null;
}

Future<bool> isPortOpen(int port, {String host: "0.0.0.0"}) async {
  try {
    ServerSocket server = await ServerSocket.bind(host, port);
    await server.close();
    return true;
  } catch (e) {
    return false;
  }
}

String get currentTimestamp {
  return new DateTime.now().toString();
}

String fseType(FileSystemEntity entity) {
  if (entity is Directory) {
    return "directory";
  } else if (entity is File) {
    return "file";
  } else if (entity is Link) {
    return "link";
  }

  return "unknown";
}
