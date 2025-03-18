import 'package:flutter/material.dart';
import '../services/weather_service.dart';
import '../models/weather_model.dart';

class WeatherScreen extends StatefulWidget {
  const WeatherScreen({super.key});

  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> {
  final _weatherService = WeatherService();
  final _controller = TextEditingController();
  WeatherData? _weatherData;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _searchWeather() async {
    final icao = _controller.text.trim().toUpperCase();
    if (icao.isEmpty) {
      setState(() => _error = '请输入机场ICAO代码');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final weather = await _weatherService.getAirportWeather(icao);
      if (weather != null) {
        setState(() {
          _weatherData = weather;
          _error = null;
        });
      } else {
        setState(() => _error = '未找到该机场的天气信息');
      }
    } catch (e) {
      setState(() => _error = '获取天气信息失败: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('机场天气查询'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // 搜索框
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: '请输入机场ICAO代码',
                hintText: '例如：ZBAA',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
              ),
              textCapitalization: TextCapitalization.characters,
              onSubmitted: (_) => _searchWeather(),
            ),
            const SizedBox(height: 16),
            
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              )
            else if (_weatherData != null)
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 原始报文
                      const Text(
                        '原始报文:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('METAR: ${_weatherData!.rawMetar}'),
                              if (_weatherData!.rawTaf != null) ...[
                                const Divider(),
                                Text('TAF: ${_weatherData!.rawTaf}'),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // 翻译后的内容
                      const Text(
                        '翻译:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_weatherService.getTranslatedMetar(_weatherData!)),
                              if (_weatherData!.rawTaf != null) ...[
                                const Divider(),
                                Text(_weatherService.getTranslatedTaf(_weatherData!.rawTaf!)),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
