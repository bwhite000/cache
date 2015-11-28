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
  static final Map<String, String> _httpCache = {};
  static final Map<String, String> _fileCache = {};
  static bool shouldBeVerbose = true;
  static iso.SendPort _isoSendPort;

  Future<Null> _init() async {
    final iso.ReceivePort receivePort = new iso.ReceivePort()
        ..listen((final dynamic messageFromIsolate) {
          if (messageFromIsolate is iso.SendPort) {
            Cache._isoSendPort = messageFromIsolate;
          } else if (messageFromIsolate is Map<String, dynamic>) {
            Cache._handleIsolateMessage(messageFromIsolate);
          } else if (Cache.shouldBeVerbose) { // Is it okay to log out the unknown message type?
            print(messageFromIsolate);
          }
        });

    iso.Isolate.spawn(Cache._isolateEntryPoint, receivePort.sendPort);
  }

  static void _handleIsolateMessage(final Map<String, dynamic> isoMessage) {
    switch (isoMessage['cmd'] as isoCmds) {
      case isoCmds.READ_FILE:
        final String filePath = isoMessage['filePath'];
        final String fileContents = isoMessage['fileContents'];

        Cache._fileCache[filePath] = fileContents;
        break;
    }
  }

  static Future<String> matchFile(final Uri resourceFile) async {
    if (Cache.shouldBeVerbose) print('Cache::matchFile(File)');

    if (Cache._fileCache.containsKey(resourceFile.uri.path)) {
      // Has this file already been read and cached at this point?
      if (Cache._fileCache[resourceFile.uri.path] != null) {
        return Cache._fileCache[resourceFile.uri.path];
      } else {
        final String _fileContents = await Cache._readFile(resourceFile);
        Cache._fileCache[resourceFile.uri.path] = _fileContents;

        return _fileContents;
      }
    }

    return null;
  }

  //static Future matchAll() async {}

  /// The resource path provided should be an absolute path
  //static Future<Null> addExternalResource(final Uri requestUri, final Uri resourceUri) async {}

  static Future<Null> addFile(final Uri resourceFile, {
    final bool shouldPreCache: false
  }) async {
    if (Cache.shouldBeVerbose) print('Cache::addFile(File)');

    final String filePath = resourceFile.path;

    // If this has already been added to the cache, do nothing and return.
    if (Cache._fileCache.containsKey(filePath)) {
      return;
    }

    if (shouldPreCache) {
      Cache._isoSendPort.send(<String, dynamic>{
        'cmd': isoCmds.READ_FILE,
        'data': {
          'filePath': filePath
        }
      });
    } else {
      Cache._fileCache[filePath] = null;
    }
  }

  static Future<Null> addAllFiles(final List<File> fileList, {
    final bool shouldPreCache: false
  }) async {
    final List<Future> listOfFutures = <Future>[];

    fileList.forEach((final File file) {
      listOfFutures.add(Cache.addFile(file, shouldPreCache: shouldPreCache));
    });

    await Future.wait(listOfFutures);
  }

  // Provide the resource path AND what the data should be.
  //Future<Null> putFile(final Uri requestUri) async {}

  //Future delete() async {}

  //Future keys() async {}

  static Future<String> _readFile(final File file) async {
    if (Cache.shouldBeVerbose) print('Cache::_readFile(File)');

    if (await file.exists()) {
      return await file.readAsString();
    } else {
      throw new Exception('Cache.add(): The file path provided does not point to a file that exists (${file.uri.path})');
    }
  }

  static void _isolateEntryPoint(final iso.SendPort sendPort) {
    final iso.ReceivePort receivePort = new iso.ReceivePort()
      ..listen((final Map<String, dynamic> messageFromMainThread) async {
        final isoCmds cmd = messageFromMainThread['cmd'];

        switch (cmd as isoCmds) {
          case isoCmds.READ_FILE:
            final String filePath = messageFromMainThread['filePath'];
            final String fileContents = await Cache._readFile(new File(filePath));

            sendPort.send(<String, dynamic>{
              'cmd': cmd,
              'data': {
                'filePath': filePath,
                'fileContents': fileContents
              }
            });
            break;
        }
      });

    // Send the sendPort to the main thread to establish communication
    sendPort.send(receivePort.sendPort);
  }
}