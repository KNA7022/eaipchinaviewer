import 'package:flutter/material.dart';
import '../services/weather_service.dart';
import '../services/airport_service.dart';
import '../models/weather_model.dart';
import 'package:flutter/services.dart';
import 'dart:async';

class WeatherScreen extends StatefulWidget {
  const WeatherScreen({super.key});

  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> {
  final _weatherService = WeatherService();
  final _airportService = AirportService();
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  WeatherData? _weatherData;
  AirportInfo? _airportInfo;
  bool _isLoading = false;
  bool _isUsingCachedData = false;
  String? _error;
  Timer? _autoRefreshTimer;
  List<String> _recentSearches = [];
  final int _maxRecentSearches = 5;

  @override
  void initState() {
    super.initState();
    _loadRecentSearches();
    
    // 应用启动时清理过期缓存
    _weatherService.clearExpiredCache();
    _airportService.clearExpiredCache();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadRecentSearches() async {
    // 从SharedPreferences加载最近的搜索历史
    // 实现代码略，仅做示例
  }

  Future<void> _saveRecentSearch(String icao) async {
    if (icao.isEmpty) return;
    
    setState(() {
      // 避免重复添加
      if (!_recentSearches.contains(icao)) {
        _recentSearches.insert(0, icao);
        // 限制最大数量
        if (_recentSearches.length > _maxRecentSearches) {
          _recentSearches = _recentSearches.sublist(0, _maxRecentSearches);
        }
      } else {
        // 如果已存在，则将其移至列表首位
        _recentSearches.remove(icao);
        _recentSearches.insert(0, icao);
      }
    });
    
    // 保存到SharedPreferences
    // 实现代码略，仅做示例
  }

  Future<void> _searchWeather({bool forceRefresh = false}) async {
    final icao = _controller.text.trim().toUpperCase();
    if (icao.isEmpty) {
      setState(() => _error = '请输入机场ICAO代码');
      return;
    }

    // 验证ICAO代码格式
    if (!_weatherService.isValidIcaoCode(icao)) {
      setState(() => _error = 'ICAO代码格式不正确，应为4个英文字母');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _isUsingCachedData = false;
    });

    try {
      // 同时获取天气数据和机场信息
      final results = await Future.wait([
        _weatherService.getAirportWeather(icao, forceRefresh: forceRefresh),
        _airportService.getAirportInfo(icao),
      ]);
      
      final weather = results[0] as WeatherData?;
      final airportInfo = results[1] as AirportInfo?;
      
      if (weather != null) {
        setState(() {
          _weatherData = weather;
          _airportInfo = airportInfo;
          _error = null;
          // 检查数据是否来自过期缓存
          final cacheAge = DateTime.now().difference(weather.cacheTime);
          _isUsingCachedData = cacheAge > const Duration(minutes: 30);
          
          // 保存到最近搜索历史
          _saveRecentSearch(icao);
        });
        
        // 设置自动刷新定时器
        _autoRefreshTimer?.cancel();
        _autoRefreshTimer = Timer(const Duration(minutes: 15), () {
          if (mounted) {
            _searchWeather(forceRefresh: true);
          }
        });
      } else {
        setState(() => _error = '未找到该机场的天气信息');
      }
    } catch (e) {
      setState(() => _error = '获取天气信息失败: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _clearSearch() {
    _controller.clear();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('机场天气查询'),
        actions: [
          if (_weatherData != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '刷新天气数据',
              onPressed: _isLoading ? null : () => _searchWeather(forceRefresh: true),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(90),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              decoration: InputDecoration(
                labelText: '请输入机场ICAO代码',
                hintText: '例如：ZBAA、ZPPP、ZGGG',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_controller.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: _clearSearch,
                        tooltip: '清除',
                      ),
                  ],
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
              textInputAction: TextInputAction.search,
            ),
          ),
        ),
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在获取天气信息...'),
          ],
        ),
      );
    }
    
    if (_error != null) {
      return Center(
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
              onPressed: () => _searchWeather(forceRefresh: true),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    
    if (_weatherData != null) {
      return _buildWeatherContent(theme);
    }
    
    return _buildInitialContent(theme);
  }

  Widget _buildInitialContent(ThemeData theme) {
    return Center(
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
          if (_recentSearches.isNotEmpty) ...[
            const SizedBox(height: 32),
            Text(
              '最近搜索',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _recentSearches.map((icao) => 
                FutureBuilder<AirportInfo?>(
                  future: _airportService.getAirportInfo(icao),
                  builder: (context, snapshot) {
                    String displayText = icao;
                    
                    if (snapshot.connectionState == ConnectionState.done) {
                      final airportInfo = snapshot.data;
                      displayText = airportInfo?.shortDisplayName ?? icao;
                    }
                    
                    return ActionChip(
                      label: Text(
                        displayText,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onPressed: () {
                        _controller.text = icao;
                        _searchWeather();
                      },
                      avatar: const Icon(Icons.history, size: 16),
                    );
                  },
                )
              ).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWeatherContent(ThemeData theme) {
    return SingleChildScrollView(
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Row(
                          children: [
                            const Icon(Icons.location_on),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _airportInfo?.displayName ?? _weatherData!.icaoId,
                                    style: theme.textTheme.titleLarge,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (_airportInfo != null)
                                    Text(
                                      'ICAO: ${_weatherData!.icaoId}${_airportInfo!.iata != null ? ' / IATA: ${_airportInfo!.iata}' : ''}',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurface.withOpacity(0.7),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_isUsingCachedData)
                        Tooltip(
                          message: '显示的是缓存数据，可能不是最新的',
                          child: Chip(
                            label: const Text('缓存数据'),
                            avatar: const Icon(Icons.access_time, size: 16),
                            backgroundColor: theme.colorScheme.surfaceVariant,
                            labelStyle: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '观测时间：${_formatDateTime(_weatherData!.reportTime)}',
                        style: theme.textTheme.bodyMedium,
                      ),
                      Text(
                        '更新于：${_formatTimeDifference(_weatherData!.cacheTime)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                          fontSize: 12,
                        ),
                      ),
                    ],
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

          if (_weatherData!.rawTaf != null && _weatherData!.rawTaf!.isNotEmpty) ...[
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '原始报文:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: content)).then((_) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('原文已复制到剪贴板')),
                              );
                            });
                          },
                          child: const Padding(
                            padding: EdgeInsets.all(4.0),
                            child: Icon(Icons.copy, size: 16),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      content,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ],
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '翻译内容:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: translation)).then((_) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('翻译已复制到剪贴板')),
                              );
                            });
                          },
                          child: const Padding(
                            padding: EdgeInsets.all(4.0),
                            child: Icon(Icons.copy, size: 16),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      translation,
                      style: Theme.of(context).textTheme.bodyMedium,
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

  String _formatDateTime(DateTime dt) {
    return '${dt.year}年${dt.month}月${dt.day}日 ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
  
  String _formatTimeDifference(DateTime dt) {
    final difference = DateTime.now().difference(dt);
    
    if (difference.inSeconds < 60) {
      return '刚刚';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}分钟前';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}小时前';
    } else {
      return '${difference.inDays}天前';
    }
  }
}
