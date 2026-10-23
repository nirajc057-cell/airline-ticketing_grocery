import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class RecordPrintField {
  const RecordPrintField(this.label, this.value);

  final String label;
  final String value;
}

class RecordPrintData {
  const RecordPrintData({
    required this.brand,
    required this.title,
    required this.reference,
    required this.fields,
  });

  final String brand;
  final String title;
  final String reference;
  final List<RecordPrintField> fields;
}

bool isSensitivePrintField(String key) {
  final normalized = key.toLowerCase();
  final condensed = normalized.replaceAll(RegExp(r'[\s_-]'), '');
  return normalized.contains('password') ||
      normalized.contains('token') ||
      normalized.contains('secret') ||
      condensed.contains('apikey');
}

Future<Uint8List> buildRecordPdf(
  RecordPrintData record,
  PdfPageFormat format, {
  pw.Font? font,
  pw.Font? devanagariFont,
  pw.Font? symbolsFont,
}) async {
  final document = pw.Document(
    title: '${record.brand} ${record.title} ${record.reference}',
    author: record.brand,
  );
  final accent = PdfColor.fromHex(
    record.brand == 'FreshMart' ? '#087C64' : '#5142BE',
  );
  document.addPage(
    pw.MultiPage(
      pageFormat: format,
      margin: const pw.EdgeInsets.fromLTRB(40, 42, 40, 40),
      theme: pw.ThemeData.withFont(
        base: font ?? pw.Font.helvetica(),
        bold: font ?? pw.Font.helveticaBold(),
        fontFallback: [
          if (devanagariFont != null) devanagariFont,
          if (symbolsFont != null) symbolsFont,
        ],
      ),
      footer:
          (context) => pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            ),
          ),
      build:
          (context) => [
            pw.Text(
              record.brand,
              style: pw.TextStyle(
                fontSize: 22,
                fontWeight: pw.FontWeight.bold,
                color: accent,
              ),
            ),
            pw.SizedBox(height: 18),
            pw.Text(
              record.title,
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              record.reference,
              style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 18),
            ...record.fields.map(
              (field) => pw.Container(
                padding: const pw.EdgeInsets.symmetric(vertical: 8),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: PdfColors.grey300),
                  ),
                ),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.SizedBox(
                      width: 125,
                      child: pw.Text(
                        field.label,
                        style: const pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Text(
                        field.value,
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
    ),
  );
  return document.save();
}

Future<void> printRecord(RecordPrintData record) async {
  // These fonts are bundled, so names print even without font downloads.
  final fonts = await Future.wait([
    PdfGoogleFonts.notoSansRegular(),
    PdfGoogleFonts.notoSansDevanagariRegular(),
    PdfGoogleFonts.notoSansSymbolsRegular(),
  ]);
  final safeName = '${record.brand}-${record.title}-${record.reference}'
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  await Printing.layoutPdf(
    name: '$safeName.pdf',
    onLayout:
        (format) => buildRecordPdf(
          record,
          format,
          font: fonts[0],
          devanagariFont: fonts[1],
          symbolsFont: fonts[2],
        ),
  );
}
