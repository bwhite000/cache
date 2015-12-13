import "dart:io";
import "dart:async";
import "package:cache/cache.dart";

Future<Null> main() async {
  // Create the file to the path of the text file that this code example will read data from.
  final Uri fileUri = Platform.script.resolve('../example/test_text_files/test.txt');

  // Set the Cache to be descriptive and use generous logging.
  Cache.shouldBeVerbose = true;

  // Add the file to the Cache as an item and have it be read into memory by the Isolate
  // thread immediately, not just when first needed in the future.
  await Cache.addFile(fileUri, shouldPreCache: true);

  // Wait a short time for Cache's Isolate to read the file and transfer the data back to the
  // main Isolates's in-memory storage cache.
  new Timer(const Duration(milliseconds: 300), () async {
    final String fileContents = await Cache.matchFile(fileUri);

    // Log the contents of the file that was Cached.
    print(fileContents);

    // Tell the script to explicitly exit since the Isolate connection in Cache holds the process
    // from exiting on its own (this is expected behavior and not unwanted).
    exit(0);
  });
}