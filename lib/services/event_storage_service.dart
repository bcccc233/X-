import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import '../models/event_model.dart';
import 'sync_service.dart';

class EventStorageService {
  static const String boxName = 'events_box';
  late Box<EventModel> _eventBox;
  late Box _pendingBox;
  bool _isInitialized = false;

  /// 数据变更回调（用于远程同步后通知UI刷新）
  void Function()? onDataChanged;

  // 初始化 Hive
  Future<void> init() async {
    if (_isInitialized) return;

    if (Hive.isBoxOpen(boxName)) {
      _eventBox = Hive.box<EventModel>(boxName);
    } else {
      _eventBox = await Hive.openBox<EventModel>(boxName);
    }
    // 打开 pending_sync box 用于离线队列
    const pendingBoxName = 'pending_sync';
    if (Hive.isBoxOpen(pendingBoxName)) {
      _pendingBox = Hive.box(pendingBoxName);
    } else {
      _pendingBox = await Hive.openBox(pendingBoxName);
    }
    // 注册远端事件处理器
    SyncService.instance.registerRemoteHandler((data) async {
      await _applyRemoteEvent(data);
    });
    // 当连接建立时尝试刷新待同步队列
    SyncService.instance.registerConnectionHandler((connected) async {
      if (connected) await flushPending();
    });
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
    // 发送到远端（如果已连接），否则入队列待同步
    if (!_suppressSync) {
      final payload = {
        'action': 'add',
        'event': {
          'id': event.id,
          'title': event.title,
          'startDateTime': event.startDateTime.toIso8601String(),
          'durationInMinutes': event.durationInMinutes,
          'createdAt': event.createdAt.toIso8601String(),
          'updatedAt': event.updatedAt.toIso8601String(),
        },
      };
      if (SyncService.instance.isConnected) {
        SyncService.instance.sendEvent(payload);
      } else {
        await _enqueuePending(payload);
      }
    }
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
      if (!_suppressSync) {
        final payload = {
          'action': 'update',
          'event': {
            'id': event.id,
            'title': event.title,
            'startDateTime': event.startDateTime.toIso8601String(),
            'durationInMinutes': event.durationInMinutes,
            'createdAt': event.createdAt.toIso8601String(),
            'updatedAt': event.updatedAt.toIso8601String(),
          },
        };
        if (SyncService.instance.isConnected) {
          SyncService.instance.sendEvent(payload);
        } else {
          await _enqueuePending(payload);
        }
      }
    }
  }

  // 删除事件
  Future<void> deleteEvent(String id) async {
    await _eventBox.delete(id);
    if (!_suppressSync) {
      final payload = {'action': 'delete', 'id': id};
      if (SyncService.instance.isConnected) {
        SyncService.instance.sendEvent(payload);
      } else {
        await _enqueuePending(payload);
      }
    }
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

  bool _suppressSync = false;

  Future<void> _applyRemoteEvent(Map<String, dynamic> data) async {
    try {
      final action = data['action'] as String?;
      if (action == null) return;

      if (action == 'delete') {
        final id = data['id'] as String?;
        if (id == null) return;
        _suppressSync = true;
        await _eventBox.delete(id);
        _suppressSync = false;
        onDataChanged?.call();
        return;
      }

      final Map<String, dynamic>? evt = (data['event'] is Map)
          ? Map<String, dynamic>.from(data['event'])
          : null;
      if (evt == null) return;

      final id = evt['id'] as String?;
      if (id == null) return;

      final remoteUpdatedAt =
          DateTime.tryParse(evt['updatedAt'] ?? '') ?? DateTime.now();
      final existing = _eventBox.get(id);
      if (existing != null) {
        // 冲突策略：以更新时间较新的为准
        if (!remoteUpdatedAt.isAfter(existing.updatedAt)) return;
      }

      final title = evt['title'] as String? ?? '';
      final start =
          DateTime.tryParse(evt['startDateTime'] ?? '') ?? DateTime.now();
      final duration = (evt['durationInMinutes'] is int)
          ? evt['durationInMinutes'] as int
          : int.tryParse('${evt['durationInMinutes']}') ?? 0;

      final remoteEvent = EventModel(
        id: id,
        title: title,
        startDateTime: start,
        durationInMinutes: duration,
        createdAt: DateTime.tryParse(evt['createdAt'] ?? '') ?? DateTime.now(),
        updatedAt: remoteUpdatedAt,
      );

      _suppressSync = true;
      await _eventBox.put(id, remoteEvent);
      _suppressSync = false;
      onDataChanged?.call();
    } catch (_) {}
  }

  Future<void> _enqueuePending(Map<String, dynamic> payload) async {
    try {
      await _pendingBox.add(payload);
    } catch (_) {}
  }

  Future<void> flushPending() async {
    try {
      final items = _pendingBox.values.toList();
      for (final entry in items) {
        try {
          final Map<String, dynamic> payload = Map<String, dynamic>.from(
            entry as Map,
          );
          SyncService.instance.sendEvent(payload);
        } catch (_) {}
      }
      await _pendingBox.clear();
    } catch (_) {}
  }
}
