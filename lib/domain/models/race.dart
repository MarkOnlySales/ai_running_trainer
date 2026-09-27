/// Race distances the app supports.
library;

enum RaceDistance {
  k5(5000, '5K'),
  k10(10000, '10K'),
  half(21097.5, 'Half marathon'),
  marathon(42197.5, 'Marathon');

  const RaceDistance(this.metres, this.label);

  final double metres;
  final String label;

  static RaceDistance fromName(String name) =>
      RaceDistance.values.firstWhere((d) => d.name == name);
}

/// A single race result, with the date it was achieved.
///
/// The date matters as much as the time: a two-year-old 10K describes a
/// different physiological reality than a six-week-old one.
class RaceResult {
  const RaceResult({
    required this.distance,
    required this.time,
    required this.date,
  });

  final RaceDistance distance;
  final Duration time;
  final DateTime date;

  /// Days between this race and [reference]. Negative if in the future.
  int ageInDays(DateTime reference) =>
      reference.difference(date).inDays;

  @override
  String toString() =>
      '${distance.label} $time on ${date.year}-${date.month}-${date.day}';

  Map<String, dynamic> toJson() => {
        'distance': distance.name,
        'seconds': time.inSeconds,
        'date': date.toIso8601String(),
      };

  static RaceResult fromJson(Map<String, dynamic> json) => RaceResult(
        distance: RaceDistance.values.firstWhere(
          (d) => d.name == json['distance'],
          orElse: () => RaceDistance.k10,
        ),
        time: Duration(seconds: (json['seconds'] as num).toInt()),
        date: DateTime.parse(json['date'] as String),
      );
}
