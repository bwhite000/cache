Cache Changelog
===============

v0.0.5 (1.12.2016)
------------------
* __Cache:__ Changed the `_readFile()` method to use an IOSink that can be closed out while
  reading a file since the former usage of `readAsString()` was leaving too many filesystem
  entities open and was throwing a top-level OS error.

v0.0.4 (12.20.2015)
-----------------
* __Cache:__ Changes to \_readFile() to support reading non-utf-8 encoded filesystem files.

v0.0.3 (12.19.2015)
-----------------
* __Cache:__ If the cached file has updated since it was cached, the cache will now be
  updated with the new file contents.
* __Cache:__ The `addFile()` method will now return a Future that will either complete
  immediately for simply adding a file to be cached in the future, or complete later for
  files set to be precached after the Isolate has read its data and stored it in memory;
  e.g. no more having to add `Timer` after `addFile` to wait for it to hopefully Cache in
  that time.
* __Cache:__ In cases where a file's value is quickly changed more than once in the same
  second, the file stat's modified value will still only be granular down to the second,
  not part of that second, so the file size is being used to also check if the file's value
  has changed in addition to the modified date value.
* Various performance optimizations and fixes.
* __Cache:__ Bumped up the `maxTimeToWaitForIsolateConnection` from 1 second to 2 seconds
  to err on the safe side for the default value, even though the developer can bump it higher,
  if needed.
* __ReadMe:__ Update the code example and added a section asking for other developers to let
  me know if the package is able to help them make a project using it.
* __Example (basic_example.dart):__ Minor updates to code and comments for clarity.

v0.0.2 (12.12.2015)
-------------------
* __Cache:__ Update addFile, addFiles, matchFile, \_init, and the Isolate communication to
  begin functioning (no longer just a roughly coded concept); optimized a lot of features
  to wait for the Isolate thread to establish, and only wait for around as long as needed;
  still can be better improved, though.
* __Example (basic_example.dart):__ Update the code with comments and formatted it to be an
  actually working example with a file in a subdirectory to actually read data out of and
  output in the console log.
* __Cache:__ Switched the .shouldBeVerbose property to be 'false' by default.
* Some more useful comments where needed.

v0.0.1 (11.28.2015)
-------------------
* Project started! (11.27.2015)
* Basic functionality for addFile and matchFile methods.
* Implemented multi-threading with an Isolate for reading the files from the
  FileSystem.