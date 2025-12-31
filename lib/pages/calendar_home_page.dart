import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

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
  Map<DateTime, List<String>> _events = {};

  // 设置
  bool _isDarkTheme = false;
  bool _notificationsEnabled = true;
  CalendarFormat _defaultCalendarFormat = CalendarFormat.month;

  List<String> _getEventsForDay(DateTime day) {
    return _events[DateTime(day.year, day.month, day.day)] ?? [];
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
      theme: _isDarkTheme ? ThemeData.dark(useMaterial3: true) : ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
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
            BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: '日历'),
            BottomNavigationBarItem(icon: Icon(Icons.list), label: '日程'),
            BottomNavigationBarItem(icon: Icon(Icons.settings), label: '设置'),
          ],
        ),
      ),
    );
  }

  Widget _buildEventList(DateTime day) {
    List<String> events = _getEventsForDay(day);
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
          child: ListView.builder(
            itemCount: events.length,
            itemBuilder: (context, index) {
              String event = events[index];
              return ListTile(
                title: Text(event),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () async {
                        String? newEvent = await _showEventDialog(context, event);
                        if (newEvent != null && newEvent.isNotEmpty) {
                          setState(() {
                            events[index] = newEvent;
                            _events[DateTime(day.year, day.month, day.day)] = events;
                          });
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () {
                        setState(() {
                          events.removeAt(index);
                          _events[DateTime(day.year, day.month, day.day)] = events;
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
              String? newEvent = await _showEventDialog(context, '');
              if (newEvent != null && newEvent.isNotEmpty) {
                setState(() {
                  if (!_events.containsKey(DateTime(day.year, day.month, day.day))) {
                    _events[DateTime(day.year, day.month, day.day)] = [];
                  }
                  _events[DateTime(day.year, day.month, day.day)]!.add(newEvent);
                });
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
              final result = await _showAddEventWithDateDialog(context);
              if (result != null) {
                setState(() {
                  _events.putIfAbsent(result.key, () => []);
                  _events[result.key]!.add(result.value);
                });
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
                      title: Text('${day.year}-${day.month}-${day.day} (${dayEvents.length})'),
                      children: List.generate(dayEvents.length, (index) {
                        return ListTile(
                          title: Text(dayEvents[index]),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: () async {
                                  final newEvent = await _showEventDialog(context, dayEvents[index]);
                                  if (newEvent != null && newEvent.isNotEmpty) {
                                    setState(() {
                                      dayEvents[index] = newEvent;
                                    });
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
              DropdownMenuItem(value: CalendarFormat.twoWeeks, child: Text('周视图')),
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
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
                    ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _events.clear();
                          });
                          Navigator.pop(context);
                        },
                        child: const Text('确定')),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<String?> _showEventDialog(BuildContext context, String initialValue) {
    TextEditingController controller = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('请输入事件'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: '事件内容'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
            ElevatedButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('确定')),
          ],
        );
      },
    );
  }

  // 日程视图添加事件（选择日期 + 输入内容）
  Future<MapEntry<DateTime, String>?> _showAddEventWithDateDialog(BuildContext context) async {
    DateTime selectedDate = DateTime.now();
    TextEditingController controller = TextEditingController();

    return showDialog<MapEntry<DateTime, String>>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('添加日程'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.calendar_today),
                label: Text('${selectedDate.year}-${selectedDate.month}-${selectedDate.day}'),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime(2010),
                    lastDate: DateTime(2035),
                  );
                  if (picked != null) selectedDate = picked;
                },
              ),
              TextField(
                controller: controller,
                decoration: const InputDecoration(hintText: '事件内容'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
            ElevatedButton(
              onPressed: () {
                if (controller.text.isNotEmpty) {
                  Navigator.pop(
                    context,
                    MapEntry(
                      DateTime(selectedDate.year, selectedDate.month, selectedDate.day),
                      controller.text,
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
  }
}
