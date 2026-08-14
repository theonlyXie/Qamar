import 'package:speech_to_text/speech_to_text.dart';

/// Real dictation, using the platform's own speech recogniser.
///
/// This replaces a placeholder that waited 1.5 seconds and then inserted a
/// scripted sentence — which looked like it worked and never did.
///
/// Nothing is sent to a server by this app: Android's SpeechRecognizer and
/// iOS's Speech framework do the work, under the microphone permission the
/// user grants. Egyptian Arabic is requested explicitly as `ar-EG`, falling
/// back to whatever the device offers if that locale is not installed.
class Dictation {
  final SpeechToText _speech = SpeechToText();
  bool _ready = false;

  /// Whether the device can actually listen. False on a device with no
  /// recogniser, or when the user refuses the microphone — the caller must
  /// offer typing instead rather than leaving a dead button.
  bool get available => _ready && _speech.isAvailable;
  bool get listening => _speech.isListening;

  /// Asks for permission and initialises the recogniser. Safe to call more
  /// than once; returns false rather than throwing when unavailable.
  Future<bool> prepare({void Function(String status)? onStatus, void Function(String error)? onError}) async {
    if (_ready) return _speech.isAvailable;
    try {
      _ready = await _speech.initialize(
        onStatus: (s) => onStatus?.call(s),
        onError: (e) => onError?.call(e.errorMsg),
      );
    } catch (e) {
      onError?.call('$e');
      _ready = false;
    }
    return _ready;
  }

  /// The locale to ask for, given the app's language. Egyptian Arabic where
  /// available, since the whole product speaks it.
  Future<String?> _localeFor(String lang) async {
    final wanted = lang == 'ar' ? 'ar_EG' : 'en_US';
    try {
      final locales = await _speech.locales();
      for (final l in locales) {
        if (l.localeId.replaceAll('-', '_') == wanted) return l.localeId;
      }
      // Fall back to any dialect of the right language before giving up.
      final prefix = lang == 'ar' ? 'ar' : 'en';
      for (final l in locales) {
        if (l.localeId.startsWith(prefix)) return l.localeId;
      }
    } catch (_) {
      // Locale enumeration is best-effort; the recogniser picks a default.
    }
    return null;
  }

  /// Starts listening. [onResult] fires repeatedly with the words so far, and
  /// a final time when the recogniser decides the user has stopped.
  Future<bool> start({
    required String lang,
    required void Function(String text, bool isFinal) onResult,
  }) async {
    if (!await prepare()) return false;
    final localeId = await _localeFor(lang);
    await _speech.listen(
      localeId: localeId,
      onResult: (r) => onResult(r.recognizedWords, r.finalResult),
      listenOptions: SpeechListenOptions(
        // Meals are short. Partial results let the orb show the words landing
        // as they are spoken, which is what makes it feel alive.
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
      ),
      pauseFor: const Duration(seconds: 3),
      listenFor: const Duration(seconds: 30),
    );
    return true;
  }

  Future<void> stop() => _speech.stop();
  Future<void> cancel() => _speech.cancel();
}
