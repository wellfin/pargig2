import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Simple Voice Input panel: tap the mic, speak, and the words appear in
/// the Transcribed Text box.
///
/// Deliberately minimal. Speech goes straight into the description text —
/// nothing is recorded to a file, uploaded, or played back, so there is no
/// clip to manage and no upload state to wait on. Recognition runs through
/// the phone's own recogniser, on-device, with no model download.
///
/// A Play button reads the box back with the phone's text-to-speech, so
/// the giver hears what workers will hear before posting. That is the same
/// synthesised voice Job Details uses, not a recording of them speaking.
///
/// The trade-off this makes, stated plainly: because Android hands the
/// microphone to a single consumer, a recogniser that listens live cannot
/// also record. Jobs posted through this panel therefore carry text only —
/// workers read the description rather than hearing the giver's voice. The
/// recording flow that does produce playable audio lives in
/// `voice_recorder.dart`, kept intact alongside this.
class VoiceDictationPanel extends StatefulWidget {
  /// The job description. Recognised words are written straight into it,
  /// and it stays editable so a misheard word can be fixed by hand.
  final TextEditingController description;

  /// Fired whenever the text changes, so the parent can rebuild.
  final VoidCallback onChanged;

  const VoiceDictationPanel({
    super.key,
    required this.description,
    required this.onChanged,
  });

  @override
  State<VoiceDictationPanel> createState() => _VoiceDictationPanelState();
}

class _VoiceDictationPanelState extends State<VoiceDictationPanel> {
  static const int _maxChars = 500;
  static const Duration _maxListen = Duration(minutes: 2);

  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _ready = false;
  bool _listening = false;
  bool _ttsReady = false;
  bool _speaking = false;
  String? _error;

  /// Whatever was in the box when this dictation started. Partial results
  /// arrive as the full phrase so far and would otherwise overwrite text
  /// the giver had already typed or dictated earlier.
  String _baseText = '';

  @override
  void dispose() {
    _speech.cancel();
    _tts.stop();
    super.dispose();
  }

  // Same voice settings as Job Details, so the giver's preview sounds
  // exactly like the worker's playback rather than subtly different.
  Future<void> _ensureTts() async {
    if (_ttsReady) return;
    _ttsReady = true;
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _speaking = false);
    });
    _tts.setCancelHandler(() {
      if (mounted) setState(() => _speaking = false);
    });
    _tts.setErrorHandler((_) {
      if (mounted) setState(() => _speaking = false);
    });
  }

  /// Reads the description box aloud, or stops if already speaking.
  Future<void> _togglePlayback() async {
    if (_speaking) {
      await _tts.stop();
      if (mounted) setState(() => _speaking = false);
      return;
    }
    final text = widget.description.text.trim();
    if (text.isEmpty) return;
    // The recogniser and the synthesiser both want the audio route;
    // speaking while still listening makes the mic hear the playback.
    if (_listening) await _stop();
    await _ensureTts();
    if (!mounted) return;
    setState(() => _speaking = true);
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> _toggle() async {
    if (_listening) {
      await _stop();
      return;
    }

    try {
      if (!_ready) {
        // Also prompts for the microphone permission the first time.
        _ready = await _speech.initialize(
          onStatus: (status) {
            // The engine stops itself after a pause — mirror that, or the
            // button stays stuck showing "Listening…".
            if ((status == 'done' || status == 'notListening') && mounted) {
              setState(() => _listening = false);
            }
          },
          onError: (_) {
            if (mounted) setState(() => _listening = false);
          },
        );
      }
      if (!mounted) return;
      if (!_ready) {
        setState(
          () => _error =
              'Speech recognition is unavailable on this device. You can '
              'type the description instead.',
        );
        return;
      }

      _baseText = widget.description.text.trim();
      setState(() {
        _listening = true;
        _error = null;
      });

      await _speech.listen(
        onResult: (result) {
          final words = result.recognizedWords.trim();
          if (words.isEmpty || !mounted) return;
          _write(_baseText.isEmpty ? words : '$_baseText $words');
        },
        listenOptions: stt.SpeechListenOptions(
          // Partials so the box fills in live while speaking, rather than
          // sitting empty until the whole phrase is finished.
          partialResults: true,
          cancelOnError: true,
          listenFor: _maxListen,
          pauseFor: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _listening = false;
        _error = 'Could not start speech recognition: $e';
      });
    }
  }

  Future<void> _stop() async {
    try {
      await _speech.stop();
    } catch (_) {
      // Nothing to stop, or the engine never started.
    }
    if (mounted) setState(() => _listening = false);
  }

  void _write(String text) {
    final capped = text.length > _maxChars
        ? text.substring(0, _maxChars)
        : text;
    widget.description.value = TextEditingValue(
      text: capped,
      selection: TextSelection.collapsed(offset: capped.length),
    );
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBEDBFF), width: 1.5),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: _toggle,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: _listening
                    ? const Color(0xFFDC2626)
                    : const Color(0xFF2B7FFF),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color:
                        (_listening
                                ? const Color(0xFFDC2626)
                                : const Color(0xFF2B7FFF))
                            .withAlpha(_listening ? 110 : 60),
                    blurRadius: _listening ? 20 : 12,
                    spreadRadius: _listening ? 2 : 0,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                _listening ? Icons.stop : Icons.mic,
                size: 40,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _listening ? 'Listening… tap to stop' : 'Tap to start recording',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF408EE0),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Describe your job requirements',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Color(0xFF155DFC)),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11.5,
                color: Color(0xFFDC2626),
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFBEDBFF), width: 0.8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Transcribed Text:',
                      style: TextStyle(fontSize: 12, color: Color(0xFF408EE0)),
                    ),
                    const Spacer(),
                    // Hear the description read back before posting — the
                    // same synthesised voice workers get on Job Details,
                    // so what the giver previews is what they receive.
                    _PlayButton(
                      speaking: _speaking,
                      // Nothing to read yet; a live button that does
                      // nothing reads as broken.
                      enabled: widget.description.text.trim().isNotEmpty,
                      onTap: _togglePlayback,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: widget.description,
                  maxLines: 4,
                  minLines: 2,
                  maxLength: _maxChars,
                  // Editable on purpose: the recogniser mishears often
                  // enough that not being able to correct a word would be
                  // worse than the text drifting from what was said.
                  onChanged: (_) => widget.onChanged(),
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF101828),
                    height: 1.43,
                  ),
                  decoration: const InputDecoration(
                    isCollapsed: true,
                    contentPadding: EdgeInsets.zero,
                    counterText: '',
                    hintText:
                        'Need complete deep cleaning of my 2BHK '
                        'apartment including kitchen and bathrooms.',
                    hintStyle: TextStyle(
                      fontSize: 14,
                      color: Color(0x801A1A1A),
                      height: 1.43,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Play / stop pill for the read-aloud preview. Mirrors the button on Job
/// Details so the same action looks the same on both sides.
class _PlayButton extends StatelessWidget {
  final bool speaking;
  final bool enabled;
  final VoidCallback onTap;
  const _PlayButton({
    required this.speaking,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = enabled ? const Color(0xFFFF6900) : const Color(0xFF9CA3AF);
    return Material(
      color: speaking
          ? const Color(0xFFFF6900)
          : (enabled ? const Color(0xFFFFEDD4) : const Color(0xFFF3F4F6)),
      borderRadius: BorderRadius.circular(100),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(100),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                speaking ? Icons.stop : Icons.play_arrow,
                size: 16,
                color: speaking ? Colors.white : fg,
              ),
              const SizedBox(width: 4),
              Text(
                speaking ? 'Stop' : 'Play',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: speaking ? Colors.white : fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
