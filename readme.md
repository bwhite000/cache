Cache
=====

A Dart package for caching Files through a multi-threaded system. The format is modeled
after the JavaScript ServiceWorker Cache Object.

Only Files are cacheable at the moment, but external resources will be possible
to cache locally in the near future.

Example
-------

More examples are located in the 'example/' directory of this package.

~~~dart
import "dart:async";
import "package:cache/cache.dart";

Future<Null> main() async {
  final Uri fileUri = new Uri.file('/Users/test/');

  await Cache.addFile(fileUri);

  final String fileContents = await Cache.matchFile(fileUri);
  print(fileContents);
}
~~~


Features and bugs
-----------------

Please file feature requests and bugs using the GitHub issue tracker for this repository.