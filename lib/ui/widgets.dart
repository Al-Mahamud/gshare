import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';

import '../core/identity.dart';
import '../core/models.dart';
import '../core/util.dart';
import '../services/app_services.dart';
import '../services/receive_manager.dart';

IconData platformIcon(DevicePlatform p) => switch (p) {
      DevicePlatform.android => Icons.phone_android,
      DevicePlatform.ios => Icons.phone_iphone,
      DevicePlatform.windows => Icons.desktop_windows_outlined,
      DevicePlatform.macos => Icons.laptop_mac,
      DevicePlatform.linux => Icons.computer,
      DevicePlatform.unknown => Icons.devices_other,
    };

IconData iconForItem(TransferItem item) {
  if (item.kind == ItemKind.text) return Icons.notes;
  if (isImageMime(item.mime)) return Icons.image_outlined;
  if (isVideoMime(item.mime)) return Icons.movie_outlined;
  if (item.mime.startsWith('audio/')) return Icons.audiotrack_outlined;
  if (item.mime == 'application/pdf') return Icons.picture_as_pdf_outlined;
  return Icons.insert_drive_file_outlined;
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});

  final TransferStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (status) {
      TransferStatus.done => (scheme.primaryContainer, scheme.onPrimaryContainer),
      TransferStatus.failed || TransferStatus.declined => (scheme.errorContainer, scheme.onErrorContainer),
      TransferStatus.cancelled => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
      _ => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(status.label, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class TransferTile extends StatelessWidget {
  const TransferTile({super.key, required this.session});

  final TransferSession session;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final s = session;
        final theme = Theme.of(context);
        final services = AppServices.I;
        final sending = s.direction == Direction.send;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(sending ? Icons.north_east : Icons.south_west, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${sending ? 'To' : 'From'} ${s.peer.name}',
                        style: theme.textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    StatusChip(status: s.status),
                  ],
                ),
                if (sending && s.status == TransferStatus.waitingAccept)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Waiting for ${s.peer.name} to accept. Both screens should show code '
                      '${verificationCode(services.identity.fingerprint, s.peer.id)}.',
                    ),
                  ),
                if (!sending && !s.verified)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber, size: 16, color: theme.colorScheme.error),
                        const SizedBox(width: 6),
                        const Expanded(child: Text('Sender identity could not be verified')),
                      ],
                    ),
                  ),
                if (s.status == TransferStatus.inProgress) ...[
                  const SizedBox(height: 10),
                  LinearProgressIndicator(value: s.progress),
                  const SizedBox(height: 4),
                  Text('${formatBytes(s.doneBytes)} of ${formatBytes(s.totalBytes)}',
                      style: theme.textTheme.bodySmall),
                ],
                if (s.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(s.error!, style: TextStyle(color: theme.colorScheme.error)),
                  ),
                const SizedBox(height: 6),
                for (final it in s.items.take(6)) _ItemRow(item: it, direction: s.direction),
                if (s.items.length > 6)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('+ ${s.items.length - 6} more', style: theme.textTheme.bodySmall),
                  ),
                if (s.isActive)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => sending ? services.sender.cancel(s) : unawaited(services.receiver.cancel(s)),
                      child: const Text('Cancel'),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.direction});

  final ItemProgress item;
  final Direction direction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final it = item.item;
    final isText = it.kind == ItemKind.text;
    final received = direction == Direction.receive;
    final path = item.savedPath;

    final detail = [
      if (!isText) formatBytes(it.size),
      if (item.note != null) item.note!,
      if (item.error != null && item.status != TransferStatus.done) item.error!,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(iconForItem(it), size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isText)
                  SelectableText(it.text ?? '', maxLines: 4)
                else
                  Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (detail.isNotEmpty) Text(detail, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          if (item.status == TransferStatus.done && isText)
            IconButton(
              tooltip: 'Copy',
              icon: const Icon(Icons.copy, size: 18),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: it.text ?? ''));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
                }
              },
            ),
          if (received && item.status == TransferStatus.done && path != null)
            IconButton(
              tooltip: 'Open',
              icon: const Icon(Icons.open_in_new, size: 18),
              onPressed: () => unawaited(OpenFilex.open(path)),
            ),
          if (item.status == TransferStatus.done && !isText && path == null)
            Icon(Icons.check, size: 18, color: theme.colorScheme.primary),
        ],
      ),
    );
  }
}

/// Accept/decline dialog for an incoming transfer. Closes itself if the request times out.
class IncomingRequestDialog extends StatefulWidget {
  const IncomingRequestDialog({super.key, required this.request});

  final IncomingRequest request;

  @override
  State<IncomingRequestDialog> createState() => _IncomingRequestDialogState();
}

class _IncomingRequestDialogState extends State<IncomingRequestDialog> {
  bool _trust = false;
  bool _answered = false;

  @override
  void initState() {
    super.initState();
    widget.request.result.then((_) {
      if (!_answered && mounted) Navigator.of(context).pop();
    });
  }

  void _answer(bool accept) {
    _answered = true;
    widget.request.respond(accept, trust: _trust);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.request.session;
    final peer = s.peer;
    final trusted = AppServices.I.settings.isTrusted(peer.id);
    return AlertDialog(
      title: Text('Receive from ${peer.name}?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(platformIcon(peer.platform), size: 18),
                const SizedBox(width: 6),
                Text('${peer.platform.label} · ${peer.ip ?? ''}'),
              ],
            ),
            const SizedBox(height: 16),
            Text('Verification code', style: theme.textTheme.labelMedium),
            Text(
              widget.request.code,
              style: theme.textTheme.headlineMedium?.copyWith(letterSpacing: 4),
            ),
            Text('Check that the sender shows the same code.', style: theme.textTheme.bodySmall),
            if (!s.verified) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.warning_amber, color: theme.colorScheme.error, size: 18),
                  const SizedBox(width: 6),
                  const Expanded(child: Text('Sender identity could not be verified. Accept only if you expect this.')),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Text('${s.items.length} item(s) · ${formatBytes(s.totalBytes)}', style: theme.textTheme.titleSmall),
            for (final it in s.items.take(5))
              Text(
                '• ${it.item.kind == ItemKind.text ? 'Text message' : '${it.item.name} (${formatBytes(it.item.size)})'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            if (s.items.length > 5) Text('• and ${s.items.length - 5} more'),
            if (s.verified && !trusted)
              CheckboxListTile(
                value: _trust,
                onChanged: (v) => setState(() => _trust = v ?? false),
                title: const Text('Trust this device'),
                subtitle: const Text('Accept from it automatically next time'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => _answer(false), child: const Text('Decline')),
        FilledButton(onPressed: () => _answer(true), child: const Text('Accept')),
      ],
    );
  }
}
