import 'dart:io';
import 'package:flutter/services.dart';
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class ExportService {
  // ૧. Excel / CSV ફાઇલ એક્સપોર્ટ (UTF-8 BOM સાથે)
  static Future<void> exportToCSV(List<Map<dynamic, dynamic>> transactions) async {
    List<List<dynamic>> rows = [
      ['તારીખ (Date)', 'વિગત (Title)', 'કેટેગરી (Category)', 'પ્રકાર (Type)', 'ખાતું (Account)', 'રકમ (Amount Rs)']
    ];

    for (var tx in transactions) {
      final date = DateTime.parse(tx['date']);
      final formattedDate = DateFormat('dd/MM/yyyy HH:mm').format(date);
      rows.add([
        formattedDate,
        tx['title'],
        tx['categoryName'],
        tx['categoryEffect'],
        tx['accountName'] ?? '',
        tx['amount'],
      ]);
    }

    String csvContent = const ListToCsvConverter().convert(rows);
    final utf8CsvWithBom = '\uFEFF$csvContent'; // Excel માં ગુજરાતી અક્ષરો ઓળખવા માટે BOM

    final directory = await getTemporaryDirectory();
    final path = "${directory.path}/Finance_Report_${DateTime.now().millisecondsSinceEpoch}.csv";
    final file = File(path);
    await file.writeAsString(utf8CsvWithBom);

    await Share.shareXFiles([XFile(path)], text: 'નાણાકીય હિસાબ રિપોર્ટ (CSV/Excel)');
  }

  // ૨. સામાન્ય નાણાકીય સ્ટેટમેન્ટ PDF એક્સપોર્ટ (જોડ્યાક્ષર સપોર્ટ સાથે)
  static Future<void> exportToPDF(
    List<Map<dynamic, dynamic>> transactions,
    double totalIncome,
    double totalExpense,
    double assetGain,
    double netSavings,
    String filterName,
  ) async {
    final pdf = pw.Document();

    // ગુજરાતી ફોન્ટ્સ લોડિંગ
    final fontData = await rootBundle.load('assets/fonts/NotoSansGujarati-Regular.ttf');
    final ttfRegular = pw.Font.ttf(fontData);

    pw.Font ttfBold = ttfRegular;
    try {
      final boldData = await rootBundle.load('assets/fonts/NotoSansGujarati-Bold.ttf');
      ttfBold = pw.Font.ttf(boldData);
    } catch (_) {}

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        theme: pw.ThemeData.withFont(base: ttfRegular, bold: ttfBold),
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('નાણાકીય સ્ટેટમેન્ટ રિપોર્ટ', style: pw.TextStyle(fontSize: 18, font: ttfBold)),
                  pw.Text(DateFormat('dd-MM-yyyy HH:mm').format(DateTime.now()), style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text('સમયગાળો: $filterName', style: pw.TextStyle(fontSize: 11, font: ttfRegular)),
            pw.SizedBox(height: 12),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _buildPdfSummaryBox('કુલ આવક', totalIncome, PdfColors.green700, ttfRegular, ttfBold),
                _buildPdfSummaryBox('કુલ ખર્ચ', totalExpense, PdfColors.red700, ttfRegular, ttfBold),
                _buildPdfSummaryBox('કુલ રોકાણ', assetGain, PdfColors.blue700, ttfRegular, ttfBold),
                _buildPdfSummaryBox('ચોખ્ખી બચત', netSavings, PdfColors.teal700, ttfRegular, ttfBold),
              ],
            ),
            pw.SizedBox(height: 16),
            pw.TableHelper.fromTextArray(
              headers: ['તારીખ', 'વિગત', 'કેટેગરી', 'ખાતું', 'રકમ (₹)'],
              data: transactions.map((tx) {
                final date = DateTime.parse(tx['date']);
                return [
                  DateFormat('dd/MM/yyyy').format(date),
                  tx['title'].toString(),
                  tx['categoryName'].toString(),
                  (tx['accountName'] ?? '').toString(),
                  (tx['amount'] as num).toStringAsFixed(2),
                ];
              }).toList(),
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              headerStyle: pw.TextStyle(color: PdfColors.white, font: ttfBold, fontSize: 10),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.teal800),
              cellStyle: pw.TextStyle(font: ttfRegular, fontSize: 9),
              cellHeight: 22,
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.centerLeft,
                3: pw.Alignment.centerLeft,
                4: pw.Alignment.centerRight,
              },
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Financial_Report_${DateFormat('ddMMyyyy').format(DateTime.now())}.pdf',
    );
  }

  // ૩. બજેટ આયોજન રિપોર્ટ PDF એક્સપોર્ટ
  static Future<void> exportBudgetPDF({
    required String periodName,
    required List<Map<String, dynamic>> budgetItems,
    required double totalBudget,
    required double totalActual,
  }) async {
    final pdf = pw.Document();

    final fontData = await rootBundle.load('assets/fonts/NotoSansGujarati-Regular.ttf');
    final ttfRegular = pw.Font.ttf(fontData);

    pw.Font ttfBold = ttfRegular;
    try {
      final boldData = await rootBundle.load('assets/fonts/NotoSansGujarati-Bold.ttf');
      ttfBold = pw.Font.ttf(boldData);
    } catch (_) {}

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        theme: pw.ThemeData.withFont(base: ttfRegular, bold: ttfBold),
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('બજેટ આયોજન અને સરખામણી રિપોર્ટ', style: pw.TextStyle(fontSize: 18, font: ttfBold)),
                  pw.Text(DateFormat('dd-MM-yyyy HH:mm').format(DateTime.now()), style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text('બજેટ ગાળો: $periodName', style: pw.TextStyle(fontSize: 11, font: ttfRegular)),
            pw.SizedBox(height: 12),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _buildPdfSummaryBox('કુલ લક્ષ્યાંક બજેટ', totalBudget, PdfColors.blue700, ttfRegular, ttfBold),
                _buildPdfSummaryBox('કુલ વાસ્તવિક ખર્ચ/ઉપયોગ', totalActual, PdfColors.orange700, ttfRegular, ttfBold),
                _buildPdfSummaryBox(
                  totalActual > totalBudget ? 'ઓવર બજેટ' : 'બાકી બચત',
                  (totalBudget - totalActual).abs(),
                  totalActual > totalBudget ? PdfColors.red700 : PdfColors.green700,
                  ttfRegular,
                  ttfBold,
                ),
              ],
            ),
            pw.SizedBox(height: 16),
            pw.TableHelper.fromTextArray(
              headers: ['કેટેગરી', 'લક્ષ્યાંક બજેટ (₹)', 'વાસ્તવિક ખર્ચ (₹)', 'તફાવત (₹)', 'સ્થિતિ'],
              data: budgetItems.map((item) {
                final target = (item['target'] as num).toDouble();
                final actual = (item['actual'] as num).toDouble();
                final diff = target - actual;
                final isOver = actual > target;

                return [
                  item['name'].toString(),
                  target.toStringAsFixed(2),
                  actual.toStringAsFixed(2),
                  diff.toStringAsFixed(2),
                  isOver ? 'બજેટ બહાર (Over)' : 'બજેટમાં (Within)',
                ];
              }).toList(),
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              headerStyle: pw.TextStyle(color: PdfColors.white, font: ttfBold, fontSize: 10),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.teal800),
              cellStyle: pw.TextStyle(font: ttfRegular, fontSize: 9),
              cellHeight: 22,
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerRight,
                2: pw.Alignment.centerRight,
                3: pw.Alignment.centerRight,
                4: pw.Alignment.center,
              },
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Budget_Report_${DateFormat('ddMMyyyy').format(DateTime.now())}.pdf',
    );
  }

  static pw.Widget _buildPdfSummaryBox(
    String title,
    double amount,
    PdfColor color,
    pw.Font fontRegular,
    pw.Font fontBold,
  ) {
    return pw.Container(
      width: 110,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: color, width: 1),
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Column(
        children: [
          pw.Text(title, style: pw.TextStyle(fontSize: 10, font: fontRegular)),
          pw.SizedBox(height: 4),
          pw.Text('Rs. ${amount.toStringAsFixed(0)}', style: pw.TextStyle(fontSize: 12, font: fontBold, color: color)),
        ],
      ),
    );
  }
}
