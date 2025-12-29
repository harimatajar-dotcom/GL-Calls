import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../../domain/entities/recording_entity.dart';
import '../../domain/repositories/recording_repository.dart';

enum RecordingStatus { initial, loading, loaded, error }

enum PlaybackState { stopped, playing, paused, loading }

enum UploadStatus { idle, uploading, success, error }

class RecordingProvider extends ChangeNotifier {
  final RecordingRepository repository;
  final AudioPlayer _audioPlayer = AudioPlayer();

  RecordingProvider({required this.repository}) {
    _initAudioPlayer();
  }

  RecordingStatus _status = RecordingStatus.initial;
  List<RecordingEntity> _recordings = [];
  List<RecordingEntity> _uploadedRecordings = [];
  String? _errorMessage;
  bool _hasPermission = false;

  // Upload state
  UploadStatus _uploadStatus = UploadStatus.idle;
  RecordingEntity? _lastUploadedRecording;

  // Playback state
  PlaybackState _playbackState = PlaybackState.stopped;
  RecordingEntity? _currentRecording;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;

  // Getters
  RecordingStatus get status => _status;
  List<RecordingEntity> get recordings => _recordings;
  List<RecordingEntity> get uploadedRecordings => _uploadedRecordings;
  String? get errorMessage => _errorMessage;
  bool get hasPermission => _hasPermission;

  UploadStatus get uploadStatus => _uploadStatus;
  RecordingEntity? get lastUploadedRecording => _lastUploadedRecording;
  bool get isUploading => _uploadStatus == UploadStatus.uploading;

  PlaybackState get playbackState => _playbackState;
  RecordingEntity? get currentRecording => _currentRecording;
  Duration get currentPosition => _currentPosition;
  Duration get totalDuration => _totalDuration;
  bool get isPlaying => _playbackState == PlaybackState.playing;

  int get recordingsCount => _recordings.length;
  int get uploadedRecordingsCount => _uploadedRecordings.length;

  void _initAudioPlayer() {
    _audioPlayer.positionStream.listen((position) {
      _currentPosition = position;
      notifyListeners();
    });

    _audioPlayer.durationStream.listen((duration) {
      _totalDuration = duration ?? Duration.zero;
      notifyListeners();
    });

    _audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _playbackState = PlaybackState.stopped;
        _currentPosition = Duration.zero;
        notifyListeners();
      }
    });
  }

  Future<void> checkPermission() async {
    _hasPermission = await repository.hasPermission();
    notifyListeners();
  }

  Future<bool> requestPermission() async {
    _hasPermission = await repository.requestPermission();
    notifyListeners();
    return _hasPermission;
  }

  Future<void> loadRecordings() async {
    _status = RecordingStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      await checkPermission();
      if (_hasPermission) {
        await repository.syncRecordings();
        _recordings = await repository.getAllRecordings();
        _uploadedRecordings = await repository.getUploadedRecordings();
      }
      _status = RecordingStatus.loaded;
    } catch (e) {
      _status = RecordingStatus.error;
      _errorMessage = e.toString();
    }
    notifyListeners();
  }

  Future<void> refresh() async {
    await loadRecordings();
  }

  Future<void> loadUploadedRecordings() async {
    try {
      _uploadedRecordings = await repository.getUploadedRecordings();
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
    }
  }

  Future<bool> uploadLatestRecording(int vendorId) async {
    _uploadStatus = UploadStatus.uploading;
    _errorMessage = null;
    notifyListeners();

    try {
      // Upload to S3 AND sync call to server
      final uploadedRecording = await repository.uploadAndSyncLatestRecording(vendorId);

      if (uploadedRecording != null) {
        _uploadStatus = UploadStatus.success;
        _lastUploadedRecording = uploadedRecording;

        // Reload recordings to update lists
        await loadRecordings();

        notifyListeners();
        return true;
      } else {
        _uploadStatus = UploadStatus.error;
        _errorMessage = 'No recordings to upload';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _uploadStatus = UploadStatus.error;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> syncCallToServer(RecordingEntity recording) async {
    try {
      return await repository.syncCallToServer(recording);
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  void resetUploadStatus() {
    _uploadStatus = UploadStatus.idle;
    notifyListeners();
  }

  Future<void> playRecording(RecordingEntity recording) async {
    try {
      // If same recording is playing, toggle pause/play
      if (_currentRecording?.id == recording.id) {
        if (_playbackState == PlaybackState.playing) {
          await pause();
          return;
        } else if (_playbackState == PlaybackState.paused) {
          await resume();
          return;
        }
      }

      // Stop current playback
      await stop();

      _currentRecording = recording;
      _playbackState = PlaybackState.loading;
      notifyListeners();

      final playPath = recording.playablePath;
      await _audioPlayer.setFilePath(playPath);
      await _audioPlayer.play();

      _playbackState = PlaybackState.playing;
      notifyListeners();
    } catch (e) {
      _playbackState = PlaybackState.stopped;
      _currentRecording = null;
      _errorMessage = 'Failed to play recording: ${e.toString()}';
      notifyListeners();
    }
  }

  Future<void> pause() async {
    await _audioPlayer.pause();
    _playbackState = PlaybackState.paused;
    notifyListeners();
  }

  Future<void> resume() async {
    await _audioPlayer.play();
    _playbackState = PlaybackState.playing;
    notifyListeners();
  }

  Future<void> stop() async {
    await _audioPlayer.stop();
    _playbackState = PlaybackState.stopped;
    _currentRecording = null;
    _currentPosition = Duration.zero;
    _totalDuration = Duration.zero;
    notifyListeners();
  }

  Future<void> seek(Duration position) async {
    await _audioPlayer.seek(position);
  }

  String formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }
}
