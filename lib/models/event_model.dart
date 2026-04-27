import 'package:hive/hive.dart';

part 'event_model.g.dart';

@HiveType(typeId: 0)
class EventModel extends HiveObject {

  @HiveField(0)
  String id;

  @HiveField(1)
  String title;

  @HiveField(2)
  DateTime startTime;

  @HiveField(3)
  DateTime endTime;

  @HiveField(4)
  String description;

  @HiveField(5)
  int priority;

  @HiveField(6)
  bool isFinished;

  @HiveField(7)
  DateTime lastModified;

  EventModel({
    required this.id,
    required this.title,
    required this.startTime,
    required this.endTime,
    required this.description,
    required this.priority,
    required this.isFinished,
    required this.lastModified,
  });
}