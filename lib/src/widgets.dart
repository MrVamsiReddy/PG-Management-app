import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'app_state.dart';
import 'theme.dart';

export 'format.dart';

/// Route guard: renders [child] only for owner/admin sessions. Tenants who
/// reach a management screen (deep link, stale navigation) get a polite
/// dead end instead of the data.
class ManagerOnly extends StatelessWidget {
  const ManagerOnly({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (AppScope.of(context).role == UserRole.tenant) {
      return Scaffold(
        appBar: AppBar(title: const Text('Not available')),
        body: const Center(child: EmptyState(icon: Icons.lock_outline, title: 'This area is for PG managers')),
      );
    }
    return child;
  }
}

/// Camera/gallery chooser → picked image compressed and returned as base64
/// (small enough to store inline), or null if cancelled or unavailable.
Future<String?> pickImageBase64(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Take a photo'), onTap: () => Navigator.pop(context, ImageSource.camera)),
        ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Choose from gallery'), onTap: () => Navigator.pop(context, ImageSource.gallery)),
      ]),
    ),
  );
  if (source == null) return null;
  try {
    final file = await ImagePicker().pickImage(source: source, maxWidth: 900, imageQuality: 55);
    if (file == null) return null;
    return base64Encode(await file.readAsBytes());
  } catch (_) {
    return null;
  }
}

Widget base64Image(String data, {double? height, BoxFit fit = BoxFit.cover}) =>
    Image.memory(base64Decode(data), height: height, width: double.infinity, fit: fit, gaplessPlayback: true);

IconData notificationIcon(NotificationType type) => switch (type) {
      NotificationType.payment => Icons.payments_outlined,
      NotificationType.visitor => Icons.badge_outlined,
      NotificationType.announcement => Icons.campaign_outlined,
      NotificationType.maintenance => Icons.build_outlined,
      NotificationType.attendance => Icons.how_to_reg_outlined,
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
    this.onTap,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color tint;
  final String? caption;

  /// When set, the whole tile is tappable (ripple + a chevron affordance).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.all(17),
      // Grid cells vary with screen width; scale down rather than overflow.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topLeft,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(color: tint.withValues(alpha: .13), borderRadius: BorderRadius.circular(11)),
              child: Icon(icon, color: tint, size: 21),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 40),
              const Icon(Icons.chevron_right, size: 18, color: Colors.black26),
            ],
          ]),
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
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : InkWell(onTap: onTap, child: content),
    );
  }
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
