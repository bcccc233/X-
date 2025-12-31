import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

class Event {
  String title;
  Event(this.title);

  @override
  String toString() => title;
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

  // 内存存储事件：日期 → 事件列表
  final Map<DateTime, List<Event>> _events = {};

  List<Event> _getEventsForDay(DateTime day) {
    return _events[DateTime(day.year, day.month, day.day)] ?? [];
  }

  void _addEvent(DateTime day, String title) {
    final key = DateTime(day.year, day.month, day.day);
    if (_events.containsKey(key)) {
      _events[key]!.add(Event(title));
    } else {
      _events[key] = [Event(title)];
    }
    setState(() {});
  }

  void _editEvent(DateTime day, int index, String newTitle) {
    final key = DateTime(day.year, day.month, day.day);
    if (_events.containsKey(key)) {
      _events[key]![index].title = newTitle;
      setState(() {});
    }
  }

  void _deleteEvent(DateTime day, int index) {
    final key = DateTime(day.year, day.month, day.day);
    if (_events.containsKey(key)) {
      _events[key]!.removeAt(index);
      if (_events[key]!.isEmpty) {
        _events.remove(key);
      }
      setState(() {});
    }
  }

  Future<void> _showAddEventDialog(DateTime day) async {
    final TextEditingController controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("添加事件"),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: "请输入事件内容"),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text("取消")),
          TextButton(
              onPressed: () {
                if (controller.text.isNotEmpty) {
                  _addEvent(day, controller.text);
                }
                Navigator.pop(context);
              },
              child: const Text("添加")),
        ],
      ),
    );
  }

  Future<void> _showEditEventDialog(DateTime day, int index) async {
    final TextEditingController controller =
        TextEditingController(text: _getEventsForDay(day)[index].title);
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("编辑事件"),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: "编辑事件内容"),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text("取消")),
          TextButton(
              onPressed: () {
                if (controller.text.isNotEmpty) {
                  _editEvent(day, index, controller.text);
                }
                Navigator.pop(context);
              },
              child: const Text("保存")),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_selectedDay != null)
            IconButton(
                icon: const Icon(Icons.add),
                tooltip: "添加事件",
                onPressed: () => _showAddEventDialog(_selectedDay!)),
        ],
      ),
      body: Column(
        children: [
          TableCalendar(
            firstDay: DateTime.utc(2010, 1, 1),
            lastDay: DateTime.utc(2035, 12, 31),
            focusedDay: _focusedDay,
            calendarFormat: _calendarFormat,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            eventLoader: _getEventsForDay,
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
          ),
          Expanded(
            child: _selectedDay == null
                ? const Center(
                    child: Text(
                      '请选择一个日期',
                      style: TextStyle(fontSize: 16),
                    ),
                  )
                : ListView.builder(
                    itemCount: _getEventsForDay(_selectedDay!).length,
                    itemBuilder: (context, index) {
                      final event = _getEventsForDay(_selectedDay!)[index];
                      return ListTile(
                        title: Text(event.title),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () =>
                                  _showEditEventDialog(_selectedDay!, index),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () =>
                                  _deleteEvent(_selectedDay!, index),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
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
          BottomNavigationBarItem(
            icon: Icon(Icons.list),
            label: '日程',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
