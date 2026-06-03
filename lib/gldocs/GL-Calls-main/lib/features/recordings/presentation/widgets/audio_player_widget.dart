import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../providers/recording_provider.dart';

class AudioPlayerWidget extends StatelessWidget {
  final RecordingProvider provider;

  const AudioPlayerWidget({
    super.key,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    final recording = provider.currentRecording;
    if (recording == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.audiotrack,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        recording.displayName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        recording.fileName,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => provider.stop(),
                  icon: const Icon(Icons.close),
                  color: AppColors.textSecondary,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  provider.formatDuration(provider.currentPosition),
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 14,
                      ),
                    ),
                    child: Slider(
                      value: _getSliderValue(),
                      onChanged: (value) {
                        final duration = provider.totalDuration;
                        final position = Duration(
                          milliseconds: (value * duration.inMilliseconds).toInt(),
                        );
                        provider.seek(position);
                      },
                      activeColor: AppColors.primary,
                      inactiveColor: AppColors.primary.withValues(alpha: 0.2),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  provider.formatDuration(provider.totalDuration),
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: () {
                    final newPosition = provider.currentPosition -
                        const Duration(seconds: 10);
                    provider.seek(
                      newPosition < Duration.zero ? Duration.zero : newPosition,
                    );
                  },
                  icon: const Icon(Icons.replay_10),
                  iconSize: 32,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 16),
                _buildPlayPauseButton(),
                const SizedBox(width: 16),
                IconButton(
                  onPressed: () {
                    final newPosition = provider.currentPosition +
                        const Duration(seconds: 10);
                    provider.seek(
                      newPosition > provider.totalDuration
                          ? provider.totalDuration
                          : newPosition,
                    );
                  },
                  icon: const Icon(Icons.forward_10),
                  iconSize: 32,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  double _getSliderValue() {
    if (provider.totalDuration.inMilliseconds == 0) return 0;
    return provider.currentPosition.inMilliseconds /
        provider.totalDuration.inMilliseconds;
  }

  Widget _buildPlayPauseButton() {
    final isLoading = provider.playbackState == PlaybackState.loading;
    final isPlaying = provider.playbackState == PlaybackState.playing;

    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading
              ? null
              : () {
                  if (isPlaying) {
                    provider.pause();
                  } else {
                    provider.resume();
                  }
                },
          borderRadius: BorderRadius.circular(32),
          child: Center(
            child: isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: AppColors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    color: AppColors.white,
                    size: 32,
                  ),
          ),
        ),
      ),
    );
  }
}
