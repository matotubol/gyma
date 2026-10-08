const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _two(int n) => n.toString().padLeft(2, '0');

String weekdayShort(DateTime d) => _weekdays[d.weekday - 1];
String monthShort(DateTime d) => _months[d.month - 1];

/// "Wed 8 Oct", with the year added when it isn't this year.
String fmtDate(DateTime d) {
  final base = '${weekdayShort(d)} ${d.day} ${monthShort(d)}';
  return d.year == DateTime.now().year ? base : '$base ${d.year}';
}

String fmtTime(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

/// "1h 05m" or "42 min".
String fmtDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  return h > 0 ? '${h}h ${_two(m)}m' : '$m min';
}

/// Stopwatch style: "1:05:09" or "05:09".
String fmtClock(Duration d) {
  final h = d.inHours;
  final ms = '${_two(d.inMinutes % 60)}:${_two(d.inSeconds % 60)}';
  return h > 0 ? '$h:$ms' : ms;
}

/// Whole numbers with thousands separators: 12500 -> "12,500".
String fmtInt(int v) {
  final s = v.abs().toString();
  final buf = StringBuffer(v < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// Weights: 60 -> "60", 62.5 -> "62.5", 31.25 -> "31.25", 1100 -> "1,100".
String fmtKg(double v) {
  final r = (v * 100).round() / 100;
  if (r == r.roundToDouble()) return fmtInt(r.round());
  var s = r.toStringAsFixed(2);
  if (s.endsWith('0')) s = s.substring(0, s.length - 1);
  return s;
}

/// Accepts both "62.5" and the Dutch keyboard's "62,5".
double? parseKg(String text) =>
    double.tryParse(text.trim().replaceAll(',', '.'));
