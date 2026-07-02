import 'package:intl/intl.dart';

String inr(num value) => NumberFormat.currency(
      locale: 'en_IN', symbol: '₹', decimalDigits: 0,
    ).format(value);

/// `03 Jul`
String formatDay(DateTime date) => DateFormat('dd MMM').format(date);

/// `03 Jul 2026`
String formatFullDate(DateTime date) => DateFormat('dd MMM yyyy').format(date);

/// `July 2026`
String formatMonth(DateTime date) => DateFormat('MMMM yyyy').format(date);

/// `July`
String formatMonthName(DateTime date) => DateFormat('MMMM').format(date);

/// `8:45 AM`
String formatTime(DateTime date) => DateFormat('h:mm a').format(date);

/// `Friday, 03 July`
String formatWeekday(DateTime date) => DateFormat('EEEE, dd MMMM').format(date);

bool isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// `Today, 5:20 PM` / `Yesterday, 9:10 AM` / `30 Jun, 1:45 PM`
String formatWhen(DateTime date) {
  final now = DateTime.now();
  if (isSameDay(date, now)) return 'Today, ${formatTime(date)}';
  if (isSameDay(date, now.subtract(const Duration(days: 1)))) return 'Yesterday, ${formatTime(date)}';
  return '${formatDay(date)}, ${formatTime(date)}';
}

/// `Just now` / `12 min ago` / `3 hrs ago` / `Yesterday` / `30 Jun`
String relativeTime(DateTime date) {
  final elapsed = DateTime.now().difference(date);
  if (elapsed.inMinutes < 1) return 'Just now';
  if (elapsed.inMinutes < 60) return '${elapsed.inMinutes} min ago';
  if (elapsed.inHours < 24) return '${elapsed.inHours} ${elapsed.inHours == 1 ? 'hr' : 'hrs'} ago';
  if (isSameDay(date, DateTime.now().subtract(const Duration(days: 1)))) return 'Yesterday';
  return formatDay(date);
}
