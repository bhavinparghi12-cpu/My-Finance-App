import 'dart:io';
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class ExportService {
  // Excel / CSV ફાઇલ એક્સપોર્ટ
  static Future<void> exportToCSV(List<Map<dynamic, dynamic>> transactions) async {
    List<List<dynamic>> rows = [
      ['તારીખ (Date)', 'વિગત (Title)', 'કેટેગરી (Category)', 'પ્રકાર (Type)', 'રકમ (Amount Rs)']
    ];

    for (var tx in transactions) {
      final date = DateTime.parse(tx['date']);
      final formattedDate = DateFormat('dd/MM/yyyy HH:mm').format(date);
      rows.add([
        formattedDate,
        tx['title'],
        tx['categoryName'],
        tx['categoryEffect'],
        tx['amount'],
      ]);
    }

    String csvData = const ListToCsvConverter().convert(rows);
    final directory = await getTemporaryDirectory();
    final path = "${directory.path}/Finance_Report_${DateTime.now().millisecondsSinceEpoch}.csv";
    final file = File(path);
    await file.writeAsString(csvData);

    await Share.shareXFiles([XFile(path)], text: 'મારો નાણાકીય હિસાબ (CSV Report)');
  }

  // PDF રિપોર્ટ જનરેટ અને પ્રિન્ટ
  static Future<void> exportToPDF(
    List<Map<dynamic, dynamic>> transactions,
    double assetGain,
    double totalExpense,
    String filterName,
  ) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Financial Statement Report',
                      style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                  pw.Text(DateFormat('dd MMM yyyy').format(DateTime.now()),
                      style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
                ],
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text('Report Period: $filterName', style: const pw.TextStyle(fontSize: 12)),
            pw.SizedBox(height: 16),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.blue50,
                    borderRadius: pw.BorderRadius.circular(6),
                    border: pw.Border.all(color: PdfColors.blue300),
                  ),
                  child: pw.Column(
                    children: [
                      pw.Text('Total Asset Gain (Investment)', style: const pw.TextStyle(fontSize: 11)),
                      pw.SizedBox(height: 4),
                      pw.Text('Rs. ${assetGain.toStringAsFixed(2)}',
                          style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
                    ],
                  ),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.red50,
                    borderRadius: pw.BorderRadius.circular(6),
                    border: pw.Border.all(color: PdfColors.red300),
                  ),
                  child: pw.Column(
                    children: [
                      pw.Text('Total Debited Expense', style: const pw.TextStyle(fontSize: 11)),
                      pw.SizedBox(height: 4),
                      pw.Text('Rs. ${totalExpense.toStringAsFixed(2)}',
                          style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: PdfColors.red800)),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 20),
            pw.Table.fromTextArray(
              headers: ['Date', 'Description', 'Category', 'Amount (Rs.)'],
              data: transactions.map((tx) {
                final date = DateTime.parse(tx['date']);
                return [
                  DateFormat('dd/MM/yyyy').format(date),
                  tx['title'].toString(),
                  tx['categoryName'].toString(),
                  (tx['amount'] as num).toStringAsFixed(2),
                ];
              }).toList(),
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.teal700),
              cellHeight: 24,
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.centerLeft,
                3: pw.Alignment.centerRight,
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
}
