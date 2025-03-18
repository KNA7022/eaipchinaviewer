import 'package:flutter/material.dart';
import '../services/weather_service.dart';
import '../models/weather_model.dart';
import 'package:flutter/services.dart';  

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
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('机场天气查询'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(90),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                labelText: '请输入机场ICAO代码',
                hintText: '例如：ZBAA、ZPPP',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => _controller.clear(),
                ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              ),
              textCapitalization: TextCapitalization.characters,
              onSubmitted: (_) => _searchWeather(),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在获取天气信息...'),
                ],
              ),
            )
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, 
                           size: 48, 
                           color: theme.colorScheme.error),
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _searchWeather,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : _weatherData != null
                  ? SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 机场信息卡片
                          Card(
                            elevation: 4,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.location_on),
                                      const SizedBox(width: 8),
                                      Text(
                                        _weatherData!.icaoId,
                                        style: theme.textTheme.titleLarge,
                                      ),
                                    ],
                                  ),
                                  const Divider(),
                                  Text(
                                    '观测时间：${_formatDateTime(_weatherData!.reportTime)}',
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // METAR信息卡片
                          _buildSection(
                            title: '实时天气',
                            icon: Icons.cloud,
                            content: _weatherData!.rawMetar,
                            translation: _weatherService.getTranslatedMetar(_weatherData!),
                          ),

                          if (_weatherData!.rawTaf != null) ...[
                            const SizedBox(height: 16),
                            // TAF信息卡片
                            _buildSection(
                              title: '天气预报',
                              icon: Icons.watch_later,
                              content: _weatherData!.rawTaf!,
                              translation: _weatherService.getTranslatedTaf(_weatherData!.rawTaf!),
                            ),
                          ],
                        ],
                      ),
                    )
                  : Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.flight,
                            size: 64,
                            color: theme.colorScheme.primary.withOpacity(0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '输入机场代码查询天气',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onBackground.withOpacity(0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required String content,
    required String translation,
  }) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const Divider(),
            // 原始报文 - 添加长按复制功能
            InkWell(
              onLongPress: () {
                Clipboard.setData(ClipboardData(text: content)).then((_) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('原文已复制到剪贴板')),
                  );
                });
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                ),
                child: Text(
                  content,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
            ),
            const Divider(),
            // 翻译内容 - 添加长按复制功能
            InkWell(
              onLongPress: () {
                Clipboard.setData(ClipboardData(text: translation)).then((_) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('翻译已复制到剪贴板')),
                  );
                });
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                ),
                child: Text(
                  translation,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}年${dt.month}月${dt.day}日 ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
