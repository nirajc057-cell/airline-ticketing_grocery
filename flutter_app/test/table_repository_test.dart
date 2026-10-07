import 'package:flutter_test/flutter_test.dart';
import 'package:aerodesk_client/api.dart';
import 'package:aerodesk_client/table_model.dart';
import 'package:aerodesk_client/table_repository.dart';

class _FakeTableApi extends ApiClient {
  String? lastPath;
  Map<String, dynamic>? lastBody;

  @override
  Future<dynamic> get(String path) async => switch (path) {
    '/api/bookings' => <Object>[],
    '/api/bookings/table-columns' => <Object>[],
    '/api/bookings/table-setup' => {'initialized': true},
    '/api/bookings/table-drafts' => [
      {
        'id': 'D-1',
        'values': {'customerName': 'Jane'},
      },
    ],
    _ => throw StateError(path),
  };

  @override
  Future<dynamic> post(String path, Object body) async {
    lastPath = path;
    lastBody = Map<String, dynamic>.from(body as Map);
    if (path == '/api/bookings') {
      return {'id': 'BK-1', ...lastBody!};
    }
    return {'id': 'D-2', 'values': lastBody};
  }

  @override
  Future<dynamic> patch(String path, Object body) async {
    lastPath = path;
    lastBody = Map<String, dynamic>.from(body as Map);
    return {'id': 'D-1', 'values': lastBody};
  }
}

void main() {
  test('loads saved draft rows alongside records', () async {
    final repository = TableRepository(_FakeTableApi(), TableKind.bookings);
    final snapshot = await repository.load();
    expect(snapshot.initialized, isTrue);
    expect(snapshot.rows.single.draftId, 'D-1');
    expect(snapshot.rows.single.values['customerName'], 'Jane');
  });

  test('incomplete draft is saved without creating a booking', () async {
    final api = _FakeTableApi();
    final repository = TableRepository(api, TableKind.bookings);
    final row = SpreadsheetRow(
      {'customerName': 'Jane'},
      isNew: true,
      draftId: 'D-1',
    );
    final result = await repository.saveRow(
      row,
      TableKind.bookings.baseColumns,
    );
    expect(result.isNew, isTrue);
    expect(api.lastPath, '/api/bookings/table-drafts/D-1');
  });

  test('complete draft becomes a booking', () async {
    final api = _FakeTableApi();
    final repository = TableRepository(api, TableKind.bookings);
    final row = SpreadsheetRow(
      {
        'reference': 'BK-1',
        'customerName': 'Jane',
        'origin': 'KTM',
        'destination': 'DXB',
        'total': 100,
      },
      isNew: true,
      draftId: 'D-1',
    );
    final result = await repository.saveRow(
      row,
      TableKind.bookings.baseColumns,
    );
    expect(result.isNew, isFalse);
    expect(api.lastPath, '/api/bookings');
    expect(api.lastBody!['tableDraftId'], 'D-1');
  });
}
