import 'package:flutter/material.dart';

import 'theme.dart';

export 'app_state.dart' show inr;

IconData notificationIcon(String type) => switch (type) {
      'payment' => Icons.payments_outlined,
      'visitor' => Icons.badge_outlined,
      'announcement' => Icons.campaign_outlined,
      _ => Icons.build_outlined,
    };

class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.action});
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Theme.of(context).textTheme.headlineMedium),
              if (subtitle != null) ...[
                const SizedBox(height: 5),
                Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ]),
          ),
          if (action != null) action!,
        ],
      );
}

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.tint,
    this.caption,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color tint;
  final String? caption;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(17),
          // Grid cells vary with screen width; scale down rather than overflow.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topLeft,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(color: tint.withValues(alpha: .13), borderRadius: BorderRadius.circular(11)),
                child: Icon(icon, color: tint, size: 21),
              ),
              const SizedBox(height: 16),
              Text(value, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 25)),
              const SizedBox(height: 3),
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
              if (caption != null) ...[
                const SizedBox(height: 8),
                Text(caption!, style: const TextStyle(color: primary, fontWeight: FontWeight.w700, fontSize: 12)),
              ],
            ]),
          ),
        ),
      );
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final lower = text.toLowerCase();
    final color = lower.contains('paid') || lower.contains('resolved') || lower.contains('verified') || lower == 'in' || lower.contains('signed') || lower.contains('generated')
        ? primary
        : lower.contains('overdue') || lower.contains('high') || lower.contains('declined')
            ? const Color(0xFFD44B47)
            : lower.contains('progress') || lower.contains('inside') || lower.contains('medium')
                ? const Color(0xFF3478C7)
                : const Color(0xFFB7791F);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: .11), borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11)),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(40),
        child: Column(children: [
          Icon(icon, size: 46, color: Colors.black26),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
        ]),
      );
}

Future<void> showAppSheet(BuildContext context, Widget child) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .9),
        padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
        decoration: const BoxDecoration(
          color: canvas,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: child,
      ),
    );

class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});
  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(4)),
        ),
      );
}

class FormLabel extends StatelessWidget {
  const FormLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 7, top: 12),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
      );
}
