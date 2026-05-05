import 'dart:convert';
import 'dart:io';

const String _kLogPath = '/Users/austen/code/HC4RL/.cursor/debug.log';

void debugLog(String location, String message, Map<String, dynamic> data,
    String hypothesisId) {
  // #region agent log
  try {
    final line = jsonEncode({
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'location': location,
          'message': message,
          'data': data,
          'hypothesisId': hypothesisId,
          'sessionId': 'debug-session',
        }) +
        '\n';
    File(_kLogPath).writeAsStringSync(line, mode: FileMode.append);
  } catch (_) {}
  // #endregion
}
