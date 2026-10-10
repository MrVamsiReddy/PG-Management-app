import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'app_state.dart';
import 'l10n.dart';
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
      final l = AppLocalizations.of(context);
      return Scaffold(
        appBar: AppBar(title: Text(l.t('common.notAvailable'))),
        body: Center(
            child: EmptyState(
                icon: Icons.lock_outline, title: l.t('common.managersOnly'))),
      );
    }
    return child;
  }
}

/// Camera/gallery chooser → picked image compressed and returned as base64
/// (small enough to store inline), or null if cancelled or unavailable.
Future<String?> pickImageBase64(BuildContext context,
    {double maxWidth = 900, int quality = 55}) async {
  final l = AppLocalizations.of(context);
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(l.t('common.takePhoto')),
            onTap: () => Navigator.pop(context, ImageSource.camera)),
        ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(l.t('common.fromGallery')),
            onTap: () => Navigator.pop(context, ImageSource.gallery)),
      ]),
    ),
  );
  if (source == null) return null;
  try {
    final file = await ImagePicker()
        .pickImage(source: source, maxWidth: maxWidth, imageQuality: quality);
    if (file == null) return null;
    return base64Encode(await file.readAsBytes());
  } catch (_) {
    return null;
  }
}

/// Decoded bytes of recently shown base64 images. Decoding a photo on every
/// rebuild made scrolling stutter (worst on iPhone web apps); reusing the
/// same bytes also lets Flutter reuse the decoded picture.
final _imageBytes = <String, Uint8List>{};
const _imageBytesLimit = 40;

/// The bytes of a base64 image, decoded once. Null when it isn't valid.
Uint8List? decodedImage(String data) {
  final cached = _imageBytes.remove(data);
  if (cached != null) {
    _imageBytes[data] = cached; // most recently used goes last
    return cached;
  }
  final Uint8List bytes;
  try {
    bytes = base64Decode(data);
  } on FormatException {
    return null;
  }
  _imageBytes[data] = bytes;
  if (_imageBytes.length > _imageBytesLimit) {
    _imageBytes.remove(_imageBytes.keys.first);
  }
  return bytes;
}

/// Shows a stored base64 image. Tenants upload these, so bad data shows a
/// placeholder instead of breaking the screen.
Widget base64Image(String data, {double? height, BoxFit fit = BoxFit.cover}) {
  final placeholder = SizedBox(
      height: height ?? 120,
      width: double.infinity,
      child: const Center(child: Icon(Icons.broken_image_outlined)));
  final bytes = decodedImage(data);
  if (bytes == null) return placeholder;
  return Image.memory(bytes,
      height: height,
      width: double.infinity,
      fit: fit,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => placeholder);
}

IconData notificationIcon(NotificationType type) => switch (type) {
      NotificationType.payment => Icons.payments_outlined,
      NotificationType.visitor => Icons.badge_outlined,
      NotificationType.announcement => Icons.campaign_outlined,
      NotificationType.maintenance => Icons.build_outlined,
      NotificationType.attendance => Icons.how_to_reg_outlined,
    };

class PageHeader extends StatelessWidget {
  const PageHeader(
      {super.key, required this.title, this.subtitle, this.action});
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Full-width header: the chevron affordance pins to the card's
            // top-right corner instead of floating beside the icon.
            Row(children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                    color: tint.withValues(alpha: .13),
                    borderRadius: BorderRadius.circular(11)),
                child: Icon(icon, color: tint, size: 21),
              ),
              const Spacer(),
              if (onTap != null)
                Icon(Icons.chevron_right, size: 18, color: faint),
            ]),
            const SizedBox(height: 14),
            // Numbers vary in width; scale down rather than overflow in
            // narrow grid cells.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topLeft,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(value,
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(fontSize: 25)),
                    const SizedBox(height: 3),
                    Text(label, style: Theme.of(context).textTheme.bodyMedium),
                    if (caption != null) ...[
                      const SizedBox(height: 8),
                      Text(caption!,
                          style: TextStyle(
                              color: accent,
                              fontWeight: FontWeight.w700,
                              fontSize: 12)),
                    ],
                  ]),
            ),
          ]),
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final lower = text.toLowerCase();
    final color = lower.contains('paid') ||
            lower.contains('resolved') ||
            lower.contains('verified') ||
            lower == 'in' ||
            lower.contains('signed') ||
            lower.contains('generated') ||
            lower.contains('enabled')
        ? success
        : lower.contains('overdue') ||
                lower.contains('high') ||
                lower.contains('declined') ||
                lower.contains('disabled')
            ? danger
            : lower.contains('progress') ||
                    lower.contains('inside') ||
                    lower.contains('medium') ||
                    lower.contains('partial')
                ? info
                : amber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: color.withValues(alpha: .16),
          borderRadius: BorderRadius.circular(20)),
      // Colors key off the English label above; the display is localized.
      child: Text(AppLocalizations.of(context).status(text),
          style: TextStyle(
              color: color, fontWeight: FontWeight.w700, fontSize: 11)),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title});
  final IconData icon;
  final String title;

  // Full width so the icon and message sit in the middle of the screen
  // rather than hugging the left edge.
  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 46, color: faint),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
          ]),
        ),
      );
}

Future<void> showAppSheet(BuildContext context, Widget child) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .9),
        padding: EdgeInsets.fromLTRB(
            20, 12, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
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
          decoration: BoxDecoration(
              color: hairline, borderRadius: BorderRadius.circular(4)),
        ),
      );
}

class FormLabel extends StatelessWidget {
  const FormLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 7, top: 12),
        child: Text(text,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
      );
}

/// "Ground floor" for floor 0, else "Floor N".
String floorLabel(AppLocalizations l, int floor) =>
    floor == 0 ? l.t('room.ground') : '${l.t('room.floor')} $floor';

/// Floor choice from the ground floor up to [maxFloor]. A room already
/// saved on a floor outside that range keeps it as an option.
class FloorPicker extends StatelessWidget {
  const FloorPicker({super.key, required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final floors = {for (var f = 0; f <= maxFloor; f++) f, value}.toList()
      ..sort();
    return DropdownButtonFormField<int>(
        isExpanded: true,
        initialValue: value,
        items: [
          for (final f in floors)
            DropdownMenuItem(value: f, child: Text(floorLabel(l, f)))
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        });
  }
}
