import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
// SPEECH-TO-TEXT — TEMPORARILY DISABLED. Every block below marked
// "SPEECH-TO-TEXT" is parked, not deleted: the recorder is back to plain
// capture → upload → playback, which is all the worker's Job Details
// screen needs. Un-comment these imports and those blocks to restore it.
// import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../api/home_api.dart';
import '../services/speech_file.dart';
// The ~98 MB in-app Whisper model stays parked — SpeechFile below gets the
// same one-take result from the phone's own recogniser with no download.
// import '../services/offline_transcriber.dart';
// import '../services/speech_model.dart';

/// WhatsApp-style voice recorder.
///
/// Captures the microphone straight to a 16 kHz mono `.wav` on disk and
/// plays that exact file back. The audio is never synthesised or
/// regenerated, so tone, accent, pauses, hesitation and background sound
/// survive byte-for-byte:
///
///   mic -> .wav on disk -> upload -> same bytes streamed back
///
/// Speech-to-text over that same file is TEMPORARILY DISABLED — the
/// transcription code is commented out rather than removed (search
/// "SPEECH-TO-TEXT" in this file and in post_job_screen.dart to bring it
/// back). Right now the clip is the description: the giver records it and
/// the worker plays it on Job Details, with the typed description a
/// separate, optional field.
///
/// The widget owns the whole local lifecycle (permission, record, timer,
/// playback, delete) and hands the parent a server URL via [onUploaded]
/// once a clip is uploaded — or `null` when the clip is deleted.
class VoiceRecorder extends StatefulWidget {
  /// Server URL of an already-uploaded clip (edit mode), if any.
  final String? initialUrl;

  /// Fired with the uploaded clip's server URL, or null when deleted.
  final ValueChanged<String?> onUploaded;

  /// Fired with the transcript of the clip, when transcription is
  /// configured. Lets the parent drop the spoken words into a written
  /// description — the recording is unaffected either way.
  ///
  /// SPEECH-TO-TEXT — TEMPORARILY DISABLED: nothing calls this today. The
  /// parameter stays so the call site can be restored with one line.
  final ValueChanged<String>? onTranscript;

  /// Surfaced so the parent can block "Continue" while a clip is still
  /// recording or uploading.
  final ValueChanged<bool>? onBusyChanged;

  const VoiceRecorder({
    super.key,
    required this.onUploaded,
    this.initialUrl,
    this.onBusyChanged,
    this.onTranscript,
  });

  @override
  State<VoiceRecorder> createState() => _VoiceRecorderState();
}

enum _Phase { idle, recording, recorded }

class _VoiceRecorderState extends State<VoiceRecorder> {
  static const Duration _maxDuration = Duration(minutes: 3);
  // 16 kHz mono 16-bit: what speech models expect, and small enough that
  // three minutes is ~5.7 MB both on disk and in memory.
  static const int _sampleRate = 16000;
  static const int _channels = 1;

  // Live capture plumbing. The PCM stream is written to [_wavSink] for the
  // recording and mirrored into [_pcmBytes] for the recogniser.
  StreamSubscription<Uint8List>? _pcmSub;
  IOSink? _wavSink;
  BytesBuilder? _pcmBytes;

  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  // True while the finished recording is being turned into text.
  bool _transcribing = false;
  // Why the last conversion produced no text, if it didn't. Kept and shown
  // because "nothing appeared in the box" is otherwise indistinguishable
  // from the app ignoring the recording.
  String? _transcribeError;

  // SPEECH-TO-TEXT (live dictation / in-app model) — STILL DISABLED.
  // // On-device recogniser, run in parallel with the recorder purely to
  // // produce the written description. Never blocks or fails the capture.
  // final stt.SpeechToText _speech = stt.SpeechToText();
  // bool _speechReady = false;
  // bool _dictating = false;
  // // Whether the offline model is on disk. Null until checked.
  // bool? _modelReady;

  _Phase _phase = _Phase.idle;
  String? _localPath; // on-disk clip, present once recording stops
  String? _uploadedUrl; // server URL, present once uploaded
  bool _uploading = false;
  String? _error;

  // Recording timer.
  Timer? _ticker;
  Duration _elapsed = Duration.zero;

  // Playback.
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _total = Duration.zero;
  final List<StreamSubscription<dynamic>> _subs = [];

  @override
  void initState() {
    super.initState();
    final url = widget.initialUrl;
    if (url != null && url.trim().isNotEmpty) {
      _uploadedUrl = url;
      _phase = _Phase.recorded;
    }
    // Playback listeners are attached once and torn down in dispose, so a
    // rebuild can't stack duplicates.
    _subs.add(_player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    }));
    _subs.add(_player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _total = d);
    }));
    _subs.add(_player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _playing = false;
        _position = Duration.zero;
      });
    }));
    // SPEECH-TO-TEXT — TEMPORARILY DISABLED.
    // // The panel fetches the speech pack before it renders this widget, so
    // // there's nothing to download here — only a check of whether it
    // // succeeded, which decides if the manual dictation button is needed.
    // SpeechModel.isReady().then((ok) {
    //   if (!mounted) return;
    //   setState(() => _modelReady = ok);
    //   if (ok) OfflineTranscriber.ensureLoaded();
    // });
  }

  @override
  void dispose() {
    // Order matters: kill the timer and streams before disposing the
    // native handles, or a late callback can fire against a dead player.
    _ticker?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    // _speech.cancel();  // SPEECH-TO-TEXT — TEMPORARILY DISABLED.
    _player.dispose();
    _recorder.dispose();
    super.dispose();
  }

  void _setBusy() {
    widget.onBusyChanged?.call(_phase == _Phase.recording || _uploading);
  }

  bool get _hasClip => _localPath != null || _uploadedUrl != null;

  /// Standard 44-byte PCM WAV header for [dataBytes] of audio.
  ///
  /// Written with zeroes up front and rewritten on stop, because the
  /// length isn't known until recording ends. Players and recognisers
  /// both need the real sizes, so leaving the placeholder in place would
  /// produce a file that looks empty.
  Uint8List _wavHeader(int dataBytes) {
    const bitsPerSample = 16;
    final byteRate = _sampleRate * _channels * bitsPerSample ~/ 8;
    final blockAlign = _channels * bitsPerSample ~/ 8;
    final b = BytesBuilder();
    void ascii(String s) => b.add(s.codeUnits);
    void u32(int v) => b.add(Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little));
    void u16(int v) => b.add(Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little));

    ascii('RIFF');
    u32(36 + dataBytes);
    ascii('WAVE');
    ascii('fmt ');
    u32(16);
    u16(1); // PCM
    u16(_channels);
    u32(_sampleRate);
    u32(byteRate);
    u16(blockAlign);
    u16(bitsPerSample);
    ascii('data');
    u32(dataBytes);
    return b.toBytes();
  }

  // ---------------------------------------------------------------- record

  Future<void> _startRecording() async {
    // Guard against a double-tap racing two recorders onto one mic.
    if (_phase == _Phase.recording || _uploading) return;
    setState(() {
      _error = null;
      // _transcribeError = null;  // SPEECH-TO-TEXT — TEMPORARILY DISABLED.
    });

    try {
      if (!await _recorder.hasPermission()) {
        if (!mounted) return;
        setState(() => _error =
            'Microphone permission denied. Enable it in Settings to record.');
        return;
      }

      // Playing and recording can't share the mic/audio session — stop any
      // preview first.
      if (_playing) await _stopPlayback();

      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/job_voice_${DateTime.now().millisecondsSinceEpoch}.wav';

      // ONE microphone session, split two ways.
      //
      // Rather than record to a file and recognise separately, we take the
      // raw PCM stream and fan it out: every chunk is appended to the .wav
      // and kept in memory for the recogniser. That's what makes a single
      // spoken take produce both outputs — and it only works because the
      // recogniser runs inside this app (see OfflineTranscriber). The
      // platform recogniser opens its own mic in another process, which is
      // why it could never be used this way.
      //
      // 16 kHz mono is what speech models expect and keeps three minutes
      // to ~5.7 MB.
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          numChannels: _channels,
          sampleRate: _sampleRate,
        ),
      );

      final file = File(path);
      _wavSink = file.openWrite();
      // Header is written up front with placeholder lengths and patched on
      // stop, once the total size is known.
      _wavSink!.add(_wavHeader(0));
      _pcmBytes = BytesBuilder(copy: false);

      _pcmSub = stream.listen(
        (chunk) {
          _wavSink?.add(chunk);
          _pcmBytes?.add(chunk);
        },
        onError: (_) {/* stop() surfaces the failure */},
        cancelOnError: false,
      );

      if (!mounted) return;
      setState(() {
        _phase = _Phase.recording;
        _elapsed = Duration.zero;
        _localPath = path;
        _uploadedUrl = null;
        _position = Duration.zero;
        _total = Duration.zero;
      });
      _setBusy();
      widget.onUploaded(null);
      _startTicker();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.idle;
        _error = 'Could not start recording: $e';
      });
      _setBusy();
    }
  }

  /// Turns the finished recording into text using the phone's own
  /// recogniser, and hands it up via [VoiceRecorder.onTranscript].
  ///
  /// The file is the input, not the microphone — that's the whole point.
  /// Android gives the mic to one consumer at a time, so a recogniser
  /// listening live would leave the recording silent. Feeding it the
  /// finished .wav lets a single spoken take produce both the audio the
  /// worker plays and the text in the box.
  ///
  /// Needs Android 13+ (or iOS); older devices report unsupported and the
  /// giver types the box themselves. Nothing is uploaded for this.
  Future<void> _transcribeFile(String path) async {
    if (!mounted) return;
    setState(() {
      _transcribing = true;
      _transcribeError = null;
    });
    final result = await SpeechFile.transcribe(path);
    if (!mounted) return;
    final text = result.text?.trim() ?? '';
    setState(() {
      _transcribing = false;
      _transcribeError = text.isEmpty
          ? (result.error?.trim().isNotEmpty == true
              ? result.error
              : 'No words recognised')
          : null;
    });
    if (text.isNotEmpty) widget.onTranscript?.call(text);
  }

  // SPEECH-TO-TEXT (live dictation / in-app model) — STILL DISABLED.
  //
  // /// Turns the captured samples into text using the in-app model — the
  // /// second half of the single take. Runs on the PCM we already have in
  // /// memory, so it needs no microphone and cannot disturb the recording.
  // Future<void> _transcribeSamples(Uint8List pcm) async {
  //   if (!mounted || pcm.isEmpty) return;
  //   if (!await OfflineTranscriber.ensureLoaded()) {
  //     if (!mounted) return;
  //     // No model yet: leave the manual button as the way to get text.
  //     setState(() => _transcribeError = 'Speech model not downloaded');
  //     return;
  //   }
  //   setState(() {
  //     _transcribing = true;
  //     _transcribeError = null;
  //   });
  //   // Little-endian 16-bit samples, exactly as captured.
  //   final samples = pcm.buffer.asInt16List(
  //     pcm.offsetInBytes,
  //     pcm.lengthInBytes ~/ 2,
  //   );
  //   final text = await OfflineTranscriber.transcribePcm16(samples, _sampleRate);
  //   if (!mounted) return;
  //   setState(() {
  //     _transcribing = false;
  //     // Keep the reason: without it a blank description looks like the
  //     // app ignoring the request rather than recognition failing.
  //     _transcribeError =
  //         (text == null || text.isEmpty) ? 'No words recognised' : null;
  //   });
  //   if (text != null && text.isNotEmpty) {
  //     widget.onTranscript?.call(text);
  //   }
  // }
  //
  // // ----------------------------------------------------------- dictation
  //
  // /// Speech-to-text using the phone's own recogniser — fully on-device,
  // /// no audio leaves the handset and no service is called.
  // ///
  // /// This is the manual fallback, used when the in-app model isn't
  // /// available. It cannot run alongside the recorder: Android grants the
  // /// microphone to a single app, and this one delegates to another.
  //
  // Future<void> _toggleDictation() async {
  //   if (_dictating) {
  //     await _stopDictation();
  //     return;
  //   }
  //   // Never contend with an active capture or playback.
  //   if (_phase == _Phase.recording) return;
  //   if (_playing) await _stopPlayback();
  //
  //   try {
  //     if (!_speechReady) {
  //       _speechReady = await _speech.initialize(
  //         onStatus: (status) {
  //           // The engine stops itself after a pause — mirror that so the
  //           // button doesn't stay stuck on "Listening".
  //           if ((status == 'done' || status == 'notListening') && mounted) {
  //             setState(() => _dictating = false);
  //           }
  //         },
  //         onError: (_) {
  //           if (mounted) setState(() => _dictating = false);
  //         },
  //       );
  //     }
  //     if (!mounted) return;
  //     if (!_speechReady) {
  //       setState(() =>
  //           _error = 'Speech recognition is unavailable on this device.');
  //       return;
  //     }
  //     setState(() {
  //       _dictating = true;
  //       _error = null;
  //     });
  //     await _speech.listen(
  //       onResult: (result) {
  //         final words = result.recognizedWords.trim();
  //         if (words.isEmpty || !mounted) return;
  //         // Emit partials so the box fills in live while speaking.
  //         widget.onTranscript?.call(words);
  //       },
  //       listenOptions: stt.SpeechListenOptions(
  //         partialResults: true,
  //         cancelOnError: true,
  //         listenFor: _maxDuration,
  //         pauseFor: const Duration(seconds: 8),
  //       ),
  //     );
  //   } catch (e) {
  //     if (!mounted) return;
  //     setState(() {
  //       _dictating = false;
  //       _error = 'Could not start speech recognition: $e';
  //     });
  //   }
  // }
  //
  // Future<void> _stopDictation() async {
  //   try {
  //     await _speech.stop();
  //   } catch (_) {
  //     // Nothing to stop, or the engine never started.
  //   }
  //   if (mounted) setState(() => _dictating = false);
  // }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed += const Duration(seconds: 1));
      // Hard cap so a forgotten recording can't grow unbounded.
      if (_elapsed >= _maxDuration) _stopRecording();
    });
  }

  Future<void> _stopRecording() async {
    if (_phase != _Phase.recording) return;
    _ticker?.cancel();
    try {
      await _recorder.stop();
      await _pcmSub?.cancel();
      _pcmSub = null;
      await _wavSink?.flush();
      await _wavSink?.close();
      _wavSink = null;

      final pcm = _pcmBytes?.takeBytes() ?? Uint8List(0);
      _pcmBytes = null;
      final path = _localPath;
      final file = path == null ? null : File(path);
      if (!mounted) return;

      // Captured nothing usable — say so rather than presenting a 0:00
      // clip that plays silence.
      if (file == null || !file.existsSync() || pcm.length < 2048) {
        try {
          file?.deleteSync();
        } catch (_) {/* temp file, not worth failing over */}
        setState(() {
          _phase = _Phase.idle;
          _elapsed = Duration.zero;
          _localPath = null;
          _error = 'Nothing was recorded. Check that no other app is using '
              'the microphone, then try again.';
        });
        _setBusy();
        return;
      }

      // Patch the header now that the payload length is known, otherwise
      // players read the placeholder and treat the file as empty.
      final handle = await file.open(mode: FileMode.writeOnlyAppend);
      await handle.setPosition(0);
      await handle.writeFrom(_wavHeader(pcm.length));
      await handle.close();

      setState(() {
        _phase = _Phase.recorded;
        _total = _elapsed;
      });
      _setBusy();
      await _upload(file.path);
      // Second half of the same take. Runs on the finished file, so it
      // needs no microphone and cannot disturb the recording that was
      // just captured — and it happens after the upload, so a recogniser
      // failure can never cost the audio.
      await _transcribeFile(file.path);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.idle;
        _error = 'Could not save the recording: $e';
      });
      _setBusy();
    }
  }

  /// Discards the clip locally and clears it upstream. Also used as
  /// "cancel" mid-recording.
  Future<void> _delete() async {
    _ticker?.cancel();
    // await _stopDictation();  // SPEECH-TO-TEXT — TEMPORARILY DISABLED.
    try {
      if (_phase == _Phase.recording) await _recorder.cancel();
      if (_playing) await _player.stop();
      final p = _localPath;
      if (p != null && File(p).existsSync()) {
        await File(p).delete();
      }
    } catch (_) {
      // Best effort — a leftover temp file isn't worth failing over.
    }
    if (!mounted) return;
    setState(() {
      _phase = _Phase.idle;
      _localPath = null;
      _uploadedUrl = null;
      _elapsed = Duration.zero;
      _position = Duration.zero;
      _total = Duration.zero;
      _playing = false;
      _uploading = false;
      _error = null;
    });
    _setBusy();
    widget.onUploaded(null);
  }

  // ---------------------------------------------------------------- upload

  Future<void> _upload(String path) async {
    setState(() {
      _uploading = true;
      _error = null;
    });
    _setBusy();
    try {
      final url = await HomeApi.uploadJobVoiceNote(path);
      if (!mounted) return;
      if (url == null || url.isEmpty) {
        setState(() {
          _uploading = false;
          _error = 'Upload failed. Tap retry to send it again.';
        });
        _setBusy();
        return;
      }
      setState(() {
        _uploadedUrl = url;
        _uploading = false;
      });
      _setBusy();
      widget.onUploaded(url);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = 'Upload failed: $e';
      });
      _setBusy();
    }
  }

  // -------------------------------------------------------------- playback

  Future<void> _togglePlayback() async {
    // Never play over a live mic.
    if (_phase == _Phase.recording) return;
    if (_playing) {
      await _player.pause();
      if (mounted) setState(() => _playing = false);
      return;
    }
    try {
      if (_player.state == PlayerState.paused) {
        await _player.resume();
      } else {
        // Prefer the on-disk file — it's the exact capture and needs no
        // network. Fall back to the uploaded URL in edit mode, where the
        // local file no longer exists.
        final local = _localPath;
        if (local != null && File(local).existsSync()) {
          await _player.play(DeviceFileSource(local));
        } else {
          final url = _uploadedUrl;
          if (url == null || url.isEmpty) return;
          await _player.play(UrlSource(HomeApi.absoluteUrl(url)));
        }
      }
      if (!mounted) return;
      setState(() => _playing = true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _playing = false;
        _error = 'Could not play the recording: $e';
      });
    }
  }

  Future<void> _stopPlayback() async {
    await _player.stop();
    if (!mounted) return;
    setState(() {
      _playing = false;
      _position = Duration.zero;
    });
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ------------------------------------------------------------------- ui

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // RECENT UI — HIDDEN (not deleted). A finished take used to swap
        // the mic out for a player card (play / re-record / delete). The
        // original design keeps the mic on screen instead, so the branch
        // below is parked and _clipView() is simply no longer called —
        // the method itself is left intact just underneath.
        //   else if (_hasClip)
        //     _clipView()
        // Recording again just overwrites the previous clip.
        if (_phase == _Phase.recording)
          _recordingView()
        else
          _idleView(),
        // The player card carried the only "saved / uploading" feedback,
        // so a one-line status replaces it. Without this the giver has no
        // sign the take landed, and Continue refuses with no visible cause
        // while the upload is still running.
        if (_phase != _Phase.recording && _hasClip) ...[
          const SizedBox(height: 10),
          Text(
            _uploading
                ? 'Uploading…'
                : _transcribing
                    ? 'Converting to text…'
                    : 'Voice description recorded',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: (_uploading || _transcribing)
                  ? const Color(0xFF2B7FFF)
                  : const Color(0xFF16A34A),
            ),
          ),
        ],
        // The recording is safe either way, so a failed conversion is a
        // note, not an error: it just means the box has to be typed. The
        // recogniser's own reason is kept in debug builds — "no language
        // model installed" and "you said nothing" need telling apart.
        if (_transcribeError != null &&
            _phase != _Phase.recording &&
            !_transcribing) ...[
          const SizedBox(height: 8),
          const Text(
            'Could not turn this recording into text — type the '
            'description below. Your voice is saved and workers can '
            'still play it.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11.5,
              color: Color(0xFF6B7280),
              height: 1.45,
            ),
          ),
          if (kDebugMode)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _transcribeError!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF9CA3AF),
                ),
              ),
            ),
        ],
        // SPEECH-TO-TEXT — TEMPORARILY DISABLED (transcription notice +
        // manual dictation button).
        //
        // // Automatic conversion is best-effort: plenty of devices report a
        // // recogniser as available and then return nothing for file input.
        // // That's not the giver's problem to read a stack trace about — the
        // // recording is safe, so just point at the way that does work. The
        // // technical reason stays available in debug builds.
        // if (_transcribeError != null && _phase != _Phase.recording) ...[
        //   const SizedBox(height: 10),
        //   Text(
        //     'This phone could not turn the recording into text by itself. '
        //     'Tap below and say it again to fill the description.',
        //     style: const TextStyle(
        //       fontSize: 11.5,
        //       color: Color(0xFF6B7280),
        //       height: 1.45,
        //     ),
        //   ),
        //   if (kDebugMode)
        //     Padding(
        //       padding: const EdgeInsets.only(top: 4),
        //       child: Text(
        //         _transcribeError!,
        //         style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF)),
        //       ),
        //     ),
        // ],
        // // Manual dictation stays available whenever the one-take route
        // // hasn't produced text — no model yet, or it recognised nothing —
        // // so there's always a way to fill the box by speaking. Hidden
        // // mid-record, since the mic is taken.
        // if (_phase != _Phase.recording &&
        //     (_modelReady == false || _transcribeError != null)) ...[
        //   const SizedBox(height: 12),
        //   _dictateButton(),
        // ],
        if (_error != null) ...[
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline,
                  size: 15, color: Color(0xFFDC2626)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _error!,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFFDC2626),
                    height: 1.4,
                  ),
                ),
              ),
              if (_localPath != null && _uploadedUrl == null && !_uploading)
                TextButton(
                  onPressed: () => _upload(_localPath!),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Retry',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2B7FFF),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  // SPEECH-TO-TEXT — TEMPORARILY DISABLED.
  // /// Fills the written description by speaking, using the phone's own
  // /// recogniser. Separate from the recording because the mic can only
  // /// serve one at a time.
  // Widget _dictateButton() {
  //   final on = _dictating;
  //   return SizedBox(
  //     height: 44,
  //     child: OutlinedButton.icon(
  //       onPressed: _toggleDictation,
  //       icon: Icon(
  //         on ? Icons.stop : Icons.keyboard_voice_outlined,
  //         size: 18,
  //         color: on ? const Color(0xFFDC2626) : Colors.white,
  //       ),
  //       label: Text(
  //         on ? 'Listening… tap to stop' : 'Speak to fill description text',
  //         style: TextStyle(
  //           fontSize: 13.5,
  //           fontWeight: FontWeight.w700,
  //           color: on ? const Color(0xFFDC2626) : Colors.white,
  //         ),
  //       ),
  //       style: OutlinedButton.styleFrom(
  //         // Filled when idle: with automatic conversion unavailable this
  //         // is the only route to text, so it shouldn't read as secondary.
  //         backgroundColor:
  //             on ? const Color(0xFFFEE2E2) : const Color(0xFF2B7FFF),
  //         side: BorderSide(
  //           color: on ? const Color(0xFFDC2626) : const Color(0xFF2B7FFF),
  //           width: 1.2,
  //         ),
  //         shape: RoundedRectangleBorder(
  //           borderRadius: BorderRadius.circular(12),
  //         ),
  //       ),
  //     ),
  //   );
  // }

  Widget _idleView() {
    return Column(
      children: [
        _MicButton(
          icon: Icons.mic,
          color: const Color(0xFF2B7FFF),
          onTap: _startRecording,
        ),
        const SizedBox(height: 16),
        const Text(
          'Tap to start recording',
          style: TextStyle(
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
        // RECENT UI — HIDDEN (not deleted). The wording that replaced the
        // original design's labels:
        // const Text(
        //   'Tap the mic and speak',
        //   style: TextStyle(
        //     fontSize: 16,
        //     fontWeight: FontWeight.w600,
        //     color: Color(0xFF408EE0),
        //   ),
        // ),
        // const SizedBox(height: 4),
        // const Text(
        //   'Your voice is recorded and played to workers exactly as you '
        //   'say it.',
        //   textAlign: TextAlign.center,
        //   style: TextStyle(fontSize: 14, color: Color(0xFF155DFC)),
        // ),
      ],
    );
  }

  Widget _recordingView() {
    return Column(
      children: [
        _MicButton(
          icon: Icons.stop,
          color: const Color(0xFFDC2626),
          pulsing: true,
          onTap: _stopRecording,
        ),
        const SizedBox(height: 16),
        // Matches the idle label's slot so the panel doesn't jump when
        // recording starts.
        const Text(
          'Recording…',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF408EE0),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: const BoxDecoration(
                color: Color(0xFFDC2626),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _fmt(_elapsed),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF101828),
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Tap to stop (max ${_maxDuration.inMinutes} min)',
          style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
        ),
        const SizedBox(height: 14),
        TextButton.icon(
          onPressed: _delete,
          icon: const Icon(Icons.close, size: 16, color: Color(0xFF6B7280)),
          label: const Text(
            'Cancel',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF6B7280),
            ),
          ),
        ),
      ],
    );
  }

  /// The player card: play/pause, scrubber, Re-record and Delete.
  ///
  /// RECENT UI — HIDDEN (not deleted). Left as live, compiling code rather
  /// than commented out so restoring it is a one-line change in build()
  /// (and so the playback plumbing it uses stays analysed).
  // ignore: unused_element
  Widget _clipView() {
    final total = _total.inMilliseconds > 0 ? _total : _elapsed;
    final progress = total.inMilliseconds == 0
        ? 0.0
        : (_position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBEDBFF), width: 1),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        children: [
          Row(
            children: [
              // Play / pause
              Material(
                color: const Color(0xFF2B7FFF),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _uploading ? null : _togglePlayback,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Icon(
                      _playing ? Icons.pause : Icons.play_arrow,
                      size: 22,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 5,
                        backgroundColor: const Color(0xFFDBEAFE),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF2B7FFF),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _fmt(_position),
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF6B7280),
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        // SPEECH-TO-TEXT — TEMPORARILY DISABLED: the
                        // "Converting to text…" state is gone with it, so
                        // this is just upload progress vs. clip length.
                        Text(
                          _uploading ? 'Uploading…' : _fmt(total),
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight:
                                _uploading ? FontWeight.w700 : FontWeight.w400,
                            color: _uploading
                                ? const Color(0xFF2B7FFF)
                                : const Color(0xFF6B7280),
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (_playing) ...[
                const SizedBox(width: 6),
                IconButton(
                  onPressed: _stopPlayback,
                  tooltip: 'Stop',
                  icon: const Icon(Icons.stop_circle_outlined,
                      size: 22, color: Color(0xFF6B7280)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          const Divider(height: 14, thickness: 0.6, color: Color(0xFFE5E7EB)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton.icon(
                onPressed: _uploading ? null : _startRecording,
                icon: const Icon(Icons.mic_none,
                    size: 17, color: Color(0xFF2B7FFF)),
                label: const Text(
                  'Re-record',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2B7FFF),
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _uploading ? null : _delete,
                icon: const Icon(Icons.delete_outline,
                    size: 17, color: Color(0xFFDC2626)),
                label: const Text(
                  'Delete',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFDC2626),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool pulsing;
  final VoidCallback onTap;

  const _MicButton({
    required this.icon,
    required this.color,
    required this.onTap,
    this.pulsing = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color.withAlpha(pulsing ? 110 : 60),
              blurRadius: pulsing ? 20 : 12,
              spreadRadius: pulsing ? 2 : 0,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(icon, size: 40, color: Colors.white),
      ),
    );
  }
}
