import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'inline_cell_layout.dart';

const tablePageSizes = <int>[10, 25, 50];

class TablePageWindow {
  const TablePageWindow(this.page, this.pageCount, this.start, this.end);

  final int page;
  final int pageCount;
  final int start;
  final int end;
}

TablePageWindow tablePageWindow(int total, int requestedPage, int pageSize) {
  final size = math.max(1, pageSize);
  final pageCount = math.max(1, (total + size - 1) ~/ size);
  final page = requestedPage.clamp(0, pageCount - 1);
  final start = page * size;
  return TablePageWindow(page, pageCount, start, math.min(total, start + size));
}

BoxDecoration tablePanelDecoration(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return BoxDecoration(
    color: scheme.surface,
    border: Border.all(color: scheme.outlineVariant.withValues(alpha: .72)),
    borderRadius: BorderRadius.circular(16),
  );
}

class TableRecordToolbar extends StatelessWidget {
  const TableRecordToolbar({
    super.key,
    required this.searchField,
    required this.fieldFilter,
    required this.exportButton,
    required this.toolsButton,
    required this.addButton,
    this.valueFilter,
  });

  final Widget searchField;
  final Widget fieldFilter;
  final Widget exportButton;
  final Widget toolsButton;
  final Widget addButton;
  final Widget? valueFilter;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const gap = 8.0;
      const fieldWidth = 170.0;
      const valueWidth = 170.0;
      const exportWidth = 112.0;
      const toolsWidth = 48.0;
      const addWidth = 160.0;
      final actionsWidth = exportWidth + toolsWidth + addWidth + gap * 2;
      final minFilterWidth =
          200 +
          fieldWidth +
          gap +
          24 +
          (valueFilter == null ? 0 : valueWidth + gap);
      final singleLine =
          constraints.maxWidth >= minFilterWidth + actionsWidth + 12;

      Widget filters({required bool compact}) => Container(
        decoration: tablePanelDecoration(context),
        padding: const EdgeInsets.all(12),
        child:
            compact
                ? LayoutBuilder(
                  builder:
                      (context, inner) => Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: math.min(280, inner.maxWidth),
                            child: searchField,
                          ),
                          SizedBox(
                            width: math.min(fieldWidth, inner.maxWidth),
                            child: fieldFilter,
                          ),
                          if (valueFilter != null)
                            SizedBox(
                              width: math.min(valueWidth, inner.maxWidth),
                              child: valueFilter,
                            ),
                        ],
                      ),
                )
                : Row(
                  children: [
                    Expanded(child: searchField),
                    const SizedBox(width: gap),
                    SizedBox(width: fieldWidth, child: fieldFilter),
                    if (valueFilter != null) ...[
                      const SizedBox(width: gap),
                      SizedBox(width: valueWidth, child: valueFilter),
                    ],
                  ],
                ),
      );

      final actions = Wrap(
        spacing: gap,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(width: exportWidth, child: exportButton),
          SizedBox(width: toolsWidth, child: toolsButton),
          SizedBox(width: addWidth, child: addButton),
        ],
      );

      if (!singleLine) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            filters(compact: true),
            const SizedBox(height: gap),
            actions,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: filters(compact: false)),
          const SizedBox(width: 12),
          actions,
        ],
      );
    },
  );
}

Color tableHeaderColor(BuildContext context) =>
    Theme.of(context).colorScheme.surfaceContainerLow;

TextStyle tableHeaderStyle(BuildContext context) => TextStyle(
  color: Theme.of(context).colorScheme.onSurfaceVariant,
  fontSize: 10,
  fontWeight: FontWeight.w800,
  letterSpacing: .8,
);

class TableValueDisplay extends StatelessWidget {
  const TableValueDisplay({
    super.key,
    required this.fieldKey,
    required this.value,
    this.style,
  });

  final String fieldKey;
  final String value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final key = fieldKey.toLowerCase();
    final normalized = value.toLowerCase();
    final isStatus = key.contains('status') && value.isNotEmpty && value != '—';
    final isAirportCode =
        {'origin', 'destination', 'fromairport', 'toairport'}.contains(key) &&
        RegExp(r'^[A-Z]{3,4}$').hasMatch(value);
    if (!isStatus && !isAirportCode) {
      return Text(
        value,
        maxLines: inlineCellMaxLines,
        softWrap: true,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final accent =
        isAirportCode
            ? scheme.primary
            : {
              'paid',
              'confirmed',
              'completed',
              'active',
              'approved',
              'resolved',
              'issued',
            }.any(normalized.contains)
            ? const Color(0xff218364)
            : {
              'cancelled',
              'failed',
              'rejected',
              'overdue',
            }.any(normalized.contains)
            ? const Color(0xffbd4b54)
            : const Color(0xffad7620);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: .09),
          border: Border.all(color: accent.withValues(alpha: .18)),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: (style ?? const TextStyle()).copyWith(
            color: accent,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class TablePagination extends StatelessWidget {
  const TablePagination({
    super.key,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.onPageChanged,
    required this.onPageSizeChanged,
  });

  final int total;
  final int page;
  final int pageSize;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onPageSizeChanged;

  @override
  Widget build(BuildContext context) {
    final window = tablePageWindow(total, page, pageSize);
    final scheme = Theme.of(context).colorScheme;
    final compact = MediaQuery.sizeOf(context).width < 720;
    final pages =
        <int>{
            0,
            window.pageCount - 1,
            window.page - 1,
            window.page,
            window.page + 1,
          }.where((number) => number >= 0 && number < window.pageCount).toList()
          ..sort();
    Widget pageButton(int number) => SizedBox(
      width: 30,
      height: 30,
      child: TextButton(
        onPressed: number == window.page ? null : () => onPageChanged(number),
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          backgroundColor:
              number == window.page ? scheme.primary : Colors.transparent,
          foregroundColor:
              number == window.page ? scheme.onPrimary : scheme.onSurface,
          disabledForegroundColor:
              number == window.page ? scheme.onPrimary : scheme.onSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        ),
        child: Text('${number + 1}', style: const TextStyle(fontSize: 12)),
      ),
    );
    return Container(
      key: const ValueKey('table-pagination'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(
                total == 0
                    ? 'Showing 0 of 0 entries'
                    : 'Showing ${window.start + 1} to ${window.end} of $total entries',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
              Text(
                'Rows per page:',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
              DropdownButton<int>(
                value: pageSize,
                isDense: true,
                underline: const SizedBox.shrink(),
                items: [
                  for (final size in tablePageSizes)
                    DropdownMenuItem(value: size, child: Text('$size')),
                ],
                onChanged: (size) {
                  if (size != null) onPageSizeChanged(size);
                },
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Previous page',
                onPressed:
                    window.page == 0
                        ? null
                        : () => onPageChanged(window.page - 1),
                icon: const Icon(Icons.chevron_left, size: 18),
                visualDensity: VisualDensity.compact,
              ),
              if (compact)
                pageButton(window.page)
              else
                for (var i = 0; i < pages.length; i++) ...[
                  if (i > 0 && pages[i] - pages[i - 1] > 1)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 3),
                      child: Text('…'),
                    ),
                  pageButton(pages[i]),
                ],
              IconButton(
                tooltip: 'Next page',
                onPressed:
                    window.page >= window.pageCount - 1
                        ? null
                        : () => onPageChanged(window.page + 1),
                icon: const Icon(Icons.chevron_right, size: 18),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
