import 'package:hive/hive.dart';

part 'event_model.g.dart';

@HiveType(typeId: 0)
class EventModel extends HiveObject {
  @HiveField(0)
  late String id;

  @HiveField(1)
  late String title;

  @HiveField(2)
  late DateTime startDateTime;

  @HiveField(3)
  late int durationInMinutes; // 使用分钟存储 Duration

  @HiveField(4)
  late DateTime createdAt;

  @HiveField(5)
  late DateTime updatedAt;

  EventModel({
    required this.id,
    required this.title,
    required this.startDateTime,
    required this.durationInMinutes,
    required this.createdAt,
    required this.updatedAt,
  });

  /// 从 Duration 对象创建 EventModel
  static EventModel fromEvent(
    String id,
    String title,
    DateTime startDateTime,
    Duration duration,
  ) {
    return EventModel(
      id: id,
      title: title,
      startDateTime: startDateTime,
      durationInMinutes: duration.inMinutes,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  // 计算 endDateTime
  DateTime get endDateTime =>
      startDateTime.add(Duration(minutes: durationInMinutes));

  // 获取 Duration
  Duration get duration => Duration(minutes: durationInMinutes);

  // 获取涉及的所有日期
  List<DateTime> get involvedDates {
    List<DateTime> dates = [];
    DateTime current = DateTime(
      startDateTime.year,
      startDateTime.month,
      startDateTime.day,
    );
    DateTime end = DateTime(
      endDateTime.year,
      endDateTime.month,
      endDateTime.day,
    );
    while (!current.isAfter(end)) {
      dates.add(current);
      current = current.add(const Duration(days: 1));
    }
    return dates;
  }

  // 获取时间范围字符串
  String get timeRange {
    final start = _formatDateTime(startDateTime);
    final end = _formatDateTime(endDateTime);
    return '$start - $end';
  }

  static String _formatDateTime(DateTime dt) {
    final date =
        '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    final time =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '$date $time';
  }
}
