import 'dart:convert';
import 'dart:math' as math;

import 'package:csv/csv.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'api.dart';
import 'named_table_repository.dart';

enum _TableSelection { none, row, column, cell }

class NamedTablesScreen extends StatefulWidget {
  const NamedTablesScreen({
    super.key,
    required this.api,
    required this.grocery,
    required this.selectedTableId,
    required this.tables,
    required this.onSelectTable,
    required this.onTablesChanged,
    required this.onOpenLinked,
    required this.message,
  });

  final ApiClient api;
  final bool grocery;
  final String? selectedTableId;
  final List<NamedTableSummary> tables;
  final ValueChanged<String?> onSelectTable;
  final VoidCallback onTablesChanged;
  final VoidCallback onOpenLinked;
  final ValueChanged<String> message;

  @override
  State<NamedTablesScreen> createState() => NamedTablesScreenState();
}

class NamedTablesScreenState extends State<NamedTablesScreen> {
  late NamedTableRepository repository;
  final search = TextEditingController();
  final filter = TextEditingController();
  final cellEditor = TextEditingController();
  final cellFocus = FocusNode();
  final horizontal = ScrollController();
  final vertical = ScrollController();
  NamedTable? table;
  String? selectedRowId;
  String? selectedColumnId;
  String? editingRowId;
  String? editingColumnId;
  _TableSelection _selection = _TableSelection.none;
  String? sortColumnId;
  String? filterColumnId;
  bool ascending = true;
  bool loading = false;
  bool saving = false;
  bool dirty = false;
  bool showFilter = false;
  String? error;
  int loadSerial = 0;
  int localId = 0;

  NamedTableRow? get selectedRow =>
      table?.rows.where((row) => row.id == selectedRowId).firstOrNull;
  NamedTableColumn? get selectedColumn =>
      table?.columns
          .where((column) => column.id == selectedColumnId)
          .firstOrNull;

  bool get hasPendingChanges => dirty;
  String _newId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${localId++}';

  @override
  void initState() {
    super.initState();
    repository = NamedTableRepository(widget.api);
    search.addListener(_refresh);
    filter.addListener(_refresh);
    _load();
  }

  @override
  void didUpdateWidget(covariant NamedTablesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api ||
        oldWidget.grocery != widget.grocery ||
        oldWidget.selectedTableId != widget.selectedTableId) {
      repository = NamedTableRepository(widget.api);
      search.clear();
      filter.clear();
      filterColumnId = null;
      sortColumnId = null;
      selectedRowId = null;
      selectedColumnId = null;
      editingRowId = null;
      editingColumnId = null;
      cellFocus.unfocus();
      _selection = _TableSelection.none;
      _load();
    }
  }

  @override
  void dispose() {
    loadSerial++;
    search.removeListener(_refresh);
    filter.removeListener(_refresh);
    search.dispose();
    filter.dispose();
    cellEditor.dispose();
    cellFocus.dispose();
    horizontal.dispose();
    vertical.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final serial = ++loadSerial;
    final id = widget.selectedTableId;
    if (id == null) {
      if (mounted) {
        setState(() {
          table = null;
          loading = false;
          dirty = false;
          error = null;
        });
      }
      return;
    }
    setState(() {
      loading = true;
      error = null;
      table = null;
      dirty = false;
    });
    try {
      final loaded = await repository.load(id);
      if (!mounted || serial != loadSerial) return;
      if (loaded.platform != (widget.grocery ? 'grocery' : 'airline')) {
        throw const FormatException('Table belongs to a different workspace');
      }
      setState(() {
        table = loaded;
        loading = false;
      });
    } catch (exception) {
      if (mounted && serial == loadSerial) {
        setState(() {
          error = exception.toString();
          loading = false;
        });
      }
    }
  }

  Future<void> _create() async {
    final request = await showDialog<_CreateSpec>(
      context: context,
      builder: (_) => const _CreateTableDialog(),
    );
    if (request == null || !mounted) return;
    try {
      final created = await repository.create(
        name: request.name,
        grocery: widget.grocery,
        rows: request.rows,
        columns: request.columns,
        headers: request.headers,
      );
      if (!mounted) return;
      widget.onTablesChanged();
      widget.onSelectTable(created.id);
      widget.message('Table created');
    } catch (exception) {
      if (mounted) widget.message(exception.toString());
    }
  }

  Future<String?> _ask(
    String title,
    String initial, {
    bool multiline = false,
  }) => showDialog<String>(
    context: context,
    builder:
        (_) =>
            _TextDialog(title: title, initial: initial, multiline: multiline),
  );

  Future<void> _renameTable() async {
    final current = table;
    if (current == null) return;
    final name = await _ask('Name for sidebar', current.name);
    if (!mounted || name == null || name.trim().isEmpty) return;
    setState(() {
      current.name = name.trim();
      dirty = true;
    });
    await _save();
  }

  Future<void> _deleteTable() async {
    final current = table;
    if (current == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text('Delete ${current.name}?'),
            content: const Text(
              'The table and all its cells will be permanently deleted.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Delete table'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await repository.delete(current.id);
      if (!mounted) return;
      setState(() {
        table = null;
        dirty = false;
      });
      widget.onTablesChanged();
      widget.onSelectTable(null);
      widget.message('Table deleted');
    } catch (exception) {
      if (mounted) widget.message(exception.toString());
    }
  }

  Future<void> _save() async {
    final current = table;
    if (current == null || saving) return;
    _finishInlineEdit();
    setState(() => saving = true);
    try {
      final saved = await repository.save(current);
      if (!mounted || widget.selectedTableId != saved.id) return;
      setState(() {
        table = saved;
        dirty = false;
      });
      widget.onTablesChanged();
      widget.message('Table saved');
    } catch (exception) {
      if (mounted) widget.message('Save failed: $exception');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _editHeader(NamedTableColumn column) async {
    final label = await _ask('Name column', column.label);
    if (!mounted || label == null) return;
    if (label.trim().length > 80) {
      widget.message('Column name must be at most 80 characters');
      return;
    }
    setState(() {
      column.label = label.trim();
      dirty = true;
    });
  }

  static const palette = <String, String>{
    'Blue': '#DDEBFF',
    'Green': '#DDF5E8',
    'Yellow': '#FFF2C7',
    'Pink': '#FCE3EB',
    'Purple': '#EAE2FF',
    'Orange': '#FFE8D2',
    'Gray': '#E9EDF2',
  };

  Color? _decodeColor(String? value) {
    if (value == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) {
      return null;
    }
    return Color(int.parse('ff${value.substring(1)}', radix: 16));
  }

  Future<String?> _pickColor(String title) => showDialog<String>(
    context: context,
    builder:
        (dialogContext) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 280,
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final entry in palette.entries)
                  Tooltip(
                    message: entry.key,
                    child: InkWell(
                      key: ValueKey('palette-${entry.key}'),
                      onTap: () => Navigator.pop(dialogContext, entry.value),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: _decodeColor(entry.value),
                          border: Border.all(color: const Color(0xffb8c6d4)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, ''),
              child: const Text('Remove color'),
            ),
          ],
        ),
  );

  Future<void> _colorRow() async {
    final row = selectedRow;
    if (row == null) return;
    final color = await _pickColor('Color row');
    if (!mounted || color == null) return;
    setState(() {
      row.color = color.isEmpty ? null : color;
      dirty = true;
    });
  }

  void _selectRowForAction(NamedTableRow row) {
    _finishInlineEdit();
    setState(() {
      selectedRowId = row.id;
      _selection = _TableSelection.row;
    });
  }

  Future<void> _colorColumn() async {
    final column = selectedColumn;
    if (column == null) return;
    final color = await _pickColor('Color column');
    if (!mounted || color == null) return;
    setState(() {
      column.color = color.isEmpty ? null : color;
      dirty = true;
    });
  }

  String _formatReminder(String? value) {
    final date = DateTime.tryParse(value ?? '')?.toLocal();
    if (date == null) return 'No notification';
    final localizations = MaterialLocalizations.of(context);
    return '${localizations.formatShortDate(date)} '
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(date))}';
  }

  Future<void> _setReminder() async {
    _finishInlineEdit();
    final row = selectedRow;
    if (row == null) return;
    final initial =
        DateTime.tryParse(row.notifyAt ?? '')?.toLocal() ??
        DateTime.now().add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    final when = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (!when.isAfter(DateTime.now())) {
      widget.message('Choose a future notification time');
      return;
    }
    setState(() {
      row.notifyAt = when.toUtc().toIso8601String();
      dirty = true;
    });
    widget.message(
      'Notification set for ${_formatReminder(row.notifyAt)}. Save the table.',
    );
  }

  void _clearReminder() {
    final row = selectedRow;
    if (row == null || row.notifyAt == null) return;
    setState(() {
      row.notifyAt = null;
      dirty = true;
    });
  }

  void _addColumn() {
    final current = table;
    if (current == null || current.columns.length >= 50) {
      widget.message('Maximum 50 columns');
      return;
    }
    _finishInlineEdit();
    final column = NamedTableColumn(_newId('COL'), '');
    setState(() {
      current.columns.add(column);
      dirty = true;
      selectedColumnId = column.id;
      _selection = _TableSelection.column;
    });
    _editHeader(column);
  }

  Future<void> _deleteColumn() async {
    _finishInlineEdit();
    final current = table;
    final id = selectedColumnId;
    if (current == null || id == null) return;
    if (current.columns.length <= 1) {
      widget.message('A table needs at least one column');
      return;
    }
    final column = current.columns.where((item) => item.id == id).firstOrNull;
    if (column == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Delete column?'),
            content: Text(
              'All values in ${column.label.isEmpty ? 'this column' : column.label} will be removed.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      current.columns.removeWhere((item) => item.id == id);
      for (final row in current.rows) {
        row.cells.remove(id);
      }
      selectedColumnId = null;
      _selection = _TableSelection.none;
      filterColumnId = filterColumnId == id ? null : filterColumnId;
      sortColumnId = sortColumnId == id ? null : sortColumnId;
      dirty = true;
    });
  }

  void _addRow() {
    final current = table;
    if (current == null || current.rows.length >= 5000) {
      widget.message('Maximum 5000 rows');
      return;
    }
    _finishInlineEdit();
    final row = NamedTableRow(_newId('ROW'), {});
    setState(() {
      current.rows.add(row);
      selectedRowId = row.id;
      _selection = _TableSelection.row;
      dirty = true;
    });
  }

  void _duplicateRow() {
    _finishInlineEdit();
    final current = table;
    final selected =
        current?.rows.where((row) => row.id == selectedRowId).firstOrNull;
    if (current == null || selected == null || current.rows.length >= 5000) {
      return;
    }
    final copy = NamedTableRow(
      _newId('ROW'),
      Map.of(selected.cells),
      color: selected.color,
    );
    setState(() {
      current.rows.insert(current.rows.indexOf(selected) + 1, copy);
      selectedRowId = copy.id;
      _selection = _TableSelection.row;
      dirty = true;
    });
  }

  Future<void> _deleteRow() async {
    _finishInlineEdit();
    final current = table;
    final row = selectedRow;
    if (current == null || row == null) return;
    if (row.cells.values.any((value) => value.isNotEmpty) ||
        row.notifyAt != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
              title: const Text('Delete selected row?'),
              content: const Text(
                'The row values and notification will be removed after you save.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Delete row'),
                ),
              ],
            ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      current.rows.removeWhere((item) => item.id == row.id);
      selectedRowId = null;
      _selection = _TableSelection.none;
      dirty = true;
    });
  }

  void _finishInlineEdit() {
    if (editingRowId == null && editingColumnId == null) return;
    cellFocus.unfocus();
    if (mounted) {
      setState(() {
        editingRowId = null;
        editingColumnId = null;
      });
    }
  }

  void _startInlineEdit(NamedTableRow row, NamedTableColumn column) {
    final value = row.cells[column.id] ?? '';
    if (editingRowId != row.id || editingColumnId != column.id) {
      cellEditor.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }
    setState(() {
      selectedRowId = row.id;
      selectedColumnId = column.id;
      editingRowId = row.id;
      editingColumnId = column.id;
      _selection = _TableSelection.cell;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && editingRowId == row.id && editingColumnId == column.id) {
        cellFocus.requestFocus();
      }
    });
  }

  void _updateInlineCell(
    NamedTableRow row,
    NamedTableColumn column,
    String value,
  ) {
    final previous = row.cells[column.id] ?? '';
    if (previous == value) return;
    row.cells[column.id] = value;
    final lineCountChanged =
        '\n'.allMatches(previous).length != '\n'.allMatches(value).length;
    if (!dirty || lineCountChanged) setState(() => dirty = true);
  }

  void _goToNextRow() {
    final current = table;
    final row = selectedRow;
    final column = selectedColumn;
    if (current == null || row == null || column == null) return;
    final visible = _visibleRows(current);
    final index = visible.indexWhere((item) => item.id == row.id);
    if (index < 0 || index + 1 >= visible.length) {
      widget.message('This is the last visible row. Use Add Row to continue.');
      return;
    }
    _finishInlineEdit();
    _startInlineEdit(visible[index + 1], column);
  }

  KeyEventResult _handleCellKey(
    KeyEvent event,
    NamedTableRow row,
    NamedTableColumn column,
  ) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.enter) {
      return KeyEventResult.ignored;
    }
    final current = cellEditor.value;
    final start =
        current.selection.isValid
            ? current.selection.start
            : current.text.length;
    final end =
        current.selection.isValid ? current.selection.end : current.text.length;
    if (current.text.length - (end - start) >= 10000) {
      return KeyEventResult.handled;
    }
    final value = current.text.replaceRange(start, end, '\n');
    cellEditor.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: start + 1),
    );
    _updateInlineCell(row, column, value);
    return KeyEventResult.handled;
  }

  Future<void> _editCell(NamedTableRow row, NamedTableColumn column) async {
    _finishInlineEdit();
    final value = await _ask(
      column.label.isEmpty ? 'Edit cell' : column.label,
      row.cells[column.id] ?? '',
      multiline: true,
    );
    if (value == null || !mounted) return;
    if (value.length > 10000) {
      widget.message('Cell value must be at most 10,000 characters');
      return;
    }
    setState(() {
      row.cells[column.id] = value;
      dirty = true;
    });
  }

  Future<void> _copy() async {
    final current = table;
    final row =
        current?.rows.where((item) => item.id == selectedRowId).firstOrNull;
    if (row == null || selectedColumnId == null) return;
    await Clipboard.setData(
      ClipboardData(text: row.cells[selectedColumnId] ?? ''),
    );
    widget.message('Cell copied');
  }

  Future<void> _paste() async {
    final current = table;
    final row =
        current?.rows.where((item) => item.id == selectedRowId).firstOrNull;
    if (row == null || selectedColumnId == null) return;
    final value = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (value == null) return;
    if (value.length > 10000) {
      widget.message('Cell value must be at most 10,000 characters');
      return;
    }
    setState(() {
      row.cells[selectedColumnId!] = value;
      dirty = true;
    });
    if (editingRowId == row.id && editingColumnId == selectedColumnId) {
      cellEditor.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }
  }

  Future<void> _importCsv() async {
    final current = table;
    if (current == null) return;
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'CSV',
            extensions: ['csv'],
            mimeTypes: ['text/csv'],
          ),
        ],
      );
      if (file == null || !mounted) return;
      final parsed = const CsvToListConverter(
        shouldParseNumbers: false,
      ).convert((await file.readAsString()).replaceFirst('\uFEFF', ''));
      if (parsed.isEmpty) {
        widget.message('CSV is empty');
        return;
      }
      if (current.rows.length + parsed.length - 1 > 5000) {
        widget.message('Import would exceed 5000 rows');
        return;
      }
      final header =
          parsed.first
              .map((item) => item.toString().trim().toLowerCase())
              .toList();
      final mapping = <int, NamedTableColumn>{};
      for (var index = 0; index < header.length; index++) {
        final matched =
            current.columns
                .where(
                  (column) =>
                      column.label.isNotEmpty &&
                      column.label.toLowerCase() == header[index],
                )
                .firstOrNull;
        if (matched != null) {
          mapping[index] = matched;
        } else if (index < current.columns.length &&
            current.columns[index].label.isEmpty) {
          mapping[index] = current.columns[index];
        }
      }
      if (mapping.isEmpty) {
        widget.message('CSV headings do not match this table');
        return;
      }
      final imported = <NamedTableRow>[];
      for (final values in parsed.skip(1)) {
        if (values.every((value) => value.toString().trim().isEmpty)) continue;
        final cells = <String, String>{};
        for (final entry in mapping.entries) {
          if (entry.key < values.length) {
            cells[entry.value.id] = values[entry.key].toString();
          }
        }
        imported.add(NamedTableRow(_newId('ROW'), cells));
      }
      setState(() {
        current.rows.addAll(imported);
        dirty = true;
      });
      widget.message('${imported.length} rows imported. Save to keep them.');
    } catch (exception) {
      if (mounted) widget.message('Import failed: $exception');
    }
  }

  String _safeCsv(String text) =>
      text.isNotEmpty &&
              '=+-@\t\r'.contains(text[0]) &&
              num.tryParse(text) == null
          ? "'$text"
          : text;

  Future<void> _exportCsv() async {
    final current = table;
    if (current == null) return;
    try {
      final csv = const ListToCsvConverter().convert([
        current.columns.map((column) => column.label).toList(),
        for (final row in _visibleRows(current))
          current.columns
              .map((column) => _safeCsv(row.cells[column.id] ?? ''))
              .toList(),
      ]);
      final bytes = Uint8List.fromList(utf8.encode('\uFEFF$csv'));
      final filename =
          '${current.name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}.csv';
      final file = XFile.fromData(bytes, name: filename, mimeType: 'text/csv');
      final desktop =
          !kIsWeb &&
          {
            TargetPlatform.windows,
            TargetPlatform.linux,
            TargetPlatform.macOS,
          }.contains(defaultTargetPlatform);
      if (desktop) {
        final location = await getSaveLocation(suggestedName: filename);
        if (location != null) await file.saveTo(location.path);
      } else {
        if (!mounted) return;
        final box = context.findRenderObject() as RenderBox?;
        await Share.shareXFiles(
          [file],
          sharePositionOrigin:
              box == null ? null : box.localToGlobal(Offset.zero) & box.size,
        );
      }
    } catch (exception) {
      if (mounted) widget.message('Export failed: $exception');
    }
  }

  List<NamedTableRow> _visibleRows(NamedTable current) {
    final needle = search.text.trim().toLowerCase();
    final filterNeedle = filter.text.trim().toLowerCase();
    final result =
        current.rows.where((row) {
          // Keep the active editor visible until the user finishes typing.
          if (row.id == editingRowId) return true;
          if (needle.isNotEmpty &&
              !row.cells.values.any(
                (value) => value.toLowerCase().contains(needle),
              )) {
            return false;
          }
          if (filterNeedle.isNotEmpty &&
              filterColumnId != null &&
              !(row.cells[filterColumnId] ?? '').toLowerCase().contains(
                filterNeedle,
              )) {
            return false;
          }
          return true;
        }).toList();
    if (sortColumnId != null) {
      result.sort((a, b) {
        final left = a.cells[sortColumnId] ?? '';
        final right = b.cells[sortColumnId] ?? '';
        final aNumber = num.tryParse(left);
        final bNumber = num.tryParse(right);
        final compared =
            aNumber != null && bNumber != null
                ? aNumber.compareTo(bNumber)
                : left.toLowerCase().compareTo(right.toLowerCase());
        return ascending ? compared : -compared;
      });
    }
    return result;
  }

  Widget _landing() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 12,
        children: [
          Text('Your tables', style: Theme.of(context).textTheme.headlineSmall),
          FilledButton.icon(
            onPressed: _create,
            icon: const Icon(Icons.add),
            label: const Text('Create table'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      const Text(
        'Choose a sidebar name, rows, columns and your own headings. No columns are pre-named.',
      ),
      const SizedBox(height: 20),
      if (widget.tables.isEmpty)
        const Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('No custom tables yet. Select Create table to begin.'),
          ),
        ),
      for (final item in widget.tables)
        Card(
          child: ListTile(
            leading: const Icon(Icons.table_chart_outlined),
            title: Text(item.name),
            subtitle: Text(
              '${item.rowCount} rows · ${item.columnCount} columns',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => widget.onSelectTable(item.id),
          ),
        ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: widget.onOpenLinked,
        icon: const Icon(Icons.link_outlined),
        label: Text(
          widget.grocery
              ? 'Open linked product spreadsheet'
              : 'Open linked booking spreadsheet',
        ),
      ),
    ],
  );

  List<PopupMenuEntry<String>> _selectionMenuItems(
    NamedTableRow? row,
  ) => switch (_selection) {
    _TableSelection.none => const [],
    _TableSelection.row => [
      const PopupMenuItem(value: 'duplicate', child: Text('Duplicate Row')),
      const PopupMenuItem(value: 'row-color', child: Text('Row color')),
      const PopupMenuItem(value: 'reminder', child: Text('Set notification')),
      if (row?.notifyAt != null)
        const PopupMenuItem(
          value: 'clear-reminder',
          child: Text('Clear notification'),
        ),
      const PopupMenuItem(value: 'delete-row', child: Text('Delete Row')),
    ],
    _TableSelection.column => const [
      PopupMenuItem(value: 'name', child: Text('Name Header')),
      PopupMenuItem(value: 'column-color', child: Text('Column color')),
      PopupMenuItem(value: 'sort', child: Text('Sort column')),
      PopupMenuItem(value: 'delete-column', child: Text('Delete Column')),
    ],
    _TableSelection.cell => const [
      PopupMenuItem(value: 'edit', child: Text('Edit cell')),
      PopupMenuItem(value: 'copy', child: Text('Copy')),
      PopupMenuItem(value: 'paste', child: Text('Paste')),
    ],
  };

  void _runSelectionAction(String value) {
    final row = selectedRow;
    final column = selectedColumn;
    switch (value) {
      case 'duplicate':
        _duplicateRow();
      case 'row-color':
        _colorRow();
      case 'reminder':
        _setReminder();
      case 'clear-reminder':
        _clearReminder();
      case 'delete-row':
        _deleteRow();
      case 'name':
        if (column != null) _editHeader(column);
      case 'column-color':
        _colorColumn();
      case 'sort':
        if (column != null) _sortColumn(column);
      case 'delete-column':
        _deleteColumn();
      case 'edit':
        if (row != null && column != null) _editCell(row, column);
      case 'copy':
        _copy();
      case 'paste':
        _paste();
    }
  }

  Widget _toolbar(NamedTable current, List<NamedTableRow> visible) {
    final scheme = Theme.of(context).colorScheme;
    final compact = MediaQuery.sizeOf(context).width < 600;
    final row = selectedRow;
    final notificationRow =
        _selection == _TableSelection.row || _selection == _TableSelection.cell
            ? row
            : null;
    final column = selectedColumn;
    final rowNumber = row == null ? 0 : current.rows.indexOf(row) + 1;
    final columnNumber =
        column == null ? 0 : current.columns.indexOf(column) + 1;

    Widget action(String label, IconData icon, VoidCallback? callback) =>
        OutlinedButton.icon(
          onPressed: callback,
          style:
              label.startsWith('Delete')
                  ? OutlinedButton.styleFrom(
                    foregroundColor: scheme.error,
                    side: BorderSide(
                      color: scheme.error.withValues(alpha: .45),
                    ),
                  )
                  : null,
          icon: Icon(icon, size: 17),
          label: Text(label),
        );

    Widget menu(
      String label,
      IconData icon,
      List<PopupMenuEntry<String>> items,
      ValueChanged<String> onSelected,
    ) => PopupMenuButton<String>(
      tooltip: label,
      onSelected: onSelected,
      itemBuilder: (_) => items,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Text(label),
            const SizedBox(width: 6),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );

    String? selectionLabel;
    String? selectionHelp;
    final selectedActions = <Widget>[];
    switch (_selection) {
      case _TableSelection.none:
        break;
      case _TableSelection.row:
        if (row != null) {
          selectionLabel = 'Row $rowNumber selected';
          selectionHelp = 'Manage this row';
          selectedActions.addAll([
            action('Duplicate Row', Icons.copy_all_outlined, _duplicateRow),
            action('Row color', Icons.format_color_fill_outlined, _colorRow),
            if (row.notifyAt != null)
              action(
                'Clear notification',
                Icons.alarm_off_outlined,
                _clearReminder,
              ),
            action('Delete Row', Icons.delete_outline, _deleteRow),
          ]);
        }
      case _TableSelection.column:
        if (column != null) {
          selectionLabel = 'Column $columnNumber selected';
          selectionHelp =
              column.label.isEmpty ? 'Unnamed column' : column.label;
          selectedActions.addAll([
            action(
              'Name Header',
              Icons.edit_note_outlined,
              () => _editHeader(column),
            ),
            action('Column color', Icons.palette_outlined, _colorColumn),
            action(
              'Sort column',
              Icons.sort_by_alpha_outlined,
              () => _sortColumn(column),
            ),
            action('Delete Column', Icons.delete_outline, _deleteColumn),
          ]);
        }
      case _TableSelection.cell:
        if (row != null && column != null) {
          selectionLabel = 'Row $rowNumber · Column $columnNumber';
          selectionHelp = column.label.isEmpty ? 'Selected cell' : column.label;
          selectedActions.addAll([
            action('Next row', Icons.arrow_downward, _goToNextRow),
            action(
              'Edit cell',
              Icons.edit_outlined,
              () => _editCell(row, column),
            ),
            action('Copy', Icons.content_copy_outlined, _copy),
            action('Paste', Icons.content_paste_outlined, _paste),
          ]);
        }
    }

    return Material(
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.table_chart_outlined,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                SizedBox(
                  width: math.min(
                    280,
                    math.max(120, MediaQuery.sizeOf(context).width - 110),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        current.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        '${current.rows.length} rows · ${current.columns.length} columns',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                action(
                  compact ? 'Tables' : 'All tables',
                  Icons.arrow_back,
                  () => widget.onSelectTable(null),
                ),
                menu(
                  compact ? 'Options' : 'Table options',
                  Icons.more_horiz,
                  const [
                    PopupMenuItem(value: 'rename', child: Text('Rename table')),
                    PopupMenuItem(value: 'delete', child: Text('Delete table')),
                  ],
                  (value) {
                    if (value == 'rename') _renameTable();
                    if (value == 'delete') _deleteTable();
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _addRow,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Row'),
                ),
                action('Add Column', Icons.view_column_outlined, _addColumn),
                Tooltip(
                  message:
                      'Choose a row or cell first. Due notifications '
                      'appear on the dashboard after saving.',
                  child: action(
                    notificationRow?.notifyAt == null
                        ? 'Set notification'
                        : 'Edit notification',
                    Icons.notifications_active_outlined,
                    notificationRow == null
                        ? () => widget.message(
                          'Select a row number or cell first, then set its notification.',
                        )
                        : _setReminder,
                  ),
                ),
                SizedBox(
                  width: compact ? MediaQuery.sizeOf(context).width - 40 : 230,
                  child: TextField(
                    controller: search,
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search, size: 20),
                      hintText: 'Search this table',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                action(
                  showFilter ? 'Hide filter' : 'Filter',
                  Icons.filter_alt_outlined,
                  () => setState(() => showFilter = !showFilter),
                ),
                menu(
                  compact ? 'Files' : 'Import / Export',
                  Icons.file_present_outlined,
                  const [
                    PopupMenuItem(value: 'import', child: Text('Import CSV')),
                    PopupMenuItem(value: 'export', child: Text('Export CSV')),
                  ],
                  (value) {
                    if (value == 'import') _importCsv();
                    if (value == 'export') _exportCsv();
                  },
                ),
                FilledButton.icon(
                  onPressed: saving ? null : _save,
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: Text(saving ? 'Saving…' : 'Save'),
                ),
                Text(
                  dirty ? '● Unsaved changes' : 'All changes saved',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: dirty ? scheme.primary : scheme.onSurfaceVariant,
                    fontWeight: dirty ? FontWeight.w600 : null,
                  ),
                ),
              ],
            ),
            if (showFilter) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Show rows where'),
                  SizedBox(
                    width: 180,
                    child: DropdownButtonFormField<String>(
                      value: filterColumnId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Column',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (
                          var index = 0;
                          index < current.columns.length;
                          index++
                        )
                          DropdownMenuItem(
                            value: current.columns[index].id,
                            child: Text(
                              current.columns[index].label.isEmpty
                                  ? 'Unnamed ${index + 1}'
                                  : current.columns[index].label,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged:
                          (value) => setState(() => filterColumnId = value),
                    ),
                  ),
                  SizedBox(
                    width: 190,
                    child: TextField(
                      controller: filter,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Contains text',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  Text('${visible.length} of ${current.rows.length} rows'),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color:
                    selectionLabel == null
                        ? scheme.surfaceContainerLowest
                        : scheme.primaryContainer.withValues(alpha: .3),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child:
                  selectionLabel == null
                      ? Text(
                        'Tap a cell to type. Use the three-dot menu beside a '
                        'row number for color and notifications.',
                        style: Theme.of(context).textTheme.bodySmall,
                      )
                      : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Icon(
                            _selection == _TableSelection.row
                                ? Icons.table_rows_outlined
                                : _selection == _TableSelection.column
                                ? Icons.view_column_outlined
                                : Icons.crop_square_outlined,
                            size: 19,
                            color: scheme.primary,
                          ),
                          Text(
                            selectionLabel,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          if (selectionHelp != null)
                            Text(
                              selectionHelp,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          if (compact) ...[
                            if (_selection == _TableSelection.cell)
                              action(
                                'Next row',
                                Icons.arrow_downward,
                                _goToNextRow,
                              ),
                            menu(
                              _selection == _TableSelection.row
                                  ? 'Row actions'
                                  : _selection == _TableSelection.column
                                  ? 'Column actions'
                                  : 'Cell actions',
                              Icons.more_horiz,
                              _selectionMenuItems(row),
                              _runSelectionAction,
                            ),
                          ] else
                            ...selectedActions,
                          if (_selection == _TableSelection.row &&
                              row?.notifyAt != null)
                            Text(
                              'Notification: ${_formatReminder(row!.notifyAt)} '
                              '· appears on Dashboard when due',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
            ),
          ],
        ),
      ),
    );
  }

  static const _rowHeaderWidth = 88.0;

  double _columnWidth(NamedTable current, double available) =>
      math.max(190, (available - _rowHeaderWidth) / current.columns.length);

  double _dataRowHeight(NamedTableRow row) {
    var lines = 1;
    for (final value in row.cells.values) {
      lines = math.max(lines, '\n'.allMatches(value).length + 1);
    }
    return math.max(52, 24 + 24.0 * math.min(lines, 8));
  }

  Color _cellFill(NamedTableRow row, NamedTableColumn column, Color fallback) {
    final rowColor = _decodeColor(row.color);
    final columnColor = _decodeColor(column.color);
    if (rowColor != null && columnColor != null) {
      return Color.alphaBlend(columnColor.withValues(alpha: .52), rowColor);
    }
    return columnColor ?? rowColor ?? fallback;
  }

  void _sortColumn(NamedTableColumn column) {
    _finishInlineEdit();
    setState(() {
      selectedColumnId = column.id;
      ascending = sortColumnId == column.id ? !ascending : true;
      sortColumnId = column.id;
    });
  }

  Widget _grid(NamedTable current, List<NamedTableRow> visible) {
    const rowHeight = 52.0;
    final scheme = Theme.of(context).colorScheme;
    final width = _rowHeaderWidth + current.columns.length * 190.0;
    return LayoutBuilder(
      builder:
          (context, constraints) => Scrollbar(
            controller: horizontal,
            thumbVisibility: true,
            notificationPredicate:
                (notification) => notification.metrics.axis == Axis.horizontal,
            child: SingleChildScrollView(
              controller: horizontal,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: math.max(width, constraints.maxWidth),
                child: Column(
                  children: [
                    Container(
                      height: rowHeight,
                      color: scheme.surfaceContainerHighest.withValues(
                        alpha: .65,
                      ),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: _rowHeaderWidth,
                            child: Center(
                              child: Text(
                                'ROW',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                          for (
                            var index = 0;
                            index < current.columns.length;
                            index++
                          )
                            SizedBox(
                              width: _columnWidth(
                                current,
                                constraints.maxWidth,
                              ),
                              child: InkWell(
                                onTap: () {
                                  _finishInlineEdit();
                                  setState(() {
                                    selectedColumnId =
                                        current.columns[index].id;
                                    _selection = _TableSelection.column;
                                  });
                                },
                                onLongPress:
                                    () => _editHeader(current.columns[index]),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color:
                                        _selection == _TableSelection.column &&
                                                selectedColumnId ==
                                                    current.columns[index].id
                                            ? scheme.primaryContainer
                                                .withValues(alpha: .7)
                                            : _decodeColor(
                                              current.columns[index].color,
                                            ),
                                    border: Border(
                                      right: BorderSide(
                                        color: scheme.outlineVariant,
                                      ),
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            current.columns[index].label.isEmpty
                                                ? 'Name column ${index + 1}'
                                                : current.columns[index].label,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        PopupMenuButton<String>(
                                          tooltip: 'Column actions',
                                          icon: const Icon(
                                            Icons.more_vert,
                                            size: 17,
                                          ),
                                          padding: EdgeInsets.zero,
                                          onSelected: (action) {
                                            _finishInlineEdit();
                                            setState(() {
                                              selectedColumnId =
                                                  current.columns[index].id;
                                              _selection =
                                                  _TableSelection.column;
                                            });
                                            switch (action) {
                                              case 'name':
                                                _editHeader(
                                                  current.columns[index],
                                                );
                                              case 'sort':
                                                _sortColumn(
                                                  current.columns[index],
                                                );
                                              case 'color':
                                                _colorColumn();
                                              case 'delete':
                                                _deleteColumn();
                                            }
                                          },
                                          itemBuilder:
                                              (_) => const [
                                                PopupMenuItem(
                                                  value: 'name',
                                                  child: Text('Name header'),
                                                ),
                                                PopupMenuItem(
                                                  value: 'sort',
                                                  child: Text('Sort column'),
                                                ),
                                                PopupMenuItem(
                                                  value: 'color',
                                                  child: Text('Color column'),
                                                ),
                                                PopupMenuItem(
                                                  value: 'delete',
                                                  child: Text('Delete column'),
                                                ),
                                              ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Scrollbar(
                        controller: vertical,
                        thumbVisibility: true,
                        child: ListView.builder(
                          controller: vertical,
                          itemExtentBuilder:
                              (index, _) =>
                                  index < visible.length
                                      ? _dataRowHeight(visible[index])
                                      : null,
                          itemCount: visible.length,
                          itemBuilder: (context, index) {
                            final row = visible[index];
                            final dataRowHeight = _dataRowHeight(row);
                            return ColoredBox(
                              color:
                                  index.isEven
                                      ? scheme.surface
                                      : scheme.surfaceContainerLowest,
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: _rowHeaderWidth,
                                    height: dataRowHeight,
                                    child: InkWell(
                                      onTap: () => _selectRowForAction(row),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color:
                                              _selection ==
                                                          _TableSelection.row &&
                                                      selectedRowId == row.id
                                                  ? scheme.primaryContainer
                                                  : _decodeColor(row.color) ??
                                                      scheme
                                                          .surfaceContainerHighest,
                                          border: Border(
                                            bottom: BorderSide(
                                              color: scheme.outlineVariant,
                                            ),
                                            right: BorderSide(
                                              color: scheme.outlineVariant,
                                            ),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            SizedBox(
                                              width: 32,
                                              child: Text(
                                                '${index + 1}',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontWeight:
                                                      _selection ==
                                                                  _TableSelection
                                                                      .row &&
                                                              selectedRowId ==
                                                                  row.id
                                                          ? FontWeight.w700
                                                          : FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                            PopupMenuButton<String>(
                                              tooltip:
                                                  'Row ${index + 1} actions',
                                              icon: Icon(
                                                Icons.more_vert,
                                                color:
                                                    row.notifyAt == null
                                                        ? scheme
                                                            .onSurfaceVariant
                                                        : scheme.primary,
                                              ),
                                              padding: EdgeInsets.zero,
                                              onSelected: (action) {
                                                _selectRowForAction(row);
                                                switch (action) {
                                                  case 'color':
                                                    _colorRow();
                                                  case 'notify':
                                                    _setReminder();
                                                  case 'clear-notification':
                                                    _clearReminder();
                                                  case 'duplicate':
                                                    _duplicateRow();
                                                  case 'delete':
                                                    _deleteRow();
                                                }
                                              },
                                              itemBuilder:
                                                  (_) => [
                                                    PopupMenuItem(
                                                      key: ValueKey(
                                                        'row-action-color-${row.id}',
                                                      ),
                                                      value: 'color',
                                                      child: const Text(
                                                        'Color row',
                                                      ),
                                                    ),
                                                    PopupMenuItem(
                                                      key: ValueKey(
                                                        'row-action-notification-${row.id}',
                                                      ),
                                                      value: 'notify',
                                                      child: Text(
                                                        row.notifyAt == null
                                                            ? 'Set notification'
                                                            : 'Edit notification',
                                                      ),
                                                    ),
                                                    if (row.notifyAt != null)
                                                      const PopupMenuItem(
                                                        value:
                                                            'clear-notification',
                                                        child: Text(
                                                          'Clear notification',
                                                        ),
                                                      ),
                                                    const PopupMenuDivider(),
                                                    const PopupMenuItem(
                                                      value: 'duplicate',
                                                      child: Text(
                                                        'Duplicate row',
                                                      ),
                                                    ),
                                                    const PopupMenuItem(
                                                      value: 'delete',
                                                      child: Text('Delete row'),
                                                    ),
                                                  ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  for (final column in current.columns)
                                    SizedBox(
                                      width: _columnWidth(
                                        current,
                                        constraints.maxWidth,
                                      ),
                                      height: dataRowHeight,
                                      child: InkWell(
                                        key: ValueKey(
                                          'table-cell-${row.id}-${column.id}',
                                        ),
                                        onTap:
                                            () => _startInlineEdit(row, column),
                                        child: Container(
                                          alignment: Alignment.centerLeft,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                _selection ==
                                                            _TableSelection
                                                                .cell &&
                                                        selectedRowId ==
                                                            row.id &&
                                                        selectedColumnId ==
                                                            column.id
                                                    ? Color.alphaBlend(
                                                      scheme.primary.withValues(
                                                        alpha: .06,
                                                      ),
                                                      _cellFill(
                                                        row,
                                                        column,
                                                        index.isEven
                                                            ? scheme.surface
                                                            : scheme
                                                                .surfaceContainerLowest,
                                                      ),
                                                    )
                                                    : _cellFill(
                                                      row,
                                                      column,
                                                      index.isEven
                                                          ? scheme.surface
                                                          : scheme
                                                              .surfaceContainerLowest,
                                                    ),
                                            border: Border(
                                              right: BorderSide(
                                                color:
                                                    editingRowId == row.id &&
                                                            editingColumnId ==
                                                                column.id
                                                        ? scheme.primary
                                                        : scheme.outlineVariant,
                                              ),
                                              bottom: BorderSide(
                                                color:
                                                    editingRowId == row.id &&
                                                            editingColumnId ==
                                                                column.id
                                                        ? scheme.primary
                                                        : scheme.outlineVariant,
                                              ),
                                              left:
                                                  _selection ==
                                                              _TableSelection
                                                                  .cell &&
                                                          selectedRowId ==
                                                              row.id &&
                                                          selectedColumnId ==
                                                              column.id
                                                      ? BorderSide(
                                                        color: scheme.primary,
                                                        width: 1,
                                                      )
                                                      : BorderSide.none,
                                              top:
                                                  editingRowId == row.id &&
                                                          editingColumnId ==
                                                              column.id
                                                      ? BorderSide(
                                                        color: scheme.primary,
                                                      )
                                                      : BorderSide.none,
                                            ),
                                          ),
                                          child:
                                              editingRowId == row.id &&
                                                      editingColumnId ==
                                                          column.id
                                                  ? Focus(
                                                    onKeyEvent:
                                                        (_, event) =>
                                                            _handleCellKey(
                                                              event,
                                                              row,
                                                              column,
                                                            ),
                                                    child: TextField(
                                                      key: const ValueKey(
                                                        'table-cell-editor',
                                                      ),
                                                      controller: cellEditor,
                                                      focusNode: cellFocus,
                                                      minLines: null,
                                                      maxLines: null,
                                                      expands: true,
                                                      keyboardType:
                                                          TextInputType
                                                              .multiline,
                                                      textInputAction:
                                                          TextInputAction
                                                              .newline,
                                                      textAlignVertical:
                                                          TextAlignVertical.top,
                                                      style:
                                                          Theme.of(context)
                                                              .textTheme
                                                              .bodyMedium,
                                                      inputFormatters: [
                                                        LengthLimitingTextInputFormatter(
                                                          10000,
                                                        ),
                                                      ],
                                                      decoration:
                                                          const InputDecoration(
                                                            isCollapsed: true,
                                                            border:
                                                                InputBorder
                                                                    .none,
                                                            enabledBorder:
                                                                InputBorder
                                                                    .none,
                                                            focusedBorder:
                                                                InputBorder
                                                                    .none,
                                                            contentPadding:
                                                                EdgeInsets.zero,
                                                          ),
                                                      onChanged:
                                                          (value) =>
                                                              _updateInlineCell(
                                                                row,
                                                                column,
                                                                value,
                                                              ),
                                                    ),
                                                  )
                                                  : Text(
                                                    row.cells[column.id] ?? '',
                                                    maxLines: 8,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style:
                                                        Theme.of(
                                                          context,
                                                        ).textTheme.bodyMedium,
                                                  ),
                                        ),
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
    if (widget.selectedTableId == null) return _landing();
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error!, textAlign: TextAlign.center),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    final current = table;
    if (current == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final visible = _visibleRows(current);
    return Column(
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .72,
          ),
          child: SingleChildScrollView(child: _toolbar(current, visible)),
        ),
        const Divider(height: 1),
        Expanded(child: _grid(current, visible)),
      ],
    );
  }
}

class _CreateSpec {
  const _CreateSpec(this.name, this.rows, this.columns, this.headers);
  final String name;
  final int rows;
  final int columns;
  final List<String> headers;
}

class _CreateTableDialog extends StatefulWidget {
  const _CreateTableDialog();
  @override
  State<_CreateTableDialog> createState() => _CreateTableDialogState();
}

class _CreateTableDialogState extends State<_CreateTableDialog> {
  final name = TextEditingController();
  final rows = TextEditingController(text: '5');
  final columns = TextEditingController(text: '3');
  final headers = <TextEditingController>[];
  String? error;

  @override
  void initState() {
    super.initState();
    _ensureHeaders(3);
  }

  void _ensureHeaders(int count) {
    while (headers.length < count) {
      headers.add(TextEditingController());
    }
  }

  @override
  void dispose() {
    name.dispose();
    rows.dispose();
    columns.dispose();
    for (final controller in headers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final rowCount = int.tryParse(rows.text.trim());
    final columnCount = int.tryParse(columns.text.trim());
    if (name.text.trim().isEmpty ||
        name.text.trim().length > 80 ||
        rowCount == null ||
        rowCount < 0 ||
        rowCount > 5000 ||
        columnCount == null ||
        columnCount < 1 ||
        columnCount > 50) {
      setState(() => error = 'Enter a name, 0–5000 rows and 1–50 columns.');
      return;
    }
    _ensureHeaders(columnCount);
    final labels =
        headers.take(columnCount).map((item) => item.text.trim()).toList();
    if (labels.any((label) => label.length > 80)) {
      setState(() => error = 'Headings must be at most 80 characters.');
      return;
    }
    Navigator.pop(
      context,
      _CreateSpec(name.text.trim(), rowCount, columnCount, labels),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = (int.tryParse(columns.text.trim()) ?? 0).clamp(0, 50);
    _ensureHeaders(count);
    return AlertDialog(
      title: const Text('Create your table'),
      content: SizedBox(
        width: 450,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: name,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'Name shown in sidebar',
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: rows,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'Rows'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: columns,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(labelText: 'Columns'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Name your headers (or leave blank and name them later).',
              ),
              const SizedBox(height: 8),
              for (var index = 0; index < count; index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    controller: headers[index],
                    maxLength: 80,
                    decoration: InputDecoration(
                      labelText: 'Header ${index + 1}',
                    ),
                  ),
                ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Create table')),
      ],
    );
  }
}

class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    required this.initial,
    required this.multiline,
  });
  final String title;
  final String initial;
  final bool multiline;
  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
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
    content: SizedBox(
      width: 410,
      child: TextField(
        controller: controller,
        autofocus: true,
        maxLines: widget.multiline ? 5 : 1,
        decoration: const InputDecoration(hintText: 'Enter value'),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, controller.text),
        child: const Text('OK'),
      ),
    ],
  );
}
