import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:csv/csv.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'api.dart';
import 'booking_form_fields.dart';
import 'form_sheet.dart';
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
  Timer? _searchDebounce;
  final filterController = TextEditingController();
  final horizontalController = ScrollController();
  final verticalController = ScrollController();
  List<SpreadsheetRow> rows = [];
  List<SpreadsheetRow> visibleRows = [];
  List<TableColumnDef> customColumns = [];
  List<TableColumnDef> formColumns = [];
  List<String> columnOrder = [];
  int layoutRevision = 0;
  bool rearranging = false;
  bool layoutSaving = false;
  bool adding = false;
  SpreadsheetRow? editingRow;
  String? editingKey;
  final cellEditor = TextEditingController();
  final cellFocus = FocusNode();
  SpreadsheetRow? selectedRow;
  String? selectedKey;
  String? sortKey;
  String? filterKey;
  bool ascending = true;
  bool loading = true;
  bool saving = false;
  bool showFilter = false;
  bool initialized = false;
  int _loadVersion = 0;
  String? error;

  List<TableColumnDef> get columns {
    final defaults = [
      ...(formColumns.isEmpty ? kind.baseColumns : formColumns),
      ...customColumns,
    ];
    final positions = {
      for (var index = 0; index < columnOrder.length; index++)
        columnOrder[index]: index,
    };
    return [...defaults]..sort((a, b) {
      final left = positions[a.key] ?? columnOrder.length + defaults.indexOf(a);
      final right =
          positions[b.key] ?? columnOrder.length + defaults.indexOf(b);
      return left.compareTo(right);
    });
  }

  bool get hasPendingChanges =>
      rows.any((row) => row.dirty || (row.isNew && row.draftId == null));

  @override
  void initState() {
    super.initState();
    kind = widget.grocery ? TableKind.products : TableKind.bookings;
    repository = TableRepository(widget.api, kind);
    searchController.addListener(_onSearchChanged);
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
      _searchDebounce?.cancel();
      _load();
    }
  }

  @override
  void dispose() {
    searchController.removeListener(_onSearchChanged);
    _searchDebounce?.cancel();
    filterController.removeListener(_rebuildVisible);
    searchController.dispose();
    filterController.dispose();
    cellEditor.dispose();
    cellFocus.dispose();
    horizontalController.dispose();
    verticalController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _rebuildVisible();
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    final version = ++_loadVersion;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final snapshot = await repository.load(
        search: searchController.text.trim(),
      );
      if (!mounted || version != _loadVersion) return;
      final pending =
          rows
              .where((row) => row.dirty || (row.isNew && row.draftId == null))
              .toList();
      final mergedRows = [...snapshot.rows];
      for (final unsaved in pending) {
        final match = mergedRows.indexWhere(
          (loaded) =>
              unsaved.id.isNotEmpty && loaded.id == unsaved.id ||
              unsaved.draftId != null && loaded.draftId == unsaved.draftId,
        );
        if (match >= 0) {
          mergedRows[match] = unsaved;
        } else {
          mergedRows.insert(0, unsaved);
        }
      }
      setState(() {
        rows = mergedRows;
        customColumns = snapshot.customColumns;
        formColumns = snapshot.formColumns;
        columnOrder = snapshot.columnOrder;
        layoutRevision = snapshot.layoutRevision;
        final positions = {
          for (var index = 0; index < snapshot.rowOrder.length; index++)
            snapshot.rowOrder[index]: index,
        };
        final defaults = [...rows];
        rows.sort((a, b) {
          final left =
              positions[a.draftId ?? a.id] ??
              snapshot.rowOrder.length + defaults.indexOf(a);
          final right =
              positions[b.draftId ?? b.id] ??
              snapshot.rowOrder.length + defaults.indexOf(b);
          return left.compareTo(right);
        });
        initialized = snapshot.initialized;
        selectedRow = null;
        selectedKey = null;
        loading = false;
      });
      _rebuildVisible();
    } catch (exception) {
      if (!mounted || version != _loadVersion) return;
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
    if (rearranging) return;
    ascending = sortKey == column.key ? !ascending : true;
    sortKey = column.key;
    _rebuildVisible();
  }

  void _select(SpreadsheetRow row, TableColumnDef column) {
    if (editingRow == row && editingKey == column.key) return;
    if (column.editable && !rearranging) {
      _startInlineEdit(row, column);
      return;
    }
    setState(() {
      selectedRow = row;
      selectedKey = column.key;
    });
  }

  void _startInlineEdit(SpreadsheetRow row, TableColumnDef column) {
    cellEditor.text = row.values[column.key]?.toString() ?? '';
    cellEditor.selection = TextSelection.collapsed(
      offset: cellEditor.text.length,
    );
    setState(() {
      selectedRow = row;
      selectedKey = column.key;
      editingRow = row;
      editingKey = column.key;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && editingRow == row) cellFocus.requestFocus();
    });
  }

  void _cancelInlineEdit() => setState(() {
    editingRow = null;
    editingKey = null;
  });

  Future<void> _saveInlineEdit(
    SpreadsheetRow row,
    TableColumnDef column,
  ) async {
    if (saving) return;
    final value = cellEditor.text.trim();
    if (column.required && value.isEmpty) {
      widget.message('${column.label} is required');
      return;
    }
    if (column.type == TableValueType.number &&
        value.isNotEmpty &&
        !isNonNegativeNumber(value)) {
      widget.message('${column.label} must be a non-negative number');
      return;
    }
    if (column.type == TableValueType.date &&
        value.isNotEmpty &&
        DateTime.tryParse(value) == null) {
      widget.message('Enter a valid date');
      return;
    }
    if (column.type == TableValueType.choice &&
        value.isNotEmpty &&
        !column.choices.contains(value)) {
      widget.message('Choose a valid ${column.label}');
      return;
    }
    final before = Map<String, dynamic>.of(row.values);
    final beforeDirty = row.dirty;
    final beforeKeys = Set<String>.of(row.changedKeys);
    final parsed =
        column.type == TableValueType.toggle ? value == 'true' : value;
    setState(() {
      row.setValue(column.key, parsed);
      editingRow = null;
      editingKey = null;
      saving = true;
    });
    try {
      final updated = await repository.saveRow(row, columns);
      if (!mounted) return;
      setState(() {
        row.values
          ..clear()
          ..addAll(updated.values);
        row.isNew = updated.isNew;
        row.draftId = updated.draftId;
        row.dirty = false;
        row.changedKeys.clear();
      });
      _rebuildVisible();
      widget.onUpdated();
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        row.values
          ..clear()
          ..addAll(before);
        row.dirty = beforeDirty;
        row.changedKeys
          ..clear()
          ..addAll(beforeKeys);
      });
      widget.message('Cell was not saved: $exception');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _addRecord() async {
    if (adding) return;
    setState(() => adding = true);
    try {
      final module =
          kind == TableKind.bookings ? 'bookings' : 'grocery_products';
      final fields = await loadRecordFields(widget.api, module);
      if (!mounted) return;
      final data = await showRecordForm(
        context,
        kind == TableKind.bookings ? 'New booking' : 'New product',
        fields,
        api: widget.api,
      );
      if (data == null || !mounted) return;
      if (kind == TableKind.bookings) data['manual'] = true;
      await widget.api.post(kind.path, data);
      if (!mounted) return;
      await _load();
      widget.onUpdated();
      widget.message('Record added');
    } catch (exception) {
      if (mounted) widget.message('Could not add record: $exception');
    } finally {
      if (mounted) setState(() => adding = false);
    }
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

  Future<void> _deleteRow([SpreadsheetRow? target]) async {
    final row = target ?? selectedRow;
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

  bool get canRearrangeRows =>
      searchController.text.trim().isEmpty &&
      filterController.text.trim().isEmpty &&
      sortKey == null;

  Future<void> _moveColumn(int index, int direction) async {
    if (layoutSaving ||
        index + direction < 0 ||
        index + direction >= columns.length) {
      return;
    }
    final next = columns.map((column) => column.key).toList();
    final value = next.removeAt(index);
    next.insert(index + direction, value);
    setState(() {
      columnOrder = next;
      layoutSaving = true;
    });
    try {
      final saved = await repository.saveLayout(
        revision: layoutRevision,
        columns: next,
      );
      if (mounted) {
        setState(
          () =>
              layoutRevision =
                  (saved['revision'] as num?)?.toInt() ?? layoutRevision + 1,
        );
      }
    } catch (exception) {
      if (mounted) {
        widget.message('Column order was not saved: $exception');
        await _load();
      }
    } finally {
      if (mounted) setState(() => layoutSaving = false);
    }
  }

  Future<void> _moveRow(int index, int direction) async {
    if (layoutSaving ||
        !canRearrangeRows ||
        index + direction < 0 ||
        index + direction >= visibleRows.length) {
      return;
    }
    final row = visibleRows[index];
    final other = visibleRows[index + direction];
    final first = rows.indexOf(row);
    final second = rows.indexOf(other);
    if (first < 0 || second < 0) return;
    final moved = [...rows];
    moved[first] = other;
    moved[second] = row;
    final ids = moved.map((item) => item.draftId ?? item.id).toList();
    if (ids.any((id) => id.isEmpty)) {
      widget.message('Save new rows before rearranging them');
      return;
    }
    setState(() {
      rows = moved;
      layoutSaving = true;
    });
    _rebuildVisible();
    try {
      final saved = await repository.saveLayout(
        revision: layoutRevision,
        rows: ids,
      );
      if (mounted) {
        setState(
          () =>
              layoutRevision =
                  (saved['revision'] as num?)?.toInt() ?? layoutRevision + 1,
        );
      }
    } catch (exception) {
      if (mounted) {
        widget.message('Row order was not saved: $exception');
        await _load();
      }
    } finally {
      if (mounted) setState(() => layoutSaving = false);
    }
  }

  Future<void> _resetLayout() async {
    if (layoutSaving) return;
    setState(() => layoutSaving = true);
    try {
      await repository.saveLayout(
        revision: layoutRevision,
        columns: [],
        rows: [],
      );
      if (!mounted) return;
      setState(() {
        rearranging = false;
        sortKey = null;
        filterKey = null;
        showFilter = false;
        filterController.clear();
      });
      await _load();
      widget.message('Table layout reset. Records were not changed.');
    } catch (exception) {
      if (mounted) widget.message('Could not reset layout: $exception');
    } finally {
      if (mounted) setState(() => layoutSaving = false);
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

  Future<void> _showSpreadsheetTools() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder:
          (sheetContext) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(title: Text('Spreadsheet tools')),
                for (final tool in const [
                  ('save', 'Save pending rows', Icons.save_outlined),
                  (
                    'duplicate',
                    'Duplicate selected row',
                    Icons.copy_all_outlined,
                  ),
                  (
                    'column',
                    'Add legacy custom column',
                    Icons.view_column_outlined,
                  ),
                  ('copy', 'Copy selected cell', Icons.content_copy_outlined),
                  (
                    'paste',
                    'Paste into selected cell',
                    Icons.content_paste_outlined,
                  ),
                  ('import', 'Import CSV', Icons.file_upload_outlined),
                  ('export', 'Export CSV', Icons.file_download_outlined),
                ])
                  ListTile(
                    leading: Icon(tool.$3),
                    title: Text(tool.$2),
                    onTap: () => Navigator.pop(sheetContext, tool.$1),
                  ),
              ],
            ),
          ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'save':
        _save();
      case 'duplicate':
        _duplicateRow();
      case 'column':
        _addColumn();
      case 'copy':
        _copyCell();
      case 'paste':
        _pasteCell();
      case 'import':
        _importCsv();
      case 'export':
        _exportCsv();
    }
  }

  Widget _toolbar() {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  kind == TableKind.bookings
                      ? 'Linked booking table'
                      : 'Linked product table',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Spreadsheet tools',
                onPressed: _showSpreadsheetTools,
                icon: const Icon(Icons.settings_outlined),
              ),
            ],
          ),
          const SizedBox(height: 8),
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
              PopupMenuButton<String>(
                tooltip: 'Table layout',
                icon: const Icon(Icons.menu),
                onSelected: (value) {
                  if (value == 'rearrange') {
                    setState(() {
                      rearranging = !rearranging;
                      if (rearranging) {
                        editingRow = null;
                        editingKey = null;
                      }
                    });
                  } else if (value == 'reset') {
                    _resetLayout();
                  }
                },
                itemBuilder:
                    (_) => [
                      PopupMenuItem(
                        value: 'rearrange',
                        child: Text(
                          rearranging ? 'Exit Rearrange' : 'Rearrange',
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'reset',
                        child: Text('Reset Table Layout'),
                      ),
                    ],
              ),
              if (rearranging)
                TextButton(
                  onPressed: () => setState(() => rearranging = false),
                  child: const Text('Done'),
                ),
              FilledButton.icon(
                onPressed: adding ? null : _addRecord,
                icon: const Icon(Icons.add, size: 17),
                label: const Text('Add Record'),
              ),
              Text(
                '${visibleRows.length} rows${hasPendingChanges ? ' • Unsaved changes' : ''}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerCell(TableColumnDef column) {
    final active = sortKey == column.key;
    final index = columns.indexWhere((item) => item.key == column.key);
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
              if (rearranging) ...[
                IconButton(
                  tooltip: 'Move ${column.label} left',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 26,
                    minHeight: 28,
                  ),
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.arrow_back, size: 16),
                  onPressed:
                      index == 0 || layoutSaving
                          ? null
                          : () => _moveColumn(index, -1),
                ),
                IconButton(
                  tooltip: 'Move ${column.label} right',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 26,
                    minHeight: 28,
                  ),
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  onPressed:
                      index == columns.length - 1 || layoutSaving
                          ? null
                          : () => _moveColumn(index, 1),
                ),
              ],
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
          child:
              editingRow == row && editingKey == column.key
                  ? Row(
                    children: [
                      Expanded(
                        child: Focus(
                          onKeyEvent: (_, event) {
                            if (event is KeyDownEvent &&
                                event.logicalKey == LogicalKeyboardKey.escape) {
                              _cancelInlineEdit();
                              return KeyEventResult.handled;
                            }
                            return KeyEventResult.ignored;
                          },
                          child:
                              column.type == TableValueType.choice ||
                                      column.type == TableValueType.toggle
                                  ? DropdownButton<String>(
                                    isExpanded: true,
                                    value:
                                        column.type == TableValueType.toggle
                                            ? (cellEditor.text == 'true'
                                                ? 'true'
                                                : 'false')
                                            : column.choices.contains(
                                              cellEditor.text,
                                            )
                                            ? cellEditor.text
                                            : null,
                                    items:
                                        (column.type == TableValueType.toggle
                                                ? const ['true', 'false']
                                                : column.choices)
                                            .map(
                                              (choice) => DropdownMenuItem(
                                                value: choice,
                                                child: Text(
                                                  choice,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            )
                                            .toList(),
                                    onChanged:
                                        (value) => setState(
                                          () => cellEditor.text = value ?? '',
                                        ),
                                  )
                                  : TextField(
                                    controller: cellEditor,
                                    focusNode: cellFocus,
                                    maxLines: 1,
                                    keyboardType:
                                        column.type == TableValueType.number
                                            ? const TextInputType.numberWithOptions(
                                              decimal: true,
                                            )
                                            : column.type == TableValueType.date
                                            ? TextInputType.datetime
                                            : TextInputType.text,
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      border: InputBorder.none,
                                    ),
                                    onSubmitted:
                                        (_) => _saveInlineEdit(row, column),
                                    onTapOutside: (_) => _cancelInlineEdit(),
                                  ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Save cell',
                        constraints: const BoxConstraints(
                          minWidth: 24,
                          minHeight: 28,
                        ),
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.check, size: 16),
                        onPressed:
                            saving ? null : () => _saveInlineEdit(row, column),
                      ),
                      IconButton(
                        tooltip: 'Cancel edit',
                        constraints: const BoxConstraints(
                          minWidth: 24,
                          minHeight: 28,
                        ),
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: _cancelInlineEdit,
                      ),
                    ],
                  )
                  : Tooltip(
                    message: value,
                    child: Text(
                      value,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight:
                            row.isNew ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
        ),
      ),
    );
  }

  Widget _grid() {
    final scheme = Theme.of(context).colorScheme;
    final tableWidth =
        164 + columns.fold<double>(0, (sum, column) => sum + column.width);
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
                            width: 100,
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
                          const SizedBox(width: 64),
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
                                    width: 100,
                                    child:
                                        rearranging
                                            ? Row(
                                              children: [
                                                IconButton(
                                                  tooltip: 'Move row up',
                                                  constraints:
                                                      const BoxConstraints(
                                                        minWidth: 25,
                                                        minHeight: 28,
                                                      ),
                                                  padding: EdgeInsets.zero,
                                                  icon: const Icon(
                                                    Icons.arrow_upward,
                                                    size: 15,
                                                  ),
                                                  onPressed:
                                                      index == 0 ||
                                                              layoutSaving ||
                                                              !canRearrangeRows
                                                          ? null
                                                          : () => _moveRow(
                                                            index,
                                                            -1,
                                                          ),
                                                ),
                                                IconButton(
                                                  tooltip: 'Move row down',
                                                  constraints:
                                                      const BoxConstraints(
                                                        minWidth: 25,
                                                        minHeight: 28,
                                                      ),
                                                  padding: EdgeInsets.zero,
                                                  icon: const Icon(
                                                    Icons.arrow_downward,
                                                    size: 15,
                                                  ),
                                                  onPressed:
                                                      index ==
                                                                  visibleRows
                                                                          .length -
                                                                      1 ||
                                                              layoutSaving ||
                                                              !canRearrangeRows
                                                          ? null
                                                          : () => _moveRow(
                                                            index,
                                                            1,
                                                          ),
                                                ),
                                              ],
                                            )
                                            : Center(
                                              child: Text(
                                                '${index + 1}',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                  ),
                                  ...columns.map(
                                    (column) => _rowCell(row, column),
                                  ),
                                  SizedBox(
                                    width: 64,
                                    child: IconButton(
                                      tooltip: 'Delete row',
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        size: 18,
                                      ),
                                      onPressed: () => _deleteRow(row),
                                    ),
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
                      rows.isEmpty && searchController.text.trim().isEmpty
                          ? 'No ${kind == TableKind.bookings ? 'bookings' : 'products'} yet. Use Add Record or Import.'
                          : 'No matching records found.',
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
