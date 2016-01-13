library Cache;

import "dart:io";
import "dart:async";
import "dart:math" as math;
import "dart:isolate" as iso;
import "dart:convert";

/**
 * READ_FILE
 * > sends:
 *    - String filePath
 * > returns:
 *    - String filePath
 *    - String fileContents
 *    - String fileModified
 *
 */
enum isoCmds {
  READ_FILE
}

class Cache {
  //static final Map<String, String> _httpCache = <String, String>{}; // Isn't being used right now.
  static final Map<String, String> _fileCache = <String, String>{}; // {FilePath: FileContents}
  static final Map<String, String> _fileCacheModifiedId = <String, String>{}; // {FilePath: FileModified}
  static final Map<String, Completer> _isolateWaitingCompleterQueue = <String, Completer>{};
  static bool shouldBeVerbose = false;
  static iso.SendPort _isoSendPort;
  static bool _isAlreadyEstablishingIsolateConnection = false; /// Is _init() already in the process of connecting to the Isolate?
  static Duration timerIntervalWaitingForIsolateConnection = const Duration(milliseconds: 50);
  static Duration maxTimeToWaitForIsolateConnection = const Duration(milliseconds: 2000);

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
      } else if (stopWatch.elapsedMilliseconds > Cache.maxTimeToWaitForIsolateConnection.inMilliseconds) {
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
        if (Cache.shouldBeVerbose) print('cmd = isoCmds.READ_FILE');

        final String uniqueId = isoMessage['id'];
        final String filePath = isoMessage['data']['filePath'];
        final String fileContents = isoMessage['data']['fileContents'];
        final String fileModified = isoMessage['data']['fileModified'];

        Cache._fileCache[filePath] = fileContents;
        Cache._fileCacheModifiedId[filePath] = fileModified;

        // Was there a completer waiting for this Isolate/Thread to return a response?
        if (Cache._isolateWaitingCompleterQueue.containsKey(uniqueId)) {
          if (Cache.shouldBeVerbose) print('Fulfilling a queued Future after getting a response from the Isolate.');

          Cache._isolateWaitingCompleterQueue[uniqueId].complete();
        }

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

    final Completer<Null> completer = new Completer<Null>();
    final String filePath = resourceFile.toFilePath();

    // If this has already been added to the cache, do nothing and return.
    if (Cache._fileCache.containsKey(filePath)) {
      completer.complete();
    } else {
      if (shouldPreCache) {
        if (Cache._isoSendPort == null) {
          await Cache._init();
        }

        // Generate a unique Id for indexing the Completer at for having the Isolate response
        // handler complete it when it gets a value from the Isolate.
        final String _uniqueId = Cache._generateUniqueId();

        // Set the Completer at its index
        Cache._isolateWaitingCompleterQueue[_uniqueId] = completer;

        // Message the Isolate to read the file
        Cache._isoSendPort.send(<String, dynamic>{
          "cmd": isoCmds.READ_FILE,
          "id": _uniqueId,
          "data": {
            "filePath": filePath
          }
        });
      } else {
        // Create an entry that this file should be cached, but the contents are not known yet
        // (either caching in separate thread or waiting until the file is first wanted before
        // reading and caching)
        Cache._fileCache[filePath] = null;

        completer.complete();
      }
    }

    return completer.future;
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
      final File _resourceFile = new File.fromUri(resourceUri);
      final FileStat _fileStat = await _resourceFile.stat();
      final String _fileModified = _fileStat.modified.toString();
      final int _fileSize = _fileStat.size;
      final String _fileStatComparisonStr = '$_fileModified.$_fileSize';

      // Has this file already been read and cached at this point?
      if (Cache._fileCache[filePath] != null &&
          Cache._fileCacheModifiedId[filePath] != null)
      {
        // Has this file changed since it was cached
        if (_fileStatComparisonStr != Cache._fileCacheModifiedId[filePath]) {
          if (Cache.shouldBeVerbose) print('Cache::matchFile(File) - Was going to read from a cached copy from memory, but the file updated and is being recached.');

          final String _fileContents = await Cache._readFile(_resourceFile);

          Cache._fileCache[filePath] = _fileContents;
          Cache._fileCacheModifiedId[filePath] = _fileStatComparisonStr;

          return _fileContents;
        } else { // The file hasn't changed; read from memory.
          if (Cache.shouldBeVerbose) print('Cache::matchFile(File) - Reading from a cached copy from memory');

          return Cache._fileCache[filePath];
        }
      } else {
        if (Cache.shouldBeVerbose) print('Cache::matchFile(File) - Reading freshly from the Filesystem');

        final String _fileContents = await Cache._readFile(_resourceFile);

        Cache._fileCache[filePath] = _fileContents;
        Cache._fileCacheModifiedId[filePath] = _fileStatComparisonStr;

        return _fileContents;
      }
    }

    return null;
  }

  //Future delete() async {}

  //Future keys() async {}

  static Future<String> _readFile(final File file) async {
    if (Cache.shouldBeVerbose) print('Cache::_readFile(File)');

    final Completer<String> completer = new Completer<String>();

    if (await file.exists()) {
      final StringBuffer buffer = new StringBuffer();

      // Read as UTF-8 by default
      file.openRead().transform(UTF8.decoder).listen((String data) {
        buffer.write(data);
      }, onDone: () {
        completer.complete(buffer.toString());

        // Clean up the buffer pieces for good measure.
        buffer.clear();
      }, onError: (err) {
        // If there was a FormatException with the UTF8 reading, try reading as Latin1.
        if (err is FormatException) {
          // Read file as LATIN1
          file.openRead().transform(LATIN1.decoder).listen((String data) {
            buffer.write(data);
          }, onDone: () {
            completer.complete(buffer.toString());

            // Clean up the buffer pieces for good measure.
            buffer.clear();
          }, onError: (err) {
            throw err;
          });
        } else {
          throw err;
        }
      });
    } else {
      throw new Exception('Cache::_readFile(File): The file path provided does not point to a file that exists (${file.uri.path})');
    }

    return completer.future;
  }

  static const int MAX_NUMBER_OF_CONCURRENT_FILE_CONNECTIONS = 500;

  static void _isolateEntryPoint(final iso.SendPort sendPort) {
    if (Cache.shouldBeVerbose) print('Cache::_isolateEntryPoint(SendPort)');

    int numberOfOpenFileConnections = 0;

    final iso.ReceivePort receivePort = new iso.ReceivePort()
      ..listen((final Map<String, dynamic> messageFromMainThread) async {
        final isoCmds cmd = messageFromMainThread['cmd'];

        switch (cmd) {
          case isoCmds.READ_FILE:
            final String filePath = messageFromMainThread['data']['filePath'];
            final File _file = new File(filePath);

            final FileStat fileStat = await _file.stat();
            final String fileModified = fileStat.modified.toString();
            final int fileSize = fileStat.size;

            // Temporarily: don't read a file if more than 500 other file connections are
            // already open; wait instead.
            if (numberOfOpenFileConnections >= Cache.MAX_NUMBER_OF_CONCURRENT_FILE_CONNECTIONS) {
              final Stopwatch stopWatch = new Stopwatch()..start();
              final int maxMsToWait = 30000; // Temporary fix: 30s

              new Timer.periodic(const Duration(milliseconds: 200), (final Timer timer) async {
                // Cancel if the max timeout has been reached.
                if (stopWatch.elapsedMilliseconds > maxMsToWait) {
                  stopWatch.stop();
                  timer.cancel();
                }

                if (numberOfOpenFileConnections < Cache.MAX_NUMBER_OF_CONCURRENT_FILE_CONNECTIONS) {
                  numberOfOpenFileConnections++; // Increment the number of open file connections.
                  final String _fileContents = await Cache._readFile(_file);
                  numberOfOpenFileConnections--; // Decrement the number of open file connections since the task has completed.

                  sendPort.send(<String, dynamic>{
                    'cmd': cmd,
                    'id': messageFromMainThread['id'],
                    'data': <String, String>{
                      'filePath': filePath,
                      'fileContents': _fileContents,
                      'fileModified': '$fileModified.$fileSize'
                    }
                  });
                }
              });
            } else {
              numberOfOpenFileConnections++; // Increment the number of open file connections.
              final String _fileContents = await Cache._readFile(_file);
              numberOfOpenFileConnections--; // Decrement the number of open file connections since the task has completed.

              sendPort.send(<String, dynamic>{
                'cmd': cmd,
                'id': messageFromMainThread['id'],
                'data': <String, String>{
                  'filePath': filePath,
                  'fileContents': _fileContents,
                  'fileModified': '$fileModified.$fileSize'
                }
              });
            }

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

  static String _generateUniqueId() {
    final DateTime nowDateTime = new DateTime.now();
    final int randomInt1 = new math.Random().nextInt(100000);
    final int randomInt2 = new math.Random().nextInt(100000);
    final int randomInt3 = new math.Random().nextInt(100000);

    return '${nowDateTime}.$randomInt1.$randomInt2.$randomInt3';
  }
}