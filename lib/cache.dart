library Cache;

import "dart:io";
import "dart:async";
import "dart:isolate" as iso;

/**
 * READ_FILE
 * > sends:
 *    - String filePath
 * > returns:
 *    - String filePath
 *    - String fileContents
 *
 */
enum isoCmds {
  READ_FILE
}

class Cache {
  //static final Map<String, String> _httpCache = <String, String>{}; // Isn't being used right now.
  static final Map<String, String> _fileCache = <String, String>{};
  static bool shouldBeVerbose = false;
  static iso.SendPort _isoSendPort;
  static bool _isAlreadyEstablishingIsolateConnection = false; /// Is _init() already in the process of connecting to the Isolate?
  static Duration timerIntervalWaitingForIsolateConnection = const Duration(milliseconds: 50);
  static Duration timeToWaitForIsolateConnection = const Duration(milliseconds: 1000);

  static Future<Null> _init() async {
    if (Cache.shouldBeVerbose) print('Cache::_init()');

    final Completer completer = new Completer();
    final Stopwatch stopWatch = new Stopwatch();

    // If this function gets called quickly back-to-back, don't try again to connect to
    // the Isolate thread that is already in the process of being connected to.
    if (Cache._isAlreadyEstablishingIsolateConnection == false) {
      Cache._isAlreadyEstablishingIsolateConnection = true;

      final iso.ReceivePort receivePort = new iso.ReceivePort()
        ..listen((final dynamic messageFromIsolate) {
          if (messageFromIsolate is iso.SendPort) {
            Cache._isoSendPort = messageFromIsolate;
          } else if (messageFromIsolate is Map<String, dynamic>) {
            Cache._handleMessageFromIsolate(messageFromIsolate);
          } else if (Cache.shouldBeVerbose) { // Is it okay to log out the unknown message type?
            print(messageFromIsolate);
          }
        });

      await iso.Isolate.spawn(Cache._isolateEntryPoint, receivePort.sendPort);
    }

    stopWatch.start();

    new Timer.periodic(Cache.timerIntervalWaitingForIsolateConnection, (final Timer timer) {
      if (Cache._isoSendPort != null) {
        timer.cancel();
        stopWatch.stop();

        completer.complete();
      } else if (stopWatch.elapsedMilliseconds > Cache.timeToWaitForIsolateConnection.inMilliseconds) {
        timer.cancel();
        stopWatch.stop();

        throw new Exception('Cache::addFile(Uri) - Not able to establish communication with the Caching thread.');
      }
    });

    return completer.future;
  }

  static void _handleMessageFromIsolate(final Map<String, dynamic> isoMessage) {
    if (Cache.shouldBeVerbose) print('Cache::_handleMessageFromIsolate(Map)');

    switch (isoMessage['cmd'] as isoCmds) {
      case isoCmds.READ_FILE:
        final String filePath = isoMessage['data']['filePath'];
        final String fileContents = isoMessage['data']['fileContents'];

        Cache._fileCache[filePath] = fileContents;
        break;
    }
  }

  //static Future matchAll() async {}

  /// The resource path provided should be an absolute path
  //static Future<Null> addExternalResource(final Uri requestUri, final Uri resourceUri) async {}

  static Future<Null> addFile(final Uri resourceFile, {
    final bool shouldPreCache: false
  }) async {
    if (Cache.shouldBeVerbose) print('Cache::addFile(Uri)');

    final String filePath = resourceFile.toFilePath();

    // If this has already been added to the cache, do nothing and return.
    if (Cache._fileCache.containsKey(filePath)) {
      return;
    }

    if (shouldPreCache) {
      if (Cache._isoSendPort == null) {
        await Cache._init();
      }

      Cache._isoSendPort.send(<String, dynamic>{
        "cmd": isoCmds.READ_FILE,
        "data": {
          "filePath": filePath
        }
      });
    } else {
      Cache._fileCache[filePath] = null;
    }
  }

  static Future<Null> addAllFiles(final List<Uri> uriList, {
    final bool shouldPreCache: false
  }) async {
    final List<Future> listOfFutures = <Future>[];

    uriList.forEach((final Uri uri) {
      listOfFutures.add(Cache.addFile(uri, shouldPreCache: shouldPreCache));
    });

    await Future.wait(listOfFutures);
  }

  // Provide the resource path AND what the data should be.
  //Future<Null> putFile(final Uri requestUri) async {}

  static Future<String> matchFile(final Uri resourceUri) async {
    if (Cache.shouldBeVerbose) print('Cache::matchFile(File)');

    final String filePath = resourceUri.toFilePath();

    if (Cache._fileCache.containsKey(filePath)) {
      // Has this file already been read and cached at this point?
      if (Cache._fileCache[filePath] != null) {
        if (Cache.shouldBeVerbose) print('Cache::matchFile(File) - Reading from a cached copy from memory');

        return Cache._fileCache[filePath];
      } else {
        if (Cache.shouldBeVerbose) print('Cache::matchFile(File) - Reading freshly from the Filesystem');

        final File _resourceFile = new File.fromUri(resourceUri);
        final String _fileContents = await Cache._readFile(_resourceFile);

        Cache._fileCache[filePath] = _fileContents;

        return _fileContents;
      }
    }

    return null;
  }

  //Future delete() async {}

  //Future keys() async {}

  static Future<String> _readFile(final File file) async {
    if (Cache.shouldBeVerbose) print('Cache::_readFile(File)');

    if (await file.exists()) {
      return await file.readAsString();
    } else {
      throw new Exception('Cache::_readFile(File): The file path provided does not point to a file that exists (${file.uri.path})');
    }
  }

  static void _isolateEntryPoint(final iso.SendPort sendPort) {
    if (Cache.shouldBeVerbose) print('Cache::_isolateEntryPoint(SendPort)');

    final iso.ReceivePort receivePort = new iso.ReceivePort()
      ..listen((final Map<String, dynamic> messageFromMainThread) async {
        final isoCmds cmd = messageFromMainThread['cmd'];

        switch (cmd) {
          case isoCmds.READ_FILE:
            final String filePath = messageFromMainThread['data']['filePath'];
            final String fileContents = await Cache._readFile(new File(filePath));

            sendPort.send(<String, dynamic>{
              'cmd': cmd,
              'data': <String, String>{
                'filePath': filePath,
                'fileContents': fileContents
              }
            });
            break;

          default:
            if (Cache.shouldBeVerbose) {
              print('Cache::_isolateEntryPoint(SendPort) - Unmatched "cmd" value in the messaged passed to this Isolate');
              print(messageFromMainThread);
            }
        }
      });

    // Send the sendPort to the main thread to establish communication
    sendPort.send(receivePort.sendPort);
  }
}