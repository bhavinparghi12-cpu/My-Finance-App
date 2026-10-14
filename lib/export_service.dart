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
  // Excel / CSV ફાઇલ - UTF-8 BOM સપોર્ટ સાથે જેથી ગુજરાતી અક્ષરો એક્સેલમાં સ્પષ્ટ વંચાય
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
    
    // '\uFEFF' (Byte Order Mark) ઉમેરવાથી Microsoft Excel ગુજરાતી યુનિકોડ ઓળખી લેશે
    final utf8CsvWithBom = '\uFEFF$csvContent';

    final directory = await getTemporaryDirectory();
    final path = "${directory.path}/Finance_Report_${DateTime.now().millisecondsSinceEpoch}.csv";
    final file = File(path);
    await file.writeAsString(utf8CsvWithBom);

    await Share.shareXFiles([XFile(path)], text: 'નાણાકીય હિસાબ રિપોર્ટ (CSV/Excel)');
  }

  // PDF એક્સપોર્ટ - ગુજરાતી ફોન્ટ એમ્બેડેડ સાથે
  static Future<void> exportToPDF(
    List<Map<dynamic, dynamic>> transactions,
    double totalIncome,
    double totalExpense,
    double assetGain,
    double netSavings,
    String filterName,
  ) async {
    final pdf = pw.Document();

    final fontData = await rootBundle.load('assets/fonts/NotoSansGujarati-Regular.ttf');
    final ttf = pw.Font.ttf(fontData);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: ttf, bold: ttf),
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('નાણાકીય સ્ટેટમેન્ટ રિપોર્ટ', style: pw.TextStyle(fontSize: 18, font: ttf)),
                  pw.Text(DateFormat('dd-MM-yyyy HH:mm').format(DateTime.now()), style: const pw.TextStyle(fontSize: 11)),
                ],
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text('સમયગાળો: $filterName', style: const pw.TextStyle(fontSize: 12)),
            pw.SizedBox(height: 12),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _buildPdfSummaryBox('કુલ આવક', totalIncome, PdfColors.green700, ttf),
                _buildPdfSummaryBox('કુલ ખર્ચ', totalExpense, PdfColors.red700, ttf),
                _buildPdfSummaryBox('કુલ રોકાણ', assetGain, PdfColors.blue700, ttf),
                _buildPdfSummaryBox('ચોખ્ખી બચત', netSavings, PdfColors.teal700, ttf),
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
              headerStyle: pw.TextStyle(color: PdfColors.white, font: ttf, fontSize: 11),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.teal800),
              cellStyle: pw.TextStyle(font: ttf, fontSize: 10),
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

  static pw.Widget _buildPdfSummaryBox(String title, double amount, PdfColor color, pw.Font font) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: color),
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Column(
        children: [
          pw.Text(title, style: pw.TextStyle(fontSize: 10, font: font)),
          pw.SizedBox(height: 3),
          pw.Text('Rs. ${amount.toStringAsFixed(0)}', style: pw.TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }
}
