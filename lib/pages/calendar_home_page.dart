import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

class Event {
  final String title;
  final TimeOfDay startTime;
  final Duration duration;

  Event({required this.title, required this.startTime, required this.duration});

  String get timeRange {
    final end = DateTime(
      2000,
      1,
      1,
      startTime.hour,
      startTime.minute,
    ).add(duration);
    final endTime = TimeOfDay(hour: end.hour, minute: end.minute);
    return '${_formatTimeOfDay(startTime)} - ${_formatTimeOfDay(endTime)}';
  }
}

String _formatTimeOfDay(TimeOfDay time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
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
  Map<DateTime, List<Event>> _events = {};

  // 设置
  bool _isDarkTheme = false;
  bool _notificationsEnabled = true;
  CalendarFormat _defaultCalendarFormat = CalendarFormat.month;

  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  DateTime _normalizeDate(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  bool _eventEquals(Event a, Event b) =>
      a.title == b.title &&
      a.startTime == b.startTime &&
      a.duration == b.duration;

  bool _eventsOverlap(Event a, Event b) {
    final aStart = DateTime(2000, 1, 1, a.startTime.hour, a.startTime.minute);
    final aEnd = aStart.add(a.duration);
    final bStart = DateTime(2000, 1, 1, b.startTime.hour, b.startTime.minute);
    final bEnd = bStart.add(b.duration);
    return aStart.isBefore(bEnd) && bStart.isBefore(aEnd);
  }

  bool _hasConflict(DateTime day, Event newEvent, {Event? exclude}) {
    final events = _events[_normalizeDate(day)] ?? [];
    for (final event in events) {
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
    return _events[_normalizeDate(day)] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    Widget bodyContent;

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
                              final localContext = context;
                              final newEvent = await _showEventDialog(
                                localContext,
                                day: day,
                                initialEvent: event,
                              );
                              if (!mounted) return;
                              if (newEvent != null) {
                                setState(() {
                                  events[index] = newEvent;
                                  _events[_normalizeDate(day)] = events;
                                });
                                if (_hasConflict(
                                  day,
                                  newEvent,
                                  exclude: event,
                                )) {
                                  _showConflictReminder(this.context);
                                }
                              }
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () {
                              setState(() {
                                events.removeAt(index);
                                if (events.isEmpty) {
                                  _events.remove(_normalizeDate(day));
                                } else {
                                  _events[_normalizeDate(day)] = events;
                                }
                              });
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
              final localContext = context;
              final newEvent = await _showEventDialog(localContext, day: day);
              if (!mounted) return;
              if (newEvent != null) {
                setState(() {
                  _events.putIfAbsent(_normalizeDate(day), () => []);
                  _events[_normalizeDate(day)]!.add(newEvent);
                });
                if (_hasConflict(day, newEvent)) {
                  _showConflictReminder(this.context);
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
              final localContext = context;
              final result = await _showAddEventWithDateDialog(localContext);
              if (!mounted) return;
              if (result != null) {
                setState(() {
                  _events.putIfAbsent(result.key, () => []);
                  _events[result.key]!.add(result.value);
                });
                if (_hasConflict(result.key, result.value)) {
                  _showConflictReminder(this.context);
                }
              }
            },
          ),
        ),
        Expanded(
          child: _events.isEmpty
              ? const Center(child: Text('暂无日程'))
              : ListView(
                  children: (_events.keys.toList()..sort()).map((day) {
                    final dayEvents = _events[day]!;
                    return ExpansionTile(
                      title: Text(
                        '${day.year}-${day.month}-${day.day} (${dayEvents.length})',
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
                                  final localContext = context;
                                  final newEvent = await _showEventDialog(
                                    localContext,
                                    day: day,
                                    initialEvent: event,
                                  );
                                  if (!mounted) return;
                                  if (newEvent != null) {
                                    setState(() {
                                      dayEvents[index] = newEvent;
                                    });
                                    if (_hasConflict(
                                      day,
                                      newEvent,
                                      exclude: event,
                                    )) {
                                      _showConflictReminder(this.context);
                                    }
                                  }
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete),
                                onPressed: () {
                                  setState(() {
                                    dayEvents.removeAt(index);
                                    if (dayEvents.isEmpty) _events.remove(day);
                                  });
                                },
                              ),
                            ],
                          ),
                        );
                      }),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  Widget _buildSettingsPage() {
    return ListView(
      children: [
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
    required DateTime day,
  }) {
    TextEditingController controller = TextEditingController(
      text: initialEvent?.title ?? '',
    );
    TimeOfDay selectedTime =
        initialEvent?.startTime ?? const TimeOfDay(hour: 9, minute: 0);
    Duration selectedDuration =
        initialEvent?.duration ?? const Duration(hours: 1);
    final List<Duration> durationOptions = const [
      Duration(minutes: 15),
      Duration(minutes: 30),
      Duration(minutes: 45),
      Duration(hours: 1),
      Duration(hours: 2),
      Duration(hours: 3),
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
                      const Text('开始时间：'),
                      TextButton(
                        onPressed: () async {
                          final localContext = context;
                          final picked = await showTimePicker(
                            context: localContext,
                            initialTime: selectedTime,
                          );
                          if (picked != null) {
                            setState(() {
                              selectedTime = picked;
                            });
                          }
                        },
                        child: Text(_formatTimeOfDay(selectedTime)),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Text('持续时长：'),
                      DropdownButton<Duration>(
                        value: selectedDuration,
                        items: durationOptions.map((duration) {
                          final minutes = duration.inMinutes;
                          final label = minutes >= 60
                              ? '${minutes ~/ 60}小时${minutes % 60 == 0 ? '' : '${minutes % 60}分'}'
                              : '$minutes分钟';
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
                          startTime: selectedTime,
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
  Future<MapEntry<DateTime, Event>?> _showAddEventWithDateDialog(
    BuildContext context,
  ) async {
    DateTime selectedDate = _normalizeDate(DateTime.now());
    TextEditingController controller = TextEditingController();
    TimeOfDay selectedTime = const TimeOfDay(hour: 9, minute: 0);
    Duration selectedDuration = const Duration(hours: 1);
    final List<Duration> durationOptions = const [
      Duration(minutes: 15),
      Duration(minutes: 30),
      Duration(minutes: 45),
      Duration(hours: 1),
      Duration(hours: 2),
      Duration(hours: 3),
    ];

    return showDialog<MapEntry<DateTime, Event>>(
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
                      '${selectedDate.year}-${selectedDate.month}-${selectedDate.day}',
                    ),
                    onPressed: () async {
                      final localContext = context;
                      final picked = await showDatePicker(
                        context: localContext,
                        initialDate: selectedDate,
                        firstDate: DateTime(2010),
                        lastDate: DateTime(2035),
                      );
                      if (!mounted) return;
                      if (picked != null) {
                        setState(() {
                          selectedDate = _normalizeDate(picked);
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
                          final picked = await showTimePicker(
                            context: localContext,
                            initialTime: selectedTime,
                          );
                          if (!mounted) return;
                          if (picked != null) {
                            setState(() {
                              selectedTime = picked;
                            });
                          }
                        },
                        child: Text(_formatTimeOfDay(selectedTime)),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Text('持续时长：'),
                      DropdownButton<Duration>(
                        value: selectedDuration,
                        items: durationOptions.map((duration) {
                          final minutes = duration.inMinutes;
                          final label = minutes >= 60
                              ? '${minutes ~/ 60}小时${minutes % 60 == 0 ? '' : '${minutes % 60}分'}'
                              : '$minutes分钟';
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
                        MapEntry(
                          selectedDate,
                          Event(
                            title: controller.text.trim(),
                            startTime: selectedTime,
                            duration: selectedDuration,
                          ),
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
