import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class RectYearCalendar extends StatefulWidget {
  final DateTime? initialDate;
  final ValueChanged<DateTime>? onChanged;
  final bool loadScanCounts;
  final EdgeInsets padding;

  const RectYearCalendar({
    super.key,
    this.initialDate,
    this.onChanged,
    this.loadScanCounts = true,
    this.padding = const EdgeInsets.all(8),
  });

  @override
  State<RectYearCalendar> createState() => _RectYearCalendarState();
}

class _RectYearCalendarState extends State<RectYearCalendar> {
  late final int _year;
  late DateTime _selected;
  late int _month;

  Map<DateTime, int> _counts = const {};
  Set<DateTime> _recycledDays = const {};
  int _maxCount = 0;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    final seed = widget.initialDate ?? now;
    _selected = DateTime(_year, seed.month, seed.day);
    _month = _selected.month;
    if (widget.loadScanCounts) _fetchCounts();
  }

  Future<void> _fetchCounts() async {
    setState(() => _loading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        _counts = {};
        _recycledDays = {};
        _maxCount = 0;
      } else {
        final snap = await FirebaseFirestore.instance
            .collection('scans')
            .where('userId', isEqualTo: uid)
            .get();

        final Map<DateTime, int> perDay = {};
        final Set<DateTime> recycled = {};
        int maxC = 0;

        for (final doc in snap.docs) {
          final data = doc.data();
          final ts = data['timestamp'];
          if (ts is! Timestamp) continue;
          final d = ts.toDate().toLocal();
          if (d.year != _year) continue;

          final key = DateTime(d.year, d.month, d.day);
          final v = (perDay[key] ?? 0) + 1;
          perDay[key] = v;
          if (v > maxC) maxC = v;

          if (data['recyclable'] == true) {
            recycled.add(key);
          }
        }

        _counts = perDay;
        _recycledDays = recycled;
        _maxCount = maxC;
      }
    } catch (_) {
      _counts = {};
      _recycledDays = {};
      _maxCount = 0;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _goPrevMonth() {
    if (_month > 1) setState(() => _month--);
  }

  void _goNextMonth() {
    if (_month < 12) setState(() => _month++);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selected,
      firstDate: DateTime(_year, 1, 1),
      lastDate: DateTime(_year, 12, 31),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF2FD885),
              surface: Color(0xFF1C1C1E),
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: const Color(0xFF1C1C1E),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      final clamped = DateTime(_year, picked.month, picked.day);
      setState(() {
        _selected = clamped;
        _month = clamped.month;
      });
      widget.onChanged?.call(_selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dayLabels = const ['M','T','W','T','F','S','S'];
    return LayoutBuilder(
      builder: (context, c) {
        final maxW = c.maxWidth.isFinite ? c.maxWidth : MediaQuery.of(context).size.width;
        final headerH = 44.0;
        final dayHeaderH = 18.0;
        final rowsH = _estimatedRowsHeight(maxW);
        final totalH = headerH + 8 + dayHeaderH + 6 + rowsH + (_loading ? 24 : 0) + 8;

        return Container(
          padding: widget.padding,
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          constraints: BoxConstraints(
            minWidth: 220,
            maxWidth: maxW,
            minHeight: totalH,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _header(),
              const SizedBox(height: 8),
              _daysHeader(dayLabels, maxW),
              const SizedBox(height: 6),
              _monthGrid(maxW),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2FD885)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _header() {
    final today = DateTime.now();
    final isTodayInView = today.year == _year && today.month == _month;
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          const Spacer(),
          _chip(
            icon: Icons.today_rounded,
            label: isTodayInView ? '${_monthName(_month)} $_year' : 'Today',
            onTap: () {
              final t = DateTime(_year, today.month, today.day);
              setState(() {
                _selected = t;
                _month = today.month;
              });
              widget.onChanged?.call(_selected);
            },
          ),
          const SizedBox(width: 6),
          _chip(icon: Icons.event_rounded, label: 'Pick', onTap: _pickDate),
          const SizedBox(width: 6),
          IconButton(
            onPressed: _month > 1 ? _goPrevMonth : null,
            icon: const Icon(Icons.chevron_left, color: Colors.white, size: 15),
            splashRadius:10,
          ),
          IconButton(
            onPressed: _month < 12 ? _goNextMonth : null,
            icon: const Icon(Icons.chevron_right, color: Colors.white, size: 15),
            splashRadius: 10,
          ),
        ],
      ),
    );
  }

  Widget _chip({required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: const Color(0xFF2FD885)),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _daysHeader(List<String> labels, double maxW) {
    final cellW = _cellW(maxW);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: labels.map((d) {
        return SizedBox(
          width: cellW, height: 18,
          child: Center(
            child: Text(
              d,
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontWeight: FontWeight.w700,
                fontSize: 10,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _monthGrid(double maxW) {
    final first = DateTime(_year, _month, 1);
    final daysInMonth = _daysInMonth(_year, _month);
    final leading = (first.weekday % 7); // Mon=1..Sun=7 -> 0..6
    final totalCells = leading + daysInMonth;
    final rows = ((totalCells + 6) / 7).floor();

    final today = DateTime.now();
    final todayKey = DateTime(_year, today.month, today.day);

    final cellW = _cellW(maxW);
    final cellH = _cellH(maxW);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(rows, (r) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (c) {
              final index = r * 7 + c;
              final day = index - leading + 1;
              if (day < 1 || day > daysInMonth) {
                return SizedBox(width: cellW, height: cellH);
              }
              final date = DateTime(_year, _month, day);
              final isToday = (date == todayKey);
              final isSelected = (_selected.year == _year && _selected.month == _month && _selected.day == day);
              final count = _counts[date] ?? 0;
              final tinted = widget.loadScanCounts ? _heat(count, _maxCount) : null;
              final recycled = _recycledDays.contains(date);

              return _dayCell(
                day: day,
                width: cellW,
                height: cellH,
                isToday: isToday,
                isSelected: isSelected,
                bg: tinted,
                recycled: recycled,
                onTap: () {
                  setState(() => _selected = date);
                  widget.onChanged?.call(_selected);
                },
              );
            }),
          ),
        );
      }),
    );
  }

  Widget _dayCell({
    required int day,
    required double width,
    required double height,
    required bool isToday,
    required bool isSelected,
    required bool recycled,
    required VoidCallback onTap,
    Color? bg,
  }) {
    final borderColor = isSelected ? const Color(0xFF2FD885) : Colors.white12;
    final ring = isToday
        ? BoxShadow(color: const Color(0xFF2FD885).withOpacity(0.40), blurRadius: 8, spreadRadius: 0.5)
        : const BoxShadow(color: Colors.transparent);

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: bg ?? Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor, width: isSelected ? 1.4 : 1),
          boxShadow: [ring],
        ),
        child: Stack(
          children: [
            Center(
              child: Text(
                '$day',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: isSelected ? const Color.fromARGB(255, 47, 134, 216) : Colors.white.withOpacity(0.9),
                  fontSize: 12,
                ),
              ),
            ),
            if (recycled)
              Positioned(
                right: 4, bottom: 4,
                child: Container(
                  width: 6, height: 6,
                  decoration: BoxDecoration(
                    color: const Color.fromARGB(255, 255, 255, 255),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: const Color(0xFF2FD885).withOpacity(0.5), blurRadius: 6, spreadRadius: 0.5),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }


  double _cellW(double maxW) {
    final available = (maxW - widget.padding.horizontal - 16);
    return (available / 7.6).clamp(30.0, 46.0);
  }

  double _cellH(double maxW) {
    final w = _cellW(maxW);
    return (w * 0.78).clamp(26.0, 40.0);
  }

  double _estimatedRowsHeight(double maxW) {
    final first = DateTime(_year, _month, 1);
    final days = _daysInMonth(_year, _month);
    final leading = (first.weekday % 7);
    final totalCells = leading + days;
    final rows = ((totalCells + 6) / 7).floor();
    final h = _cellH(maxW);
    return rows * h + (rows - 1) * 4;
  }


  int _daysInMonth(int year, int month) {
    final firstNext = (month == 12) ? DateTime(year + 1, 1, 1) : DateTime(year, month + 1, 1);
    return firstNext.subtract(const Duration(days: 1)).day;
  }

  String _monthName(int m) {
    const names = [
      'January','February','March','April','May','June',
      'July','August','September','October','November','December'
    ];
    return names[m - 1];
  }

  Color _heat(int count, int max) {
    if (count <= 0 || max <= 0) return Colors.white.withOpacity(0.04);
    final t = (count / max).clamp(0.0, 1.0);
    const end = Color(0xFF2FD885);
    final start = const Color(0xFFBFF4E3).withOpacity(0.35);
    return Color.lerp(start, end, math.pow(t, 0.6).toDouble())!;
  }
}
