import 'package:flutter/material.dart';

import '../models.dart';
import 'appliance_art.dart';

/// A saved command is deliberately distinct from physical relay feedback.
class RelayTile extends StatelessWidget {
  const RelayTile({
    super.key,
    required this.relay,
    required this.online,
    required this.sending,
    required this.onChanged,
    this.pendingState,
    this.compact = false,
    this.onEdit,
  });

  final RelayChannel relay;
  final bool online;
  final bool sending;
  final bool? pendingState;
  final ValueChanged<bool>? onChanged;
  final bool compact;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final on = pendingState ?? (relay.lastState == true);
    final state = relay.uncertain
        ? 'Uncertain'
        : relay.lastState == null
        ? 'Unknown'
        : relay.lastState == true
        ? 'On'
        : 'Off';
    final active = on && (pendingState != null || !relay.uncertain);
    final status = sending
        ? 'Setting ${on ? 'On' : 'Off'}…'
        : 'Last set $state';
    final artwork = SizedBox.square(
      dimension: compact ? 36 : 102,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: dark ? const Color(0xFFE5EAE0) : Colors.transparent,
          borderRadius: BorderRadius.circular(compact ? 9 : 17),
        ),
        child: Padding(
          padding: EdgeInsets.all(dark ? (compact ? 2 : 5) : 0),
          child: ApplianceArt(
            preset: relay.preset,
            on: on,
            customImagePath: relay.customImagePath,
            size: compact ? 36 : 102,
          ),
        ),
      ),
    );

    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      padding: EdgeInsets.all(compact ? 10 : 16),
      decoration: BoxDecoration(
        color: active
            ? colors.primaryContainer.withValues(alpha: .45)
            : colors.surface,
        borderRadius: BorderRadius.circular(compact ? 17 : 22),
        border: Border.all(
          color: active
              ? colors.primary.withValues(alpha: .08)
              : colors.outlineVariant.withValues(alpha: .55),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (compact)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(child: artwork),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        relay.name,
                        style: text.labelLarge?.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Relay ${relay.channel}',
                        style: text.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          else ...[
            Stack(
              clipBehavior: Clip.none,
              children: [
                Align(
                  alignment: Alignment.center,
                  child: ExcludeSemantics(child: artwork),
                ),
                if (onEdit != null)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton(
                      onPressed: onEdit,
                      tooltip: 'Edit ${relay.name}',
                      icon: const Icon(Icons.edit_outlined, size: 18),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              relay.name,
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              'Relay ${relay.channel}',
              style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
          SizedBox(height: compact ? 4 : 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  status,
                  style: text.bodySmall?.copyWith(
                    color: relay.uncertain && !sending
                        ? colors.error
                        : active
                        ? colors.primary
                        : colors.onSurfaceVariant,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              Semantics(
                label:
                    '${relay.name}, relay ${relay.channel}, $status${online ? '' : ', device offline'}',
                child: Switch(
                  value: on,
                  onChanged: online && !sending ? onChanged : null,
                  activeTrackColor: colors.primary,
                  activeThumbColor: colors.onPrimary,
                  // Disabled switches still communicate the saved value.
                  trackColor: WidgetStateProperty.resolveWith((states) {
                    if (sending && on) return colors.primary;
                    if (states.contains(WidgetState.disabled) && on) {
                      return colors.primary.withValues(alpha: .45);
                    }
                    return null;
                  }),
                  thumbColor: WidgetStateProperty.resolveWith((states) {
                    if (sending && on) return colors.onPrimary;
                    return null;
                  }),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Intrinsic rows keep names readable at large text sizes without clipping.
class RelayGrid extends StatelessWidget {
  const RelayGrid({super.key, required this.children, this.gap = 10});
  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
      final columns = constraints.maxWidth < 300 || scale > 1.35 ? 1 : 2;
      final rows = <Widget>[];
      for (var index = 0; index < children.length; index += columns) {
        if (rows.isNotEmpty) rows.add(SizedBox(height: gap));
        if (columns == 1) {
          rows.add(children[index]);
        } else {
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: children[index]),
                  SizedBox(width: gap),
                  Expanded(
                    child: index + 1 < children.length
                        ? children[index + 1]
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          );
        }
      }
      return Column(children: rows);
    },
  );
}
