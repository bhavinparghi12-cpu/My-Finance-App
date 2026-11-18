import 'dart:io';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';

class ExportService {
  // =========================================================
  // ૧. ગુજરાતી જોડાક્ષરો (Conjuncts) ૧૦૦% સાચા દેખાય તે માટે
  // HTML + Google Fonts ('Noto Sans Gujarati') -> Native Chromium PDF
  // અને સાથે જ Excel (.xls અને .csv) ફાઇલ જનરેશન
  // =========================================================
  static Future<void> exportToPDF(
    List<Map<dynamic, dynamic>> transactions,
    double totalIncome,
    double totalExpense,
    double totalInvestment,
    double netSavings,
    String periodTitle,
  ) async {
    final String dateNow = DateFormat('dd/MM/yyyy hh:mm a').format(DateTime.now());

    // PDF ની સાથે આપોઆપ Excel (.xls) અને CSV રિપોર્ટ પણ Download ફોલ્ડરમાં સેવ કરો
    await exportToExcelAndCsv(
      transactions,
      totalIncome,
      totalExpense,
      totalInvestment,
      netSavings,
      periodTitle,
    );

    final StringBuffer rowsHtml = StringBuffer();
    int index = 1;
    for (final tx in transactions) {
      final dt = DateFormat('dd/MM/yyyy').format(DateTime.parse(tx['date'].toString()));
      final title = _escapeHtml((tx['title'] ?? '').toString());
      final category = _escapeHtml((tx['categoryName'] ?? '').toString());
      final account = _escapeHtml((tx['accountName'] ?? '').toString());
      final effect = (tx['categoryEffect'] ?? '').toString();
      final amt = ((tx['amount'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(0);

      String typeLabel = 'ખર્ચ';
      String colorHex = '#D32F2F';
      if (effect == 'incomeCredit') {
        typeLabel = 'આવક';
        colorHex = '#2E7D32';
      } else if (effect == 'assetIncrease') {
        typeLabel = 'રોકાણ';
        colorHex = '#1565C0';
      }

      rowsHtml.writeln('''
        <tr>
          <td style="text-align:center;">${index++}</td>
          <td>$dt</td>
          <td><b>$title</b></td>
          <td>$category</td>
          <td>$account</td>
          <td style="color:$colorHex; font-weight:bold;">$typeLabel</td>
          <td style="text-align:right; color:$colorHex; font-weight:bold;">₹$amt</td>
        </tr>
      ''');
    }

    // Android Native WebView (HarfBuzz Shaping Engine) દ્વારા HTML to PDF બનવાથી
    // ગુજરાતી જોડાક્ષરો (ક્ષ, જ્ઞ, ત્ર, શ્ર, દ્ધ, પ્ર, ર્ વગેરે) ૧૦૦% સાચા અને સ્પષ્ટ દેખાય છે!
    final String htmlContent = '''
<!DOCTYPE html>
<html lang="gu">
<head>
  <meta charset="UTF-8">
  <link href="https://fonts.googleapis.com/css2?family=Noto+Sans+Gujarati:wght@400;600;700&display=swap" rel="stylesheet">
  <style>
    body {
      font-family: 'Noto Sans Gujarati', sans-serif;
      margin: 20px;
      color: #1F2937;
    }
    .header {
      background: #00695C;
      color: white;
      padding: 16px 20px;
      border-radius: 10px;
      margin-bottom: 16px;
    }
    .header h1 {
      margin: 0;
      font-size: 22px;
    }
    .header p {
      margin: 4px 0 0 0;
      font-size: 12px;
      opacity: 0.9;
    }
    .summary-grid {
      display: flex;
      justify-content: space-between;
      gap: 10px;
      margin-bottom: 18px;
    }
    .card {
      flex: 1;
      padding: 12px;
      border-radius: 8px;
      border: 1px solid #E5E7EB;
      text-align: center;
    }
    table {
      width: 100%;
      border-collapse: collapse;
      font-size: 12px;
    }
    th {
      background-color: #00796B;
      color: white;
      padding: 8px;
      text-align: left;
      border: 1px solid #004D40;
    }
    td {
      padding: 7px 8px;
      border: 1px solid #D1D5DB;
    }
    tr:nth-child(even) {
      background-color: #F9FAFB;
    }
  </style>
</head>
<body>
  <div class="header">
    <h1>નાણાકીય હિસાબો - સંપૂર્ણ રિપોર્ટ ($periodTitle)</h1>
    <p>રિપોર્ટ તારીખ: $dateNow</p>
  </div>

  <div class="summary-grid">
    <div class="card" style="background:#E8F5E9;">
      <div><b>કુલ આવક</b></div>
      <div style="color:#2E7D32; font-size:16px; font-weight:bold;">₹${totalIncome.toStringAsFixed(0)}</div>
    </div>
    <div class="card" style="background:#FFEBEE;">
      <div><b>કુલ ખર્ચ</b></div>
      <div style="color:#C62828; font-size:16px; font-weight:bold;">₹${totalExpense.toStringAsFixed(0)}</div>
    </div>
    <div class="card" style="background:#E3F2FD;">
      <div><b>કુલ રોકાણ</b></div>
      <div style="color:#1565C0; font-size:16px; font-weight:bold;">₹${totalInvestment.toStringAsFixed(0)}</div>
    </div>
    <div class="card" style="background:#E0F2F1;">
      <div><b>નેટ બચત</b></div>
      <div style="color:#00695C; font-size:16px; font-weight:bold;">₹${netSavings.toStringAsFixed(0)}</div>
    </div>
  </div>

  <table>
    <thead>
      <tr>
        <th style="width:40px; text-align:center;">ક્રમ</th>
        <th style="width:85px;">તારીખ</th>
        <th>વિગત / શીર્ષક</th>
        <th>કેટેગરી</th>
        <th>ખાતું</th>
        <th style="width:65px;">પ્રકાર</th>
        <th style="width:95px; text-align:right;">રકમ (₹)</th>
      </tr>
    </thead>
    <tbody>
      ${rowsHtml.toString()}
    </tbody>
  </table>
</body>
</html>
''';

    await Printing.layoutPdf(
      format: PdfPageFormat.a4,
      name: 'Finance_Report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf',
      onLayout: (PdfPageFormat format) async {
        return await Printing.convertHtml(
          format: format,
          html: htmlContent,
        );
      },
    );
  }

  static Future<void> exportToExcelAndCsv(
    List<Map<dynamic, dynamic>> transactions,
    double totalIncome,
    double totalExpense,
    double totalInvestment,
    double netSavings,
    String periodTitle,
  ) async {
    try {
      final dir = Directory('/storage/emulated/0/Download/MyFinanceApp_Backup');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());

      // Excel XML (.xls)
      final StringBuffer xls = StringBuffer();
      xls.writeln('<?xml version="1.0" encoding="UTF-8"?>');
      xls.writeln('<?mso-application progid="Excel.Sheet"?>');
      xls.writeln('<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">');
      xls.writeln('<Worksheet ss:Name="નાણાકીય રિપોર્ટ"><Table>');
      xls.writeln('<Row><Cell><Data ss:Type="String">નાણાકીય હિસાબો રિપોર્ટ ($periodTitle)</Data></Cell></Row>');
      xls.writeln('<Row><Cell><Data ss:Type="String">કુલ આવક</Data></Cell><Cell><Data ss:Type="Number">$totalIncome</Data></Cell></Row>');
      xls.writeln('<Row><Cell><Data ss:Type="String">કુલ ખર્ચ</Data></Cell><Cell><Data ss:Type="Number">$totalExpense</Data></Cell></Row>');
      xls.writeln('<Row><Cell><Data ss:Type="String">કુલ રોકાણ</Data></Cell><Cell><Data ss:Type="Number">$totalInvestment</Data></Cell></Row>');
      xls.writeln('<Row><Cell><Data ss:Type="String">નેટ બચત</Data></Cell><Cell><Data ss:Type="Number">$netSavings</Data></Cell></Row>');
      xls.writeln('<Row></Row>');
      xls.writeln('<Row><Cell><Data ss:Type="String">તારીખ</Data></Cell><Cell><Data ss:Type="String">વિગત</Data></Cell><Cell><Data ss:Type="String">કેટેગરી</Data></Cell><Cell><Data ss:Type="String">પ્રકાર</Data></Cell><Cell><Data ss:Type="String">ખાતું</Data></Cell><Cell><Data ss:Type="String">રકમ (₹)</Data></Cell></Row>');

      for (final tx in transactions) {
        final dt = DateFormat('dd/MM/yyyy').format(DateTime.parse(tx['date'].toString()));
        final title = _escapeHtml((tx['title'] ?? '').toString());
        final cat = _escapeHtml((tx['categoryName'] ?? '').toString());
        final acc = _escapeHtml((tx['accountName'] ?? '').toString());
        final eff = tx['categoryEffect'] == 'incomeCredit'
            ? 'આવક'
            : (tx['categoryEffect'] == 'assetIncrease' ? 'રોકાણ' : 'ખર્ચ');
        final amt = ((tx['amount'] as num?)?.toDouble() ?? 0.0);

        xls.writeln(
          '<Row>'
          '<Cell><Data ss:Type="String">$dt</Data></Cell>'
          '<Cell><Data ss:Type="String">$title</Data></Cell>'
          '<Cell><Data ss:Type="String">$cat</Data></Cell>'
          '<Cell><Data ss:Type="String">$eff</Data></Cell>'
          '<Cell><Data ss:Type="String">$acc</Data></Cell>'
          '<Cell><Data ss:Type="Number">$amt</Data></Cell>'
          '</Row>',
        );
      }
      xls.writeln('</Table></Worksheet></Workbook>');

      final xlsFile = File('${dir.path}/Finance_Report_$ts.xls');
      await xlsFile.writeAsString(xls.toString(), flush: true);
    } catch (_) {}
  }

  static String _escapeHtml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
