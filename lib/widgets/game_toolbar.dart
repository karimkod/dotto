import 'package:flutter/material.dart';

import '../models/grid_cell.dart';
import '../theme/app_theme.dart';
import 'bouncy_button.dart';
import 'game_grid.dart';

/// Horizontal row of selectable toolkit items, each a thick-bordered tile with
/// a glyph, label and remaining-count badge.
///
/// Tiles are plain (no Draggable) — the screen drives drag-and-drop manually
/// with pan gestures and uses [tileKeys] to know which tile a pan started on.
class GameToolbar extends StatelessWidget {
  const GameToolbar({
    super.key,
    required this.tools,
    required this.counts,
    required this.selected,
    required this.onSelect,
    required this.enabled,
    required this.tileKeys,
    this.draggingTool,
    this.onReset,
  });

  /// Distinct tools available in this level, in display order.
  final List<ToolType> tools;
  final Map<ToolType, int> counts;
  final ToolType? selected;
  final ValueChanged<ToolType> onSelect;

  /// False while the dot is running — selection is disabled.
  final bool enabled;

  /// One GlobalKey per tool, so the screen can resolve each tile's screen rect.
  final Map<ToolType, GlobalKey> tileKeys;

  /// The tool currently being dragged (its tile is dimmed), if any.
  final ToolType? draggingTool;

  /// Shows a Reset tile at the end of the row when non-null.
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final t in tools)
          _ToolTile(
            key: tileKeys[t],
            tool: t,
            count: counts[t] ?? 0,
            selected: selected == t,
            enabled: enabled && (counts[t] ?? 0) > 0,
            dragging: draggingTool == t,
            onTap: () => onSelect(t),
          ),
        if (onReset != null) _ResetTile(enabled: enabled, onTap: onReset!),
      ],
    );
  }
}

/// Reset tile — looks like a toolkit item but uses a muted red outline to read
/// as a distinct action rather than a placeable element.
class _ResetTile extends StatelessWidget {
  const _ResetTile({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  static const _red = Color(0xFFCF6B61);

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: BouncyButton(
        enabled: enabled,
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        rippleColor: _red,
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _red, width: 3),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.restart_alt_rounded, color: _red, size: 24),
              SizedBox(height: 2),
              Text(
                'RESET',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                  color: _red,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({
    super.key,
    required this.tool,
    required this.count,
    required this.selected,
    required this.enabled,
    required this.dragging,
    required this.onTap,
  });

  final ToolType tool;
  final int count;
  final bool selected;
  final bool enabled;
  final bool dragging;
  final VoidCallback onTap;

  bool get _isArrow => tool.direction != null;

  @override
  Widget build(BuildContext context) {
    final opacity = !enabled ? 0.4 : (dragging ? 0.3 : 1.0);
    return Opacity(
      opacity: opacity,
      child: BouncyButton(
        enabled: enabled,
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        rippleColor: AppColors.coral,
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    final isShield = tool.placedType == PlacedType.shield;
    final glyphColor = _isArrow
        ? const Color(0xFF1E88E5)
        : (isShield ? kShieldColor : AppColors.ink);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accent.withValues(alpha: 0.20)
                : AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppColors.coral : AppColors.ink,
              width: selected ? 3.5 : 3,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isShield)
                const ShieldGlyph(size: 26, color: kShieldColor)
              else
                Text(
                  tool.glyph,
                  style: TextStyle(
                    fontSize: 22,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    color: glyphColor,
                  ),
                ),
              const SizedBox(height: 2),
              Text(
                tool.label,
                style: const TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                  color: AppColors.textSoft,
                ),
              ),
            ],
          ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.ink,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.card, width: 2),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
