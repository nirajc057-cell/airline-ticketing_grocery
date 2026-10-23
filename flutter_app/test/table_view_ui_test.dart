import 'package:aerodesk_client/table_view_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('page window clamps pages and handles empty tables', () {
    final first = tablePageWindow(71, 0, 10);
    expect(
      (first.page, first.pageCount, first.start, first.end),
      (0, 8, 0, 10),
    );
    final last = tablePageWindow(71, 99, 10);
    expect((last.page, last.pageCount, last.start, last.end), (7, 8, 70, 71));
    final empty = tablePageWindow(0, 3, 10);
    expect((empty.page, empty.pageCount, empty.start, empty.end), (0, 1, 0, 0));
  });

  testWidgets('pagination shows ranges and changes page size', (tester) async {
    var page = 0;
    var pageSize = 10;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder:
                (context, update) => TablePagination(
                  total: 71,
                  page: page,
                  pageSize: pageSize,
                  onPageChanged: (value) => update(() => page = value),
                  onPageSizeChanged:
                      (value) => update(() {
                        page = 0;
                        pageSize = value;
                      }),
                ),
          ),
        ),
      ),
    );
    expect(find.text('Showing 1 to 10 of 71 entries'), findsOneWidget);
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(find.text('Showing 11 to 20 of 71 entries'), findsOneWidget);
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('25').last);
    await tester.pumpAndSettle();
    expect(find.text('Showing 1 to 25 of 71 entries'), findsOneWidget);
  });
}
