String formatClock(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

Duration parseFfprobeSeconds(String seconds) {
  final value = double.tryParse(seconds) ?? 0;
  return Duration(milliseconds: (value * 1000).round());
}

Duration clampDuration(Duration value, Duration min, Duration max) {
  final ms = value.inMilliseconds.clamp(min.inMilliseconds, max.inMilliseconds);
  return Duration(milliseconds: ms);
}

String formatSeconds(Duration d) =>
    (d.inMicroseconds / Duration.microsecondsPerSecond).toStringAsFixed(3);

/// Human-friendly relative time like "2 hours ago" / "just now".
String timeAgo(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}
