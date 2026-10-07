import 'dart:convert';
import 'dart:math' as math;

import 'package:csv/csv.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'api.dart';
import 'table_model.dart';
import 'table_repository.dart';

class TableScreen extends StatefulWidget {
  const TableScreen({
    super.key,
    required this.api,
    required this.grocery,
    required this.message,
    required this.onUpdated,
  });

  final ApiClient api;
  final bool grocery;
  final void Function(String) message;
  final VoidCallback onUpdated;

  @override
  State<TableScreen> createState() => TableScreenState();
}

class TableScreenState extends State<TableScreen> {
  late TableKind kind;
  late TableRepository repository;
  final searchController = TextEditingController();
  final filterController = TextEditingController();
  final horizontalController = ScrollController();
  final verticalController = ScrollController();
  List<SpreadsheetRow> rows = [];
  List<SpreadsheetRow> visibleRows = [];
  List<TableColumnDef> customColumns = [];
  SpreadsheetRow? selectedRow;
  String? selectedKey;
  String? sortKey;
  String? filterKey;
  bool ascending = true;
  bool loading = true;
  bool saving = false;
  bool showFilter = false;
  bool initialized = false;
  String? error;

  List<TableColumnDef> get columns => [...kind.baseColumns, ...customColumns];
  bool get hasPendingChanges =>
      rows.any((row) => row.dirty || (row.isNew && row.draftId == null));

  @override
  void initState() {
    super.initState();
    kind = widget.grocery ? TableKind.products : TableKind.bookings;
    repository = TableRepository(widget.api, kind);
    searchController.addListener(_rebuildVisible);
    filterController.addListener(_rebuildVisible);
    _load();
  }

  @override
  void didUpdateWidget(covariant TableScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.grocery != widget.grocery || oldWidget.api != widget.api) {
      kind = widget.grocery ? TableKind.products : TableKind.bookings;
      repository = TableRepository(widget.api, kind);
      selectedRow = null;
      selectedKey = null;
      filterKey = null;
      searchController.clear();
      filterController.clear();
      _load();
    }
  }

  @override
  void dispose() {
    searchController.removeListener(_rebuildVisible);
    filterController.removeListener(_rebuildVisible);
    searchController.dispose();
    filterController.dispose();
    horizontalController.dispose();
    verticalController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final snapshot = await repository.load();
      if (!mounted) return;
      setState(() {
        rows = snapshot.rows;
        customColumns = snapshot.customColumns;
        initialized = snapshot.initialized;
        selectedRow = null;
        selectedKey = null;
        loading = false;
      });
      _rebuildVisible();
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        error = exception.toString();
        loading = false;
      });
    }
  }

  Future<void> _createSetup(int rowCount, int extraColumns) async {
    await repository.createSetup(rows: rowCount, extraColumns: extraColumns);
    if (!mounted) return;
    await _load();
    if (mounted) widget.message('Table created. You can now edit cells.');
  }

  void _rebuildVisible() {
    if (!mounted) return;
    final search = searchController.text.trim().toLowerCase();
    final filter = filterController.text.trim().toLowerCase();
    final keys = columns.map((column) => column.key).toList();
    final result =
        rows.where((row) {
          if (search.isNotEmpty &&
              !keys.any(
                (key) => (row.values[key] ?? '')
                    .toString()
                    .toLowerCase()
                    .contains(search),
              )) {
            return false;
          }
          if (filter.isNotEmpty &&
              filterKey != null &&
              !(row.values[filterKey] ?? '').toString().toLowerCase().contains(
                filter,
              )) {
            return false;
          }
          return true;
        }).toList();
    if (sortKey != null) {
      final key = sortKey!;
      result.sort((a, b) {
        final left = a.values[key];
        final right = b.values[key];
        final leftNumber = num.tryParse('${left ?? ''}');
        final rightNumber = num.tryParse('${right ?? ''}');
        final comparison =
            leftNumber != null && rightNumber != null
                ? leftNumber.compareTo(rightNumber)
                : '${left ?? ''}'.toLowerCase().compareTo(
                  '${right ?? ''}'.toLowerCase(),
                );
        return ascending ? comparison : -comparison;
      });
    }
    setState(() => visibleRows = result);
  }

  void _sort(TableColumnDef column) {
    ascending = sortKey == column.key ? !ascending : true;
    sortKey = column.key;
    _rebuildVisible();
  }

  void _select(SpreadsheetRow row, TableColumnDef column) {
    if (selectedRow == row && selectedKey == column.key) {
      _editCell(row, column);
      return;
    }
    setState(() {
      selectedRow = row;
      selectedKey = column.key;
    });
  }

  Future<void> _editCell(SpreadsheetRow row, TableColumnDef column) async {
    if (!column.editable) return;
    final original = row.values[column.key]?.toString() ?? '';
    final result = await showDialog<String>(
      context: context,
      builder:
          (context) => _CellEditorDialog(column: column, initial: original),
    );
    if (!mounted || result == null) return;
    if (column.required && result.isEmpty) {
      widget.message('${column.label} is required');
      return;
    }
    if (column.type == TableValueType.number &&
        result.isNotEmpty &&
        !isNonNegativeNumber(result)) {
      widget.message('${column.label} must be a non-negative number');
      return;
    }
    if (column.type == TableValueType.date &&
        result.isNotEmpty &&
        DateTime.tryParse(result) == null) {
      widget.message('Use a valid date, for example 2026-10-03');
      return;
    }
    setState(() => row.setValue(column.key, result));
    _rebuildVisible();
  }

  void _addRow() {
    final defaults =
        kind == TableKind.bookings
            ? <String, dynamic>{
              'status': 'On hold',
              'paymentStatus': 'Pending',
              'total': 0,
              'cost': 0,
            }
            : <String, dynamic>{
              'status': 'Active',
              'stock': 0,
              'cost': 0,
              'price': 0,
              'unit': 'piece',
            };
    final row = SpreadsheetRow(defaults, isNew: true);
    setState(() {
      rows.insert(0, row);
      selectedRow = row;
      selectedKey = columns.firstWhere((column) => column.editable).key;
    });
    _rebuildVisible();
    if (verticalController.hasClients) verticalController.jumpTo(0);
  }

  void _duplicateRow() {
    final source = selectedRow;
    if (source == null) return;
    final values = <String, dynamic>{};
    for (final column in columns.where((column) => column.editable)) {
      values[column.key] = source.values[column.key];
    }
    if (kind == TableKind.bookings) {
      values['reference'] = '';
      values['pnr'] = '';
      values['paymentStatus'] = 'Pending';
      values['status'] = 'On hold';
    } else {
      values['sku'] = '';
      values['barcode'] = '';
      values['stock'] = 0;
    }
    final duplicate = SpreadsheetRow(values, isNew: true);
    setState(() {
      rows.insert(0, duplicate);
      selectedRow = duplicate;
      selectedKey = kind == TableKind.bookings ? 'reference' : 'barcode';
    });
    _rebuildVisible();
    if (verticalController.hasClients) verticalController.jumpTo(0);
  }

  Future<void> _deleteRow() async {
    final row = selectedRow;
    if (row == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete selected row?'),
            content: Text(
              row.isNew
                  ? 'This unsaved row will be discarded.'
                  : 'This removes the record from the workspace. Linked or transacted records are protected.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await repository.deleteRow(row);
      if (!mounted) return;
      setState(() {
        rows.remove(row);
        selectedRow = null;
        selectedKey = null;
      });
      _rebuildVisible();
      widget.onUpdated();
      widget.message('Row deleted');
    } catch (exception) {
      widget.message(exception.toString());
    }
  }

  Future<void> _save() async {
    if (saving) return;
    final pending =
        rows
            .where((row) => row.dirty || (row.isNew && row.draftId == null))
            .toList();
    if (pending.isEmpty) {
      widget.message('No changes to save');
      return;
    }
    for (final row in pending) {
      final validation = validateSpreadsheetRow(row, columns);
      if (validation != null && !row.isNew) {
        setState(() => selectedRow = row);
        widget.message(validation);
        return;
      }
    }
    setState(() => saving = true);
    var saved = 0;
    try {
      for (final row in pending) {
        final updated = await repository.saveRow(row, columns);
        row.values
          ..clear()
          ..addAll(updated.values);
        row.isNew = updated.isNew;
        row.draftId = updated.draftId;
        row.dirty = false;
        row.changedKeys.clear();
        saved++;
      }
      if (!mounted) return;
      _rebuildVisible();
      widget.onUpdated();
      widget.message('$saved row${saved == 1 ? '' : 's'} saved');
    } catch (exception) {
      if (mounted) {
        widget.message('$saved saved; remaining changes kept. $exception');
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<String?> _askText(String title, {String initial = ''}) async {
    return showDialog<String>(
      context: context,
      builder: (context) => _ColumnNameDialog(title: title, initial: initial),
    );
  }

  Future<void> _addColumn() async {
    final label = await _askText('Add column');
    if (label == null || label.isEmpty || !mounted) return;
    if (columns.any(
      (column) => column.label.toLowerCase() == label.toLowerCase(),
    )) {
      widget.message('Column already exists');
      return;
    }
    try {
      final column = await repository.addColumn(label);
      if (!mounted) return;
      setState(() => customColumns.add(column));
      widget.message('Column added');
    } catch (exception) {
      widget.message(exception.toString());
    }
  }

  Future<void> _renameColumn(TableColumnDef column) async {
    if (!column.custom) return;
    final label = await _askText('Rename column', initial: column.label);
    if (label == null || label.isEmpty || !mounted || label == column.label) {
      return;
    }
    try {
      await repository.renameColumn(column, label);
      if (!mounted) return;
      setState(() {
        final index = customColumns.indexOf(column);
        customColumns[index] = TableColumnDef(
          column.key,
          label,
          width: column.width,
          custom: true,
        );
      });
      widget.message('Column renamed');
    } catch (exception) {
      widget.message(exception.toString());
    }
  }

  Future<void> _copyCell() async {
    final row = selectedRow;
    final key = selectedKey;
    if (row == null || key == null) return;
    await Clipboard.setData(ClipboardData(text: '${row.values[key] ?? ''}'));
    widget.message('Cell copied');
  }

  Future<void> _pasteCell() async {
    final row = selectedRow;
    final column = columns.where((item) => item.key == selectedKey).firstOrNull;
    if (row == null || column == null || !column.editable) return;
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    final value = clipboard?.text?.trim();
    if (value == null) return;
    if (column.type == TableValueType.number &&
        value.isNotEmpty &&
        !isNonNegativeNumber(value)) {
      widget.message('Clipboard is not a non-negative number');
      return;
    }
    if (column.type == TableValueType.choice &&
        !column.choices.contains(value)) {
      widget.message('Clipboard value is not an allowed choice');
      return;
    }
    if (column.required && value.isEmpty) {
      widget.message('${column.label} is required');
      return;
    }
    setState(() => row.setValue(column.key, value));
    _rebuildVisible();
  }

  Future<void> _importCsv() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'CSV',
            extensions: ['csv'],
            mimeTypes: ['text/csv'],
            uniformTypeIdentifiers: ['public.comma-separated-values-text'],
          ),
        ],
      );
      if (file == null || !mounted) return;
      final raw = await file.readAsString();
      final parsed = const CsvToListConverter(
        shouldParseNumbers: false,
      ).convert(raw.replaceFirst('\uFEFF', ''));
      if (parsed.isEmpty) {
        widget.message('CSV file is empty');
        return;
      }
      final header =
          parsed.first
              .map((value) => value.toString().trim().toLowerCase())
              .toList();
      final mapped =
          header.map((value) {
            for (final column in columns.where((column) => column.editable)) {
              if (column.key.toLowerCase() == value ||
                  column.label.toLowerCase() == value) {
                return column;
              }
            }
            return null;
          }).toList();
      if (mapped.every((column) => column == null)) {
        widget.message('CSV headers do not match table columns');
        return;
      }
      if (parsed.length > 50001) {
        widget.message('Import up to 50,000 rows at a time');
        return;
      }
      final imported = <SpreadsheetRow>[];
      for (final cells in parsed.skip(1)) {
        if (cells.every((cell) => cell.toString().trim().isEmpty)) continue;
        final values = <String, dynamic>{};
        for (var index = 0; index < mapped.length; index++) {
          final column = mapped[index];
          if (column != null && index < cells.length) {
            values[column.key] = cells[index].toString();
          }
        }
        imported.add(SpreadsheetRow(values, isNew: true));
      }
      if (!mounted) return;
      setState(() => rows.insertAll(0, imported));
      _rebuildVisible();
      widget.message(
        '${imported.length} rows imported as drafts. Review and Save.',
      );
    } catch (exception) {
      widget.message('Import failed: $exception');
    }
  }

  String _safeCsvValue(dynamic value) {
    final text = value?.toString() ?? '';
    if (text.isNotEmpty &&
        '=+-@\t\r'.contains(text[0]) &&
        num.tryParse(text) == null) {
      return "'$text";
    }
    return text;
  }

  Future<void> _exportCsv() async {
    try {
      final selectedColumns = columns;
      final csvText = const ListToCsvConverter().convert([
        selectedColumns.map((column) => column.label).toList(),
        ...visibleRows.map(
          (row) =>
              selectedColumns
                  .map((column) => _safeCsvValue(row.values[column.key]))
                  .toList(),
        ),
      ]);
      final bytes = Uint8List.fromList(utf8.encode('\uFEFF$csvText'));
      final filename = '${kind.name}-table.csv';
      final file = XFile.fromData(bytes, name: filename, mimeType: 'text/csv');
      final platform = defaultTargetPlatform;
      final desktop =
          !kIsWeb &&
          (platform == TargetPlatform.windows ||
              platform == TargetPlatform.linux ||
              platform == TargetPlatform.macOS);
      if (desktop) {
        final location = await getSaveLocation(suggestedName: filename);
        if (location == null) return;
        await file.saveTo(location.path);
      } else {
        if (!mounted) return;
        final box = context.findRenderObject() as RenderBox?;
        await Share.shareXFiles(
          [file],
          sharePositionOrigin:
              box == null ? null : box.localToGlobal(Offset.zero) & box.size,
        );
      }
      widget.message('CSV exported');
    } catch (exception) {
      widget.message('Export failed: $exception');
    }
  }

  Widget _button(String label, IconData icon, VoidCallback? action) =>
      OutlinedButton.icon(
        onPressed: action,
        icon: Icon(icon, size: 17),
        label: Text(label),
      );

  Widget _toolbar() {
    final theme = Theme.of(context);
    final selectedColumn =
        columns.where((column) => column.key == selectedKey).firstOrNull;
    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _button('Add Row', Icons.add, _addRow),
              _button(
                'Delete Row',
                Icons.delete_outline,
                selectedRow == null ? null : _deleteRow,
              ),
              _button(
                'Duplicate Row',
                Icons.copy_all_outlined,
                selectedRow == null ? null : _duplicateRow,
              ),
              _button('Add Column', Icons.view_column_outlined, _addColumn),
              _button(
                'Filter',
                Icons.filter_alt_outlined,
                () => setState(() => showFilter = !showFilter),
              ),
              FilledButton.icon(
                onPressed: saving ? null : _save,
                icon: const Icon(Icons.save_outlined, size: 17),
                label: Text(saving ? 'Saving…' : 'Save'),
              ),
              _button('Import', Icons.file_upload_outlined, _importCsv),
              _button('Export', Icons.file_download_outlined, _exportCsv),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 250,
                child: TextField(
                  controller: searchController,
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search table data',
                  ),
                ),
              ),
              if (showFilter) ...[
                SizedBox(
                  width: 190,
                  child: DropdownButtonFormField<String>(
                    value: filterKey,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Filter column',
                    ),
                    items:
                        columns
                            .map(
                              (column) => DropdownMenuItem(
                                value: column.key,
                                child: Text(
                                  column.label,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                    onChanged: (value) {
                      filterKey = value;
                      _rebuildVisible();
                    },
                  ),
                ),
                SizedBox(
                  width: 200,
                  child: TextField(
                    controller: filterController,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Contains…',
                    ),
                  ),
                ),
              ],
              Text(
                '${visibleRows.length} rows${hasPendingChanges ? ' • Unsaved changes' : ''}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          if (selectedRow != null && selectedColumn != null) ...[
            const SizedBox(height: 9),
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Selected: ${selectedColumn.label}',
                  style: theme.textTheme.bodySmall,
                ),
                TextButton.icon(
                  onPressed:
                      selectedColumn.editable
                          ? () => _editCell(selectedRow!, selectedColumn)
                          : null,
                  icon: const Icon(Icons.edit_outlined, size: 15),
                  label: const Text('Edit cell'),
                ),
                TextButton.icon(
                  onPressed: _copyCell,
                  icon: const Icon(Icons.content_copy_outlined, size: 15),
                  label: const Text('Copy'),
                ),
                TextButton.icon(
                  onPressed: selectedColumn.editable ? _pasteCell : null,
                  icon: const Icon(Icons.content_paste_outlined, size: 15),
                  label: const Text('Paste'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _headerCell(TableColumnDef column) {
    final active = sortKey == column.key;
    return SizedBox(
      width: column.width,
      child: InkWell(
        onTap: () => _sort(column),
        onLongPress: column.custom ? () => _renameColumn(column) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  column.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              if (active)
                Icon(
                  ascending ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 13,
                ),
              if (column.custom) const Icon(Icons.edit_outlined, size: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rowCell(SpreadsheetRow row, TableColumnDef column) {
    final selected = selectedRow == row && selectedKey == column.key;
    final value = row.values[column.key]?.toString() ?? '';
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: column.width,
      height: 46,
      child: InkWell(
        onTap: () => _select(row, column),
        onDoubleTap: () => _editCell(row, column),
        onLongPress: () => _editCell(row, column),
        child: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected ? scheme.primary.withValues(alpha: .11) : null,
            border: Border(
              right: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: .6),
              ),
              bottom: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: .55),
              ),
              top:
                  selected
                      ? BorderSide(color: scheme.primary, width: 1.5)
                      : BorderSide.none,
              left:
                  selected
                      ? BorderSide(color: scheme.primary, width: 1.5)
                      : BorderSide.none,
            ),
          ),
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: row.isNew ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _grid() {
    final scheme = Theme.of(context).colorScheme;
    final tableWidth =
        56 + columns.fold<double>(0, (sum, column) => sum + column.width);
    return LayoutBuilder(
      builder:
          (context, constraints) => Scrollbar(
            controller: horizontalController,
            thumbVisibility: true,
            notificationPredicate:
                (notification) => notification.metrics.axis == Axis.horizontal,
            child: SingleChildScrollView(
              controller: horizontalController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: math.max(tableWidth, constraints.maxWidth),
                child: Column(
                  children: [
                    Container(
                      height: 48,
                      color: scheme.surfaceContainerHighest.withValues(
                        alpha: .65,
                      ),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 56,
                            child: Center(
                              child: Text(
                                'S.N',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                          ...columns.map(_headerCell),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Scrollbar(
                        controller: verticalController,
                        thumbVisibility: true,
                        child: ListView.builder(
                          controller: verticalController,
                          itemExtent: 46,
                          itemCount: visibleRows.length,
                          itemBuilder: (context, index) {
                            final row = visibleRows[index];
                            return ColoredBox(
                              color:
                                  index.isEven
                                      ? scheme.surface
                                      : scheme.surfaceContainerLowest,
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 56,
                                    child: Center(
                                      child: Text(
                                        '${index + 1}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ),
                                  ...columns.map(
                                    (column) => _rowCell(row, column),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (!initialized) {
      return _TableSetupView(
        kind: kind,
        existingCount: rows.where((row) => !row.isNew).length,
        onCreate: _createSetup,
      );
    }
    return Column(
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .46,
          ),
          child: SingleChildScrollView(child: _toolbar()),
        ),
        const Divider(height: 1),
        Expanded(
          child:
              visibleRows.isEmpty
                  ? Center(
                    child: Text(
                      rows.isEmpty
                          ? 'No ${kind == TableKind.bookings ? 'bookings' : 'products'} yet. Use Add Row or Import.'
                          : 'No rows match your search or filter.',
                    ),
                  )
                  : _grid(),
        ),
      ],
    );
  }
}

class _TableSetupView extends StatefulWidget {
  const _TableSetupView({
    required this.kind,
    required this.existingCount,
    required this.onCreate,
  });

  final TableKind kind;
  final int existingCount;
  final Future<void> Function(int rows, int extraColumns) onCreate;

  @override
  State<_TableSetupView> createState() => _TableSetupViewState();
}

class _TableSetupViewState extends State<_TableSetupView> {
  final rowController = TextEditingController(text: '5');
  final columnController = TextEditingController(text: '0');
  bool busy = false;
  String? error;

  @override
  void dispose() {
    rowController.dispose();
    columnController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final rowCount = int.tryParse(rowController.text.trim());
    final columnCount = int.tryParse(columnController.text.trim());
    if (rowCount == null ||
        rowCount < 0 ||
        rowCount > 5000 ||
        columnCount == null ||
        columnCount < 0 ||
        columnCount > 50) {
      setState(() => error = 'Enter 0–5000 rows and 0–50 extra columns.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.onCreate(rowCount, columnCount);
    } catch (exception) {
      if (mounted) setState(() => error = exception.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 510),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.table_chart_outlined,
                  size: 34,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  'Create ${widget.kind.title}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 10),
                Text(
                  'Choose the starting size before editing. Your '
                  '${widget.existingCount} existing '
                  '${widget.kind == TableKind.bookings ? 'bookings' : 'products'} '
                  'stay in the table; these counts add blank draft rows and extra columns.',
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: rowController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Number of blank rows',
                    helperText: '0–5000; fill them in after creating the table',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: columnController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'Number of extra columns',
                    helperText:
                        '${widget.kind.baseColumns.length} built-in columns '
                        'are already included; add up to 50 more',
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: busy ? null : _create,
                    icon: const Icon(Icons.add_box_outlined),
                    label: Text(busy ? 'Creating…' : 'Create table'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _CellEditorDialog extends StatefulWidget {
  const _CellEditorDialog({required this.column, required this.initial});

  final TableColumnDef column;
  final String initial;

  @override
  State<_CellEditorDialog> createState() => _CellEditorDialogState();
}

class _CellEditorDialogState extends State<_CellEditorDialog> {
  late final TextEditingController controller;
  String? choice;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initial);
    choice =
        widget.column.choices.contains(widget.initial) ? widget.initial : null;
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Edit ${widget.column.label}'),
    content: SizedBox(
      width: 430,
      child:
          widget.column.type == TableValueType.choice
              ? DropdownButtonFormField<String>(
                value: choice,
                decoration: InputDecoration(labelText: widget.column.label),
                items:
                    widget.column.choices
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                onChanged: (value) => setState(() => choice = value),
              )
              : TextField(
                controller: controller,
                autofocus: true,
                maxLines: widget.column.type == TableValueType.longText ? 6 : 1,
                keyboardType:
                    widget.column.type == TableValueType.number
                        ? const TextInputType.numberWithOptions(decimal: true)
                        : widget.column.type == TableValueType.longText
                        ? TextInputType.multiline
                        : TextInputType.text,
                decoration: InputDecoration(
                  labelText: widget.column.label,
                  hintText:
                      widget.column.type == TableValueType.date
                          ? 'YYYY-MM-DD'
                          : null,
                ),
              ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed:
            () => Navigator.pop(
              context,
              widget.column.type == TableValueType.choice
                  ? choice ?? ''
                  : controller.text.trim(),
            ),
        child: const Text('Apply'),
      ),
    ],
  );
}

class _ColumnNameDialog extends StatefulWidget {
  const _ColumnNameDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_ColumnNameDialog> createState() => _ColumnNameDialogState();
}

class _ColumnNameDialogState extends State<_ColumnNameDialog> {
  late final TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: controller,
      autofocus: true,
      maxLength: 60,
      decoration: const InputDecoration(labelText: 'Column name'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, controller.text.trim()),
        child: const Text('Save'),
      ),
    ],
  );
}
