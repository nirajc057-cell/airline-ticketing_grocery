import 'dart:convert';

import 'package:aerodesk_client/record_print.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('record summaries build PDFs for AeroDesk and FreshMart', () async {
    final latin = pw.Font.ttf(
      await rootBundle.load('google_fonts/NotoSans-Regular.ttf'),
    );
    final devanagari = pw.Font.ttf(
      await rootBundle.load('google_fonts/NotoSansDevanagari-Regular.ttf'),
    );
    final symbols = pw.Font.ttf(
      await rootBundle.load('google_fonts/NotoSansSymbols-Regular.ttf'),
    );

    for (final brand in ['AeroDesk', 'FreshMart']) {
      final bytes = await buildRecordPdf(
        RecordPrintData(
          brand: brand,
          title: brand == 'AeroDesk' ? 'Booking summary' : 'Product record',
          reference: brand == 'AeroDesk' ? 'BK-123' : 'PROD-123',
          fields: const [
            RecordPrintField('Status', 'On hold'),
            RecordPrintField('Route', 'KTM → DXB'),
            RecordPrintField('Customer', 'निश्चल'),
          ],
        ),
        PdfPageFormat.a4,
        font: latin,
        devanagariFont: devanagari,
        symbolsFont: symbols,
      );

      expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
      expect(bytes.length, greaterThan(1000));
    }
  });

  test('sensitive values are excluded from printable fields', () {
    expect(isSensitivePrintField('passwordHash'), isTrue);
    expect(isSensitivePrintField('accessToken'), isTrue);
    expect(isSensitivePrintField('API_KEY'), isTrue);
    expect(isSensitivePrintField('secret'), isTrue);
    expect(isSensitivePrintField('customerName'), isFalse);
  });
}
