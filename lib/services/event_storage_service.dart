import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import '../models/event_model.dart';

class EventStorageService {
  static const String boxName = 'events_box';
  late Box<EventModel> _eventBox;
  bool _isInitialized = false;

  // 初始化 Hive
  Future<void> init() async {
    if (_isInitialized) return;

    _eventBox = await Hive.openBox<EventModel>(boxName);
    _isInitialized = true;
  }

  // 添加事件
  Future<String> addEvent({
    required String title,
    required DateTime startDateTime,
    required Duration duration,
  }) async {
    final id = const Uuid().v4();
    final event = EventModel.fromEvent(id, title, startDateTime, duration);
    await _eventBox.put(id, event);
    return id;
  }

  // 获取所有事件
  List<EventModel> getAllEvents() {
    return _eventBox.values.toList();
  }

  // 按 ID 获取事件
  EventModel? getEventById(String id) {
    return _eventBox.get(id);
  }

  // 获取某一天的事件
  List<EventModel> getEventsByDate(DateTime date) {
    final normalizedDate = DateTime(date.year, date.month, date.day);
    return _eventBox.values
        .where((event) => event.involvedDates.contains(normalizedDate))
        .toList();
  }

  // 更新事件
  Future<void> updateEvent({
    required String id,
    required String title,
    required DateTime startDateTime,
    required Duration duration,
  }) async {
    final event = _eventBox.get(id);
    if (event != null) {
      event.title = title;
      event.startDateTime = startDateTime;
      event.durationInMinutes = duration.inMinutes;
      event.updatedAt = DateTime.now();
      await event.save();
    }
  }

  // 删除事件
  Future<void> deleteEvent(String id) async {
    await _eventBox.delete(id);
  }

  // 清空所有事件
  Future<void> clearAll() async {
    await _eventBox.clear();
  }

  // 检查是否为空
  bool isEmpty() {
    return _eventBox.isEmpty;
  }

  // 获取事件数量
  int getEventCount() {
    return _eventBox.length;
  }
}
