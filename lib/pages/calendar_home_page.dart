import 'package:flutter/material.dart';
import 'package:lunar/lunar.dart';
import 'package:table_calendar/table_calendar.dart';
import '../services/event_storage_service.dart';
import '../services/sync_service.dart';

class Event {
  final String? id; // 数据库ID
  final String title;
  final DateTime startDateTime;
  final Duration duration;

  Event({
    this.id,
    required this.title,
    required this.startDateTime,
    required this.duration,
  });

  DateTime get endDateTime => startDateTime.add(duration);

  String get timeRange {
    final start = _formatDateTime(startDateTime);
    final end = _formatDateTime(endDateTime);
    return '$start - $end';
  }

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
}

String _formatDateTime(DateTime dt) {
  final date =
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  final time =
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  return '$date $time';
}

class CalendarHomePage extends StatefulWidget {
  const CalendarHomePage({super.key, required this.title});

  final String title;

  @override
  State<CalendarHomePage> createState() => _CalendarHomePageState();
}

class _CalendarHomePageState extends State<CalendarHomePage> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  int _currentIndex = 0;

  // 日程数据
  List<Event> _events = [];

  // 数据存储服务
  late EventStorageService _storageService;
  bool _storageReady = false;

  // 设置
  bool _isDarkTheme = false;
  bool _notificationsEnabled = true;
  CalendarFormat _defaultCalendarFormat = CalendarFormat.month;
  // 同步控件
  final TextEditingController _syncHostController = TextEditingController();
  final TextEditingController _syncPortController = TextEditingController(
    text: '4040',
  );
  final TextEditingController _syncTokenController = TextEditingController();
  bool _isHosting = false;
  bool _isConnected = false;
  List<Map<String, dynamic>> _savedHosts = [];

  @override
  void initState() {
    super.initState();
    _initializeStorage();
    // 注册连接状态回调用于 UI 更新
    SyncService.instance.registerConnectionHandler((connected) {
      if (!mounted) return;
      setState(() {
        _isConnected = connected;
      });
    });
    _loadSavedHosts();
  }

  @override
  void dispose() {
    _syncHostController.dispose();
    _syncPortController.dispose();
    _syncTokenController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedHosts() async {
    final hosts = await SyncService.instance.getSavedHosts();
    if (!mounted) return;
    setState(() {
      _savedHosts = hosts;
    });
  }

  // 初始化存储服务并加载数据
  Future<void> _initializeStorage() async {
    _storageService = EventStorageService();
    try {
      await _storageService.init();
      // 注册数据变更回调：远程同步后自动刷新UI
      _storageService.onDataChanged = () {
        if (!mounted) return;
        _loadEventsFromStorage();
      };
      // 从数据库加载事件
      _loadEventsFromStorage();
    } finally {
      if (mounted) {
        setState(() {
          _storageReady = true;
        });
      }
    }
  }

  // 从存储中加载事件
  void _loadEventsFromStorage() {
    final storedEvents = _storageService.getAllEvents();
    setState(() {
      _events = storedEvents
          .map(
            (model) => Event(
              id: model.id,
              title: model.title,
              startDateTime: model.startDateTime,
              duration: Duration(minutes: model.durationInMinutes),
            ),
          )
          .toList();
    });
  }

  DateTime _normalizeDate(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  bool _eventEquals(Event a, Event b) =>
      a.title == b.title &&
      a.startDateTime == b.startDateTime &&
      a.duration == b.duration;

  bool _eventsOverlap(Event a, Event b) {
    final aStart = a.startDateTime;
    final aEnd = aStart.add(a.duration);
    final bStart = b.startDateTime;
    final bEnd = bStart.add(b.duration);
    return aStart.isBefore(bEnd) && bStart.isBefore(aEnd);
  }

  bool _hasConflict(Event newEvent, {Event? exclude}) {
    for (final event in _events) {
      if (exclude != null && _eventEquals(event, exclude)) continue;
      if (_eventsOverlap(event, newEvent)) return true;
    }
    return false;
  }

  void _showConflictReminder(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('时间冲突'),
        content: const Text('当前事件的时间段与已有事件重叠，请检查安排。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  List<Event> _getEventsForDay(DateTime day) {
    final normalizedDay = _normalizeDate(day);
    return _events
        .where((event) => event.involvedDates.contains(normalizedDay))
        .toList();
  }

  String _getLunarDayLabel(DateTime date) {
    final lunar = Lunar.fromDate(date);
    final currentJieQi = lunar.getCurrentJieQi();
    if (currentJieQi != null) {
      return currentJieQi.getName();
    }
    return lunar.getDayInChinese();
  }

  @override
  Widget build(BuildContext context) {
    Widget bodyContent;

    if (!_storageReady) {
      bodyContent = const Center(child: CircularProgressIndicator());
    } else {
      switch (_currentIndex) {
        case 0: // 日历
          bodyContent = Column(
            children: [
              TableCalendar(
                firstDay: DateTime.utc(2010, 1, 1),
                lastDay: DateTime.utc(2035, 12, 31),
                focusedDay: _focusedDay,
                calendarFormat: _calendarFormat,
                selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                onDaySelected: (selectedDay, focusedDay) {
                  setState(() {
                    _selectedDay = selectedDay;
                    _focusedDay = focusedDay;
                  });
                },
                onFormatChanged: (format) {
                  setState(() {
                    _calendarFormat = format;
                  });
                },
                onPageChanged: (focusedDay) {
                  _focusedDay = focusedDay;
                },
                calendarBuilders: CalendarBuilders(
                  defaultBuilder: (context, day, focusedDay) {
                    final lunarLabel = _getLunarDayLabel(day);
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${day.day}',
                            style: const TextStyle(fontSize: 16),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            lunarLabel,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                  markerBuilder: (context, date, events) {
                    final hasEvents = _getEventsForDay(date).isNotEmpty;
                    if (hasEvents) {
                      return Positioned(
                        bottom: 4,
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                      );
                    }
                    return null;
                  },
                ),
              ),
              Expanded(
                child: _selectedDay == null
                    ? const Center(child: Text('请选择一个日期'))
                    : _buildEventList(_selectedDay!),
              ),
            ],
          );
          break;

        case 1: // 日程列表
          bodyContent = _buildAllEventsList();
          break;

        case 2: // 设置
          bodyContent = _buildSettingsPage();
          break;

        default:
          bodyContent = const Center(child: Text('未知页面'));
      }
    }

    return MaterialApp(
      theme: _isDarkTheme
          ? ThemeData.dark(useMaterial3: true)
          : ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        ),
        body: bodyContent,
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.calendar_month),
              label: '日历',
            ),
            BottomNavigationBarItem(icon: Icon(Icons.list), label: '日程'),
            BottomNavigationBarItem(icon: Icon(Icons.settings), label: '设置'),
          ],
        ),
      ),
    );
  }

  Widget _buildEventList(DateTime day) {
    List<Event> events = _getEventsForDay(day);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            '日程列表 (${day.year}-${day.month}-${day.day})',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: events.isEmpty
              ? const Center(child: Text('当前日期暂无日程'))
              : ListView.builder(
                  itemCount: events.length,
                  itemBuilder: (context, index) {
                    Event event = events[index];
                    return ListTile(
                      title: Text(event.title),
                      subtitle: Text(event.timeRange),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () async {
                              if (!mounted) return;
                              final newEvent = await _showEventDialog(
                                context,
                                initialEvent: event,
                              );
                              if (!mounted) return;
                              if (newEvent != null) {
                                final BuildContext localContext = context;
                                if (_hasConflict(newEvent, exclude: event)) {
                                  // ignore: use_build_context_synchronously
                                  _showConflictReminder(localContext);
                                } else {
                                  setState(() {
                                    final globalIndex = _events.indexOf(event);
                                    _events[globalIndex] = Event(
                                      id: event.id,
                                      title: newEvent.title,
                                      startDateTime: newEvent.startDateTime,
                                      duration: newEvent.duration,
                                    );
                                  });
                                  // 更新数据库
                                  if (event.id != null) {
                                    await _storageService.updateEvent(
                                      id: event.id!,
                                      title: newEvent.title,
                                      startDateTime: newEvent.startDateTime,
                                      duration: newEvent.duration,
                                    );
                                  }
                                }
                              }
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () {
                              setState(() {
                                _events.remove(event);
                              });
                              // 从数据库删除
                              if (event.id != null) {
                                _storageService.deleteEvent(event.id!);
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: ElevatedButton(
            onPressed: () async {
              if (!mounted) return;
              final newEvent = await _showEventDialog(
                context,
                initialEvent: null,
                day: day,
              );
              if (!mounted) return;
              if (newEvent != null) {
                if (_hasConflict(newEvent)) {
                  _showConflictReminder(context);
                } else {
                  // 保存到数据库并获取 ID
                  final eventId = await _storageService.addEvent(
                    title: newEvent.title,
                    startDateTime: newEvent.startDateTime,
                    duration: newEvent.duration,
                  );
                  setState(() {
                    // 创建带 ID 的 Event 对象
                    _events.add(
                      Event(
                        id: eventId,
                        title: newEvent.title,
                        startDateTime: newEvent.startDateTime,
                        duration: newEvent.duration,
                      ),
                    );
                  });
                }
              }
            },
            child: const Text('添加事件'),
          ),
        ),
      ],
    );
  }

  // 日程视图增强版：支持添加/编辑/删除
  Widget _buildAllEventsList() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('添加日程'),
            onPressed: () async {
              if (!mounted) return;
              final result = await _showAddEventWithDateDialog(context);
              if (!mounted) return;
              if (result != null) {
                if (_hasConflict(result)) {
                  _showConflictReminder(context);
                } else {
                  // 保存到数据库并获取 ID
                  final eventId = await _storageService.addEvent(
                    title: result.title,
                    startDateTime: result.startDateTime,
                    duration: result.duration,
                  );
                  setState(() {
                    // 创建带 ID 的 Event 对象
                    _events.add(
                      Event(
                        id: eventId,
                        title: result.title,
                        startDateTime: result.startDateTime,
                        duration: result.duration,
                      ),
                    );
                  });
                }
              }
            },
          ),
        ),
        Expanded(
          child: _events.isEmpty
              ? const Center(child: Text('暂无日程'))
              : Builder(
                  builder: (context) {
                    Map<DateTime, List<Event>> groupedEvents = {};
                    for (var event in _events) {
                      for (var date in event.involvedDates) {
                        final normalized = _normalizeDate(date);
                        groupedEvents
                            .putIfAbsent(normalized, () => [])
                            .add(event);
                      }
                    }
                    final sortedDays = groupedEvents.keys.toList()..sort();
                    return ListView(
                      children: sortedDays.map((day) {
                        final dayEvents = groupedEvents[day]!;
                        return ExpansionTile(
                          title: Text(
                            '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')} (${dayEvents.length})',
                          ),
                          children: List.generate(dayEvents.length, (index) {
                            final event = dayEvents[index];
                            return ListTile(
                              title: Text(event.title),
                              subtitle: Text(event.timeRange),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit),
                                    onPressed: () async {
                                      if (!mounted) return;
                                      final newEvent = await _showEventDialog(
                                        context,
                                        initialEvent: event,
                                      );
                                      if (!mounted) return;
                                      if (newEvent != null) {
                                        final BuildContext localContext =
                                            context;
                                        if (_hasConflict(
                                          newEvent,
                                          exclude: event,
                                        )) {
                                          // ignore: use_build_context_synchronously
                                          _showConflictReminder(localContext);
                                        } else {
                                          setState(() {
                                            final globalIndex = _events.indexOf(
                                              event,
                                            );
                                            _events[globalIndex] = Event(
                                              id: event.id,
                                              title: newEvent.title,
                                              startDateTime:
                                                  newEvent.startDateTime,
                                              duration: newEvent.duration,
                                            );
                                          });
                                          // 更新数据库
                                          if (event.id != null) {
                                            await _storageService.updateEvent(
                                              id: event.id!,
                                              title: newEvent.title,
                                              startDateTime:
                                                  newEvent.startDateTime,
                                              duration: newEvent.duration,
                                            );
                                          }
                                        }
                                      }
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete),
                                    onPressed: () {
                                      setState(() {
                                        _events.remove(event);
                                      });
                                      // 从数据库删除
                                      if (event.id != null) {
                                        _storageService.deleteEvent(event.id!);
                                      }
                                    },
                                  ),
                                ],
                              ),
                            );
                          }),
                        );
                      }).toList(),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSettingsPage() {
    return ListView(
      children: [
        Card(
          margin: const EdgeInsets.all(8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '局域网同步',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _syncHostController,
                  decoration: const InputDecoration(labelText: '主机地址 (IP)'),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _syncPortController,
                        decoration: const InputDecoration(labelText: '端口'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _syncTokenController,
                        decoration: const InputDecoration(
                          labelText: '配对 Token (可选)',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ElevatedButton(
                      onPressed: _isHosting
                          ? null
                          : () async {
                              final port =
                                  int.tryParse(_syncPortController.text) ??
                                  4040;
                              final token = _syncTokenController.text.isNotEmpty
                                  ? _syncTokenController.text
                                  : null;
                              await SyncService.instance.startServer(
                                port: port,
                                token: token,
                              );
                              if (!mounted) return;
                              setState(() {
                                _isHosting = true;
                              });
                            },
                      child: const Text('作为主机启动'),
                    ),
                    ElevatedButton(
                      onPressed: !_isHosting
                          ? null
                          : () async {
                              await SyncService.instance.stopServer();
                              if (!mounted) return;
                              setState(() {
                                _isHosting = false;
                              });
                            },
                      child: const Text('停止主机'),
                    ),
                    ElevatedButton(
                      onPressed: _isConnected
                          ? null
                          : () async {
                              final host = _syncHostController.text.trim();
                              final port =
                                  int.tryParse(_syncPortController.text) ??
                                  4040;
                              final token = _syncTokenController.text.isNotEmpty
                                  ? _syncTokenController.text
                                  : null;
                              if (host.isEmpty) return;
                              if (token != null) {
                                await SyncService.instance.connectWithToken(
                                  host,
                                  port,
                                  token,
                                );
                              } else {
                                await SyncService.instance.connect(host, port);
                              }
                            },
                      child: const Text('连接主机'),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        final found = await SyncService.instance
                            .discoverHosts();
                        if (!mounted) return;
                        if (found.isEmpty) {
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('未发现主机'),
                              content: const Text('在本局域网内未发现运行中的主机。'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('确定'),
                                ),
                              ],
                            ),
                          );
                          return;
                        }
                        showDialog(
                          context: context,
                          builder: (ctx) {
                            return AlertDialog(
                              title: const Text('选择要连接的主机'),
                              content: SizedBox(
                                width: double.maxFinite,
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: found.length,
                                  itemBuilder: (context, index) {
                                    final item = found[index];
                                    final host = item['host'] ?? '';
                                    final port = item['port']?.toString() ?? '';
                                    final token = item['token'] ?? '';
                                    return ListTile(
                                      title: Text('$host:$port'),
                                      subtitle: Text(
                                        token != '' ? '需要 Token' : '无需 Token',
                                      ),
                                      onTap: () {
                                        _syncHostController.text = host;
                                        _syncPortController.text = port;
                                        _syncTokenController.text = token ?? '';
                                        Navigator.pop(ctx);
                                      },
                                    );
                                  },
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('取消'),
                                ),
                              ],
                            );
                          },
                        );
                      },
                      child: const Text('扫描局域网'),
                    ),
                    ElevatedButton(
                      onPressed: !_isConnected
                          ? null
                          : () async {
                              await SyncService.instance.disconnect();
                            },
                      child: const Text('断开连接'),
                    ),
                    ElevatedButton(
                      onPressed: _savedHosts.isEmpty
                          ? null
                          : () async {
                              // 填充第一个历史主机到输入框
                              final item = _savedHosts.first;
                              _syncHostController.text = item['host'] ?? '';
                              _syncPortController.text =
                                  '${item['port'] ?? ''}';
                              _syncTokenController.text = item['token'] ?? '';
                            },
                      child: const Text('使用最近主机'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('状态：'),
                    const SizedBox(width: 8),
                    Text(
                      _isHosting ? '主机(已启动)' : (_isConnected ? '已连接' : '未连接'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_savedHosts.isNotEmpty)
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '最近主机',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ..._savedHosts.map((h) {
                    final host = h['host'] ?? '';
                    final port = h['port']?.toString() ?? '';
                    final token = h['token'] ?? '';
                    return ListTile(
                      title: Text('$host:$port'),
                      subtitle: Text(token != '' ? '需要 Token' : '无需 Token'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () async {
                          final idx = _savedHosts.indexOf(h);
                          await SyncService.instance.removeSavedHostAt(idx);
                          await _loadSavedHosts();
                        },
                      ),
                      onTap: () {
                        _syncHostController.text = host;
                        _syncPortController.text = port;
                        _syncTokenController.text = token ?? '';
                      },
                    );
                  }),
                ],
              ),
            ),
          ),
        SwitchListTile(
          title: const Text('深色主题'),
          value: _isDarkTheme,
          onChanged: (val) {
            setState(() {
              _isDarkTheme = val;
            });
          },
        ),
        SwitchListTile(
          title: const Text('启用提醒'),
          value: _notificationsEnabled,
          onChanged: (val) {
            setState(() {
              _notificationsEnabled = val;
            });
          },
        ),
        ListTile(
          title: const Text('默认日历视图'),
          trailing: DropdownButton<CalendarFormat>(
            value: _defaultCalendarFormat,
            items: const [
              DropdownMenuItem(value: CalendarFormat.month, child: Text('月视图')),
              DropdownMenuItem(
                value: CalendarFormat.twoWeeks,
                child: Text('周视图'),
              ),
              DropdownMenuItem(value: CalendarFormat.week, child: Text('日视图')),
            ],
            onChanged: (val) {
              if (val != null) {
                setState(() {
                  _defaultCalendarFormat = val;
                  _calendarFormat = val;
                });
              }
            },
          ),
        ),
        ListTile(
          title: const Text('重置所有日程'),
          trailing: IconButton(
            icon: const Icon(Icons.delete_forever),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('确认重置？'),
                  content: const Text('此操作会删除所有日程，无法撤销！'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _events.clear();
                        });
                        // 清空数据库
                        _storageService.clearAll();
                        Navigator.pop(context);
                      },
                      child: const Text('确定'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<Event?> _showEventDialog(
    BuildContext context, {
    Event? initialEvent,
    DateTime? day,
  }) {
    TextEditingController controller = TextEditingController(
      text: initialEvent?.title ?? '',
    );
    DateTime selectedDateTime =
        initialEvent?.startDateTime ?? (day ?? DateTime.now());
    Duration selectedDuration =
        initialEvent?.duration ?? const Duration(hours: 1);
    final List<Duration> durationOptions = [
      const Duration(minutes: 15),
      const Duration(minutes: 30),
      const Duration(minutes: 45),
      const Duration(hours: 1),
      const Duration(hours: 2),
      const Duration(hours: 3),
      const Duration(hours: 6),
      const Duration(hours: 12),
      const Duration(days: 1),
      const Duration(days: 2),
      const Duration(days: 3),
      const Duration(days: 7),
    ];

    return showDialog<Event>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(initialEvent == null ? '添加事件' : '编辑事件'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(hintText: '事件内容'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('开始日期：'),
                      TextButton(
                        onPressed: () async {
                          final localContext = context;
                          final pickedDate = await showDatePicker(
                            context: localContext,
                            initialDate: selectedDateTime,
                            firstDate: DateTime(2010),
                            lastDate: DateTime(2035),
                          );
                          if (!mounted) return;
                          if (pickedDate != null) {
                            setState(() {
                              selectedDateTime = DateTime(
                                pickedDate.year,
                                pickedDate.month,
                                pickedDate.day,
                                selectedDateTime.hour,
                                selectedDateTime.minute,
                              );
                            });
                          }
                        },
                        child: Text(
                          '${selectedDateTime.year}-${selectedDateTime.month.toString().padLeft(2, '0')}-${selectedDateTime.day.toString().padLeft(2, '0')}',
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Text('开始时间：'),
                      TextButton(
                        onPressed: () async {
                          final localContext = context;
                          final pickedTime = await showTimePicker(
                            context: localContext,
                            initialTime: TimeOfDay.fromDateTime(
                              selectedDateTime,
                            ),
                          );
                          if (!mounted) return;
                          if (pickedTime != null) {
                            setState(() {
                              selectedDateTime = DateTime(
                                selectedDateTime.year,
                                selectedDateTime.month,
                                selectedDateTime.day,
                                pickedTime.hour,
                                pickedTime.minute,
                              );
                            });
                          }
                        },
                        child: Text(
                          '${selectedDateTime.hour.toString().padLeft(2, '0')}:${selectedDateTime.minute.toString().padLeft(2, '0')}',
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Text('持续时长：'),
                      DropdownButton<Duration>(
                        value: selectedDuration,
                        items: durationOptions.map((duration) {
                          String label;
                          if (duration.inDays > 0) {
                            label = '${duration.inDays}天';
                          } else if (duration.inHours > 0) {
                            label = '${duration.inHours}小时';
                          } else {
                            label = '${duration.inMinutes}分钟';
                          }
                          return DropdownMenuItem(
                            value: duration,
                            child: Text(label),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              selectedDuration = value;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (controller.text.trim().isNotEmpty) {
                      Navigator.pop(
                        context,
                        Event(
                          title: controller.text.trim(),
                          startDateTime: selectedDateTime,
                          duration: selectedDuration,
                        ),
                      );
                    }
                  },
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // 日程视图添加事件（选择日期 + 输入内容 + 时间 + 时长）
  Future<Event?> _showAddEventWithDateDialog(BuildContext context) async {
    DateTime selectedDateTime = DateTime.now();
    TextEditingController controller = TextEditingController();
    Duration selectedDuration = const Duration(hours: 1);
    final List<Duration> durationOptions = [
      const Duration(minutes: 15),
      const Duration(minutes: 30),
      const Duration(minutes: 45),
      const Duration(hours: 1),
      const Duration(hours: 2),
      const Duration(hours: 3),
      const Duration(hours: 6),
      const Duration(hours: 12),
      const Duration(days: 1),
      const Duration(days: 2),
      const Duration(days: 3),
      const Duration(days: 7),
    ];

    return showDialog<Event>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('添加日程'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.calendar_today),
                    label: Text(
                      '${selectedDateTime.year}-${selectedDateTime.month.toString().padLeft(2, '0')}-${selectedDateTime.day.toString().padLeft(2, '0')}',
                    ),
                    onPressed: () async {
                      final localContext = context;
                      final pickedDate = await showDatePicker(
                        context: localContext,
                        initialDate: selectedDateTime,
                        firstDate: DateTime(2010),
                        lastDate: DateTime(2035),
                      );
                      if (!mounted) return;
                      if (pickedDate != null) {
                        setState(() {
                          selectedDateTime = DateTime(
                            pickedDate.year,
                            pickedDate.month,
                            pickedDate.day,
                            selectedDateTime.hour,
                            selectedDateTime.minute,
                          );
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('开始时间：'),
                      TextButton(
                        onPressed: () async {
                          final localContext = context;
                          final pickedTime = await showTimePicker(
                            context: localContext,
                            initialTime: TimeOfDay.fromDateTime(
                              selectedDateTime,
                            ),
                          );
                          if (!mounted) return;
                          if (pickedTime != null) {
                            setState(() {
                              selectedDateTime = DateTime(
                                selectedDateTime.year,
                                selectedDateTime.month,
                                selectedDateTime.day,
                                pickedTime.hour,
                                pickedTime.minute,
                              );
                            });
                          }
                        },
                        child: Text(
                          '${selectedDateTime.hour.toString().padLeft(2, '0')}:${selectedDateTime.minute.toString().padLeft(2, '0')}',
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Text('持续时长：'),
                      DropdownButton<Duration>(
                        value: selectedDuration,
                        items: durationOptions.map((duration) {
                          String label;
                          if (duration.inDays > 0) {
                            label = '${duration.inDays}天';
                          } else if (duration.inHours > 0) {
                            label = '${duration.inHours}小时';
                          } else {
                            label = '${duration.inMinutes}分钟';
                          }
                          return DropdownMenuItem(
                            value: duration,
                            child: Text(label),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              selectedDuration = value;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(hintText: '事件内容'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (controller.text.trim().isNotEmpty) {
                      Navigator.pop(
                        context,
                        Event(
                          title: controller.text.trim(),
                          startDateTime: selectedDateTime,
                          duration: selectedDuration,
                        ),
                      );
                    }
                  },
                  child: const Text('添加'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
