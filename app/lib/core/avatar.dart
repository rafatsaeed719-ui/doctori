import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'l10n.dart';
import 'supa.dart';
import 'widgets.dart';

/// Round profile photo with the first letter of the name as fallback.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, this.url, this.name, this.radius = 22, this.ring});
  final String? url;
  final String? name;
  final double radius;
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final initial = (name == null || name!.trim().isEmpty) ? '?' : name!.trim().characters.first;
    final hasUrl = url != null && url!.isNotEmpty;
    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: cs.primaryContainer,
      foregroundImage: hasUrl ? NetworkImage(url!) : null,
      onForegroundImageError: hasUrl ? (_, __) {} : null,
      child: Text(initial,
          style: TextStyle(fontSize: radius * 0.85, fontWeight: FontWeight.w800, color: cs.onPrimaryContainer)),
    );
    if (ring == null) return avatar;
    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(shape: BoxShape.circle, color: ring,
          boxShadow: [BoxShadow(color: ring!.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4))]),
      child: avatar,
    );
  }
}

/// The signed-in user's avatar + name, live-updating when the photo changes.
class MeHeader extends StatelessWidget {
  const MeHeader({super.key, this.prefix = '', this.radius = 18});
  final String prefix;
  final double radius;
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, dynamic>>(
      valueListenable: AppState.ctx,
      builder: (context, ctx, _) => Row(mainAxisSize: MainAxisSize.min, children: [
        UserAvatar(url: ctx['avatar_url'] as String?, name: ctx['full_name'] as String?, radius: radius),
        const SizedBox(width: 10),
        Flexible(
          child: Text('$prefix${ctx['full_name'] ?? ''}',
              overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }
}

/// Shrinks a photo so its longest side is [maxSide] px and re-encodes it as PNG.
Future<Uint8List> _shrinkToPng(Uint8List bytes, {int maxSide = 512}) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final desc = await ui.ImageDescriptor.encoded(buffer);
  final w = desc.width, h = desc.height;
  final scale = (w > h ? w : h) > maxSide ? maxSide / (w > h ? w : h) : 1.0;
  final codec = await desc.instantiateCodec(
    targetWidth: (w * scale).round().clamp(1, maxSide).toInt(),
    targetHeight: (h * scale).round().clamp(1, maxSide).toInt(),
  );
  final frame = await codec.getNextFrame();
  final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// Lets the user pick, upload, or remove their profile photo. Returns true when it changed.
Future<bool> changeMyAvatar(BuildContext context) async {
  final hasPhoto = ((AppState.context['avatar_url'] as String?) ?? '').isNotEmpty;
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.photo_library_outlined),
          title: Text(tr('اختيار صورة من المعرض', 'Choose a photo')),
          onTap: () => Navigator.pop(c, 'pick'),
        ),
        if (hasPhoto)
          ListTile(
            leading: Icon(Icons.delete_outline, color: Theme.of(c).colorScheme.error),
            title: Text(tr('إزالة الصورة', 'Remove photo'), style: TextStyle(color: Theme.of(c).colorScheme.error)),
            onTap: () => Navigator.pop(c, 'remove'),
          ),
      ]),
    ),
  );
  if (action == null || !context.mounted) return false;

  if (action == 'remove') {
    return runBusy(context, () async {
      await supa.from('profiles').update({'avatar_url': null}).eq('id', myId);
      AppState.updateContext({'avatar_url': null});
    }, success: tr('تمت إزالة الصورة', 'Photo removed'));
  }

  List<PlatformFile> picked;
  try {
    picked = await FilePicker.pickFiles(type: FileType.image);
  } catch (e) {
    if (context.mounted) showMessage(context, friendlyError(e), error: true);
    return false;
  }
  if (picked.isEmpty || !context.mounted) return false;

  return runBusy(context, () async {
    final raw = await picked.first.readAsBytes();
    final png = await _shrinkToPng(raw);
    final path = '$myId/avatar_${DateTime.now().millisecondsSinceEpoch}.png';
    await supa.storage.from('avatars').uploadBinary(path, png,
        fileOptions: FileOptions(contentType: 'image/png', upsert: true));
    final url = supa.storage.from('avatars').getPublicUrl(path);
    await supa.from('profiles').update({'avatar_url': url}).eq('id', myId);
    AppState.updateContext({'avatar_url': url});
  }, success: tr('تم تحديث صورتك', 'Photo updated'));
}
