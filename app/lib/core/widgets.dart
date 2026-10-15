import 'package:flutter/material.dart';

import 'l10n.dart';
import 'supa.dart';

/// Loads data once, shows loading / error-with-retry, and supports pull-to-refresh.
class FutureView<T> extends StatefulWidget {
  const FutureView({super.key, required this.load, required this.builder});
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;

  @override
  State<FutureView<T>> createState() => _FutureViewState<T>();
}

class _FutureViewState<T> extends State<FutureView<T>> {
  late Future<T> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.load();
  }

  Future<void> _reload() async {
    final f = widget.load();
    setState(() => _future = f);
    try {
      await f;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const LoadingView();
        if (snap.hasError) {
          return ErrorView(message: friendlyError(snap.error!), onRetry: _reload, details: errorDetails(snap.error!));
        }
        return widget.builder(context, snap.data as T, _reload);
      },
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: Padding(
        padding: EdgeInsets.all(32),
        child: CircularProgressIndicator(),
      ));
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry, this.details});
  final String message;
  final VoidCallback? onRetry;
  /// Technical detail shown small under the message, so a screenshot tells us the real cause.
  final String? details;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.wifi_off_rounded, size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
            if (details != null && details!.isNotEmpty) ...[
              const SizedBox(height: 8),
              SelectableText(details!.length > 300 ? details!.substring(0, 300) : details!,
                  textAlign: TextAlign.center, textDirection: TextDirection.ltr,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline)),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(tr('إعادة المحاولة', 'Retry')),
              ),
            ],
          ]),
        ),
      );
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.icon, required this.title, this.subtitle, this.action});
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(radius: 36, backgroundColor: cs.primaryContainer,
              child: Icon(icon, size: 36, color: cs.onPrimaryContainer)),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle!, textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      ),
    );
  }
}

/// Pull-to-refresh list that still scrolls when it holds a single empty-state child.
class RefreshList extends StatelessWidget {
  const RefreshList({super.key, required this.onRefresh, required this.children, this.padding});
  final Future<void> Function() onRefresh;
  final List<Widget> children;
  final EdgeInsets? padding;
  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: padding ?? const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: children,
        ),
      );
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5)),
      );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      );
}

class InfoBanner extends StatelessWidget {
  const InfoBanner({super.key, required this.icon, required this.text, this.color});
  final IconData icon;
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.withValues(alpha: 0.3))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: c),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(height: 1.5))),
      ]),
    );
  }
}

void showMessage(BuildContext context, String text, {bool error = false}) {
  final cs = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? cs.error : null,
    ));
}

Future<bool> confirmDialog(BuildContext context,
    {required String title, required String body, required String confirm, bool danger = false}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body, style: const TextStyle(height: 1.5)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('إلغاء', 'Cancel'))),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error,
              minimumSize: const Size(88, 44)) : FilledButton.styleFrom(minimumSize: const Size(88, 44)),
          onPressed: () => Navigator.pop(c, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return res ?? false;
}

/// Runs an async action with a blocking spinner and friendly error handling.
/// Returns true on success.
Future<bool> runBusy(BuildContext context, Future<void> Function() action, {String? success}) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(canPop: false, child: Center(child: CircularProgressIndicator())),
  );
  try {
    await action();
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      if (success != null) showMessage(context, success);
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      showMessage(context, friendlyError(e), error: true);
    }
    return false;
  }
}

String? requiredField(String? v) =>
    (v == null || v.trim().isEmpty) ? tr('هذا الحقل مطلوب', 'This field is required') : null;
