import 'package:flutter/material.dart';

import '../models/grid_cell.dart';
import '../theme/app_theme.dart';
import 'game_grid.dart';

/// Horizontal row of selectable toolkit items, each a thick-bordered tile with
/// a glyph, label and remaining-count badge.
class GameToolbar extends StatelessWidget {
  const GameToolbar({
    super.key,
    required this.tools,
    required this.counts,
    required this.selected,
    required this.onSelect,
    required this.enabled,
  });

  /// Distinct tools available in this level, in display order.
  final List<ToolType> tools;
  final Map<ToolType, int> counts;
  final ToolType? selected;
  final ValueChanged<ToolType> onSelect;

  /// False while the dot is running — selection is disabled.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final t in tools)
          _ToolTile(
            tool: t,
            count: counts[t] ?? 0,
            selected: selected == t,
            enabled: enabled && (counts[t] ?? 0) > 0,
            onTap: () => onSelect(t),
          ),
      ],
    );
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({
    required this.tool,
    required this.count,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final ToolType tool;
  final int count;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  bool get _isArrow => tool.direction != null;

  @override
  Widget build(BuildContext context) {
    final content = _buildContent();

    return Opacity(
      opacity: enabled ? 1 : 0.4,
      // Drag is the primary interaction; tap-to-select is the fallback.
      child: Draggable<ToolType>(
        data: tool,
        maxSimultaneousDrags: enabled ? 1 : 0,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: DragGhost(tool: tool),
        childWhenDragging: Opacity(opacity: 0.3, child: content),
        child: GestureDetector(
          onTap: enabled ? onTap : null,
          child: content,
        ),
      ),
    );
  }

  Widget _buildContent() {
    final glyphColor = _isArrow ? const Color(0xFF1E88E5) : AppColors.ink;

    return Stack(
      clipBehavior: Clip.none,
      children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: selected ? AppColors.accent.withValues(alpha: 0.20) : AppColors.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected ? AppColors.coral : AppColors.ink,
                  width: selected ? 3.5 : 3,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
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
