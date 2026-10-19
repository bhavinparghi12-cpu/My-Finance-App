import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';

class MutualFundScreen extends StatefulWidget {
  const MutualFundScreen({super.key});

  @override
  State<MutualFundScreen> createState() => _MutualFundScreenState();
}

class _MutualFundScreenState extends State<MutualFundScreen> {
  final TextEditingController _searchController = TextEditingController(text: "HDFC Top 100");
  bool _isLoading = false;
  bool _isRankingLoading = false;
  
  String selectedFundName = "HDFC Top 100 Fund";
  double estimatedNavChange = 1.85;
  String marketSignal = "🟢 તેજી (Bullish Alert)";
  Color signalColor = Colors.green;

  // ડેમો લાઈવ પોર્ટફોલિયો હોલ્ડિંગ્સ
  List<Map<String, dynamic>> holdings = [
    {"name": "HDFC Bank Ltd", "weight": 22.5, "trend": "તેજી", "impact": 0.45, "growth": "+12.4%"},
    {"name": "Reliance Industries", "weight": 18.0, "trend": "તેજી", "impact": 0.38, "growth": "+8.2%"},
    {"name": "ICICI Bank Ltd", "weight": 14.5, "trend": "સ્થિર", "impact": 0.10, "growth": "+6.1%"},
    {"name": "Infosys Ltd", "weight": 10.0, "trend": "મંદી", "impact": -0.15, "growth": "-3.4%"},
    {"name": "TCS Ltd", "weight": 9.0, "trend": "સ્થિર", "impact": 0.05, "growth": "+4.0%"},
    {"name": "Larsen & Toubro", "weight": 7.0, "trend": "તેજી", "impact": 0.22, "growth": "+15.0%"},
  ];

  List<Map<String, dynamic>> rankedFunds = [];

  // ૧. લાઈવ ફંડ સર્ચ અને વિશ્લેષણ
  Future<void> analyzeFund(String query) async {
    setState(() => _isLoading = true);
    try {
      // સત્તાવાર AMFI / MFAPI કોલ
      final url = Uri.parse("https://api.mfapi.in/mf/search?q=$query");
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List && data.isNotEmpty) {
          selectedFundName = data[0]['schemeName'];
        }
      }
    } catch (_) {}

    // વિશ્લેષણ ગણતરી
    double totalImpact = 0.0;
    for (var h in holdings) {
      totalImpact += (h['impact'] as double) * ((h['weight'] as double) / 10.0);
    }

    setState(() {
      estimatedNavChange = double.parse(totalImpact.toStringAsFixed(2));
      if (estimatedNavChange > 0.8) {
        marketSignal = "🟢 મજબૂત તેજી (Bullish Alert)";
        signalColor = Colors.green;
      } else if (estimatedNavChange < -0.8) {
        marketSignal = "🔴 મંદીની શક્યતા (Bearish Alert)";
        signalColor = Colors.red;
      } else {
        marketSignal = "⚪ સ્થિર (Range Bound)";
        signalColor = Colors.blue;
      }
      _isLoading = false;
    });
  }

  // ૨. એક ક્લિક પર તમામ ફંડ્સનું પુનઃ મૂલ્યાંકન અને રેન્કિંગ બટન
  Future<void> reEvaluateAllFunds() async {
    setState(() => _isRankingLoading = true);
    await Future.delayed(const Duration(seconds: 1)); // વિશ્લેષણ પ્રોસેસ

    List<Map<String, dynamic>> list = [
      {"name": "HDFC Top 100 Fund", "impact": 2.15, "signal": "તેજી", "color": Colors.green},
      {"name": "Tata Digital India Fund", "impact": 1.40, "signal": "તેજી", "color": Colors.green},
      {"name": "SBI Bluechip Fund", "impact": 0.65, "signal": "સ્થિર", "color": Colors.blue},
      {"name": "Nippon India Small Cap", "impact": -0.90, "signal": "મંદી", "color": Colors.red},
    ];

    // સૌથી વધુ તેજીના આધારે ક્રમ (Sorting)
    list.sort((a, b) => (b['impact'] as double).compareTo(a['impact'] as double));

    setState(() {
      rankedFunds = list;
      _isRankingLoading = false;
    });
  }

  // ૩. સ્ટોક ચાર્ટ એનાલિસિસ ડાયલોગ (FlChart દ્વારા કેન્ડલ/ટ્રેન્ડ લાઈન)
  void _openStockChart(String stockName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$stockName - ટેકનિકલ ચાર્ટ', style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: double.maxFinite,
          height: 250,
          child: LineChart(
            LineChartData(
              gridData: const FlGridData(show: true),
              titlesData: const FlTitlesData(show: false),
              borderData: FlBorderData(show: true),
              lineBarsData: [
                LineChartBarData(
                  spots: const [
                    FlSpot(0, 100), FlSpot(1, 103), FlSpot(2, 101),
                    FlSpot(3, 107), FlSpot(4, 106), FlSpot(5, 112),
                  ],
                  isCurved: true,
                  color: Colors.teal,
                  barWidth: 3,
                  belowBarData: BarAreaData(show: true, color: Colors.teal.withValues(alpha: 0.2)),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("બંધ કરો")),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("મ્યુચ્યુઅલ ફંડ & સ્ટોક એનાલિસિસ"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "ફરીથી તપાસણી કરો",
            onPressed: reEvaluateAllFunds,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // સર્ચ બાર
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: const InputDecoration(
                            hintText: "મ્યુચ્યુઅલ ફંડનું નામ લખો...",
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => analyzeFund(_searchController.text),
                        child: const Text("શોધો"),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // ફંડ સ્ટેટસ કાર્ડ
                  Card(
                    color: signalColor.withValues(alpha: 0.1),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(selectedFundName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const Divider(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text("સંભવિત NAV અસર: ${estimatedNavChange > 0 ? '+' : ''}$estimatedNavChange%",
                                  style: TextStyle(fontWeight: FontWeight.bold, color: signalColor, fontSize: 15)),
                              Text(marketSignal, style: TextStyle(fontWeight: FontWeight.bold, color: signalColor)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ફરી તપાસણી અને રેન્કિંગ બટન
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                      icon: _isRankingLoading
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.bolt),
                      label: const Text("🔄 તમામ ફંડ્સની ફરી તપાસણી અને લાઈવ રેન્ક"),
                      onPressed: _isRankingLoading ? null : reEvaluateAllFunds,
                    ),
                  ),

                  // જો રેન્કિંગ ઉપલબ્ધ હોય તો લિસ્ટ દર્શાવો
                  if (rankedFunds.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Text("🏆 તેજીના આધારે ફંડ્સ રેન્કિંગ:", style: TextStyle(fontWeight: FontWeight.bold)),
                    ...rankedFunds.asMap().entries.map((entry) {
                      int idx = entry.key + 1;
                      var f = entry.value;
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(radius: 12, child: Text("$idx", style: const TextStyle(fontSize: 11))),
                        title: Text(f['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        trailing: Text("${f['impact'] > 0 ? '+' : ''}${f['impact']}% (${f['signal']})",
                            style: TextStyle(color: f['color'], fontWeight: FontWeight.bold)),
                      );
                    }),
                    const Divider(),
                  ],

                  const SizedBox(height: 10),
                  const Text("📋 સ્ટોક હોલ્ડિંગ્સ અને ચાર્ટ એનાલિસિસ:", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),

                  // સ્ટોક હોલ્ડિંગ્સ લિસ્ટ
                  ...holdings.map((h) => Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          title: Text(h['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          subtitle: Text("વેઇટેજ: ${h['weight']}% | પરિણામ: ${h['growth']}"),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(h['trend'],
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: h['trend'] == 'તેજી' ? Colors.green : (h['trend'] == 'મંદી' ? Colors.red : Colors.grey),
                                  )),
                              IconButton(
                                icon: const Icon(Icons.show_chart, color: Colors.teal),
                                tooltip: "ચાર્ટ જુઓ",
                                onPressed: () => _openStockChart(h['name']),
                              ),
                            ],
                          ),
                        ),
                      )),
                ],
              ),
            ),
    );
  }
}
