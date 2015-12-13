Cache Changelog
===============

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