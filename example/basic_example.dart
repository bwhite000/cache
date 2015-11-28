import "dart:async";
import "package:cache/cache.dart";

Future<Null> main() async {
  final Uri fileUri = new Uri.file('/Users/test/');

  await Cache.addFile(fileUri);

  final String fileContents = await Cache.matchFile(fileUri);
  print(fileContents);
}