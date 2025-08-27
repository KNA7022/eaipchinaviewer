import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart' as gauges;
import 'dart:math' as math;
import '../models/weather_model.dart';
import '../utils/weather_data_parser.dart';

/// 气象数据可视化组件基类
abstract class WeatherVisualizationWidget extends StatefulWidget {
  final WeatherData weatherData;

  const WeatherVisualizationWidget({
    Key? key,
    required this.weatherData,
  }) : super(key: key);
}

/// 气象数据可视化组件状态基类
abstract class WeatherVisualizationState<T extends WeatherVisualizationWidget> extends State<T> with AutomaticKeepAliveClientMixin {
  // 缓存解析后的数据
  Map<String, dynamic> _dataCache = {};
  
  @override
  bool get wantKeepAlive => true;
  
  /// 获取缓存的数据，如果不存在则解析并缓存
  T getCachedData<T>(String key, T Function() parser) {
    if (!_dataCache.containsKey(key) || _dataCache[key] == null) {
      _dataCache[key] = parser();
    }
    return _dataCache[key] as T;
  }
  
  /// 清除缓存
  void clearCache() {
    _dataCache.clear();
  }
  
  @override
  void didUpdateWidget(T oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 如果数据发生变化，清除缓存
    if (oldWidget.weatherData.rawMetar != widget.weatherData.rawMetar) {
      clearCache();
    }
  }
}

/// 风向风速可视化组件
class WindVisualizationWidget extends WeatherVisualizationWidget {
  const WindVisualizationWidget({
    Key? key,
    required WeatherData weatherData,
  }) : super(key: key, weatherData: weatherData);

  @override
  State<WindVisualizationWidget> createState() => _WindVisualizationWidgetState();
}

class _WindVisualizationWidgetState extends WeatherVisualizationState<WindVisualizationWidget> with SingleTickerProviderStateMixin {
  // 添加动画控制器，用于VRB（不定风向）的旋转动画
  late AnimationController _animationController;
  double _currentVrbDirection = 0;
  
  @override
  void initState() {
    super.initState();
    
    // 初始化动画控制器
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8), // 8秒旋转一周
    );
    
    // 延迟初始化，确保数据已加载
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeAnimation();
    });
  }
  
  void _initializeAnimation() {
    try {
      // 确保组件仍然挂载
      if (!mounted) return;
      
      final windData = getCachedData<WindVisualizationData>('windData', () => _parseWindData());
      
      // 无论如何，先停止动画并移除监听器
      _animationController.stop();
      _animationController.removeListener(_updateVrbDirection);
      
      // 如果是不定风向，启动动画
      if (windData.isVariable) {
        _animationController.addListener(_updateVrbDirection);
        _animationController.repeat();
      } else {
        // 如果不是不定风向，确保使用固定方向值
        setState(() {
          _currentVrbDirection = windData.direction;
        });
      }
    } catch (e) {
      print('初始化风向动画错误: $e');
    }
  }
  
  void _updateVrbDirection() {
    // 检查组件是否已挂载，避免在组件销毁后调用setState
    if (mounted) {
      setState(() {
        // 根据动画值更新VRB方向，实现360度旋转
        _currentVrbDirection = _animationController.value * 360;
      });
    }
  }
  
  @override
  void didUpdateWidget(WindVisualizationWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 如果数据发生变化，重新初始化动画
    if (oldWidget.weatherData.rawMetar != widget.weatherData.rawMetar) {
      // 使用延迟回调确保状态已更新
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _initializeAnimation();
        }
      });
    }
  }

  @override
  void dispose() {
    // 在销毁前移除监听器，避免在组件销毁后调用setState
    _animationController.removeListener(_updateVrbDirection);
    _animationController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Card(
      elevation: 4,
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.air,
                  color: Theme.of(context).primaryColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  '风向风速',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                _buildDataQualityIndicator(context),
              ],
            ),
            const SizedBox(height: 16),
            _buildWindContent(context),
          ],
        ),
      ),
    );
  }

  Widget _buildWindContent(BuildContext context) {
    try {
      final windData = getCachedData<WindVisualizationData>('windData', () => _parseWindData());
      
      // 只有在确认是静风时才显示静风界面
      // 不定风向(VRB)不是静风，应该显示风向风速图表
      if (windData.isCalm || (windData.speed == 0)) {
        return _buildCalmWindDisplay(context);
      }
      
      return Column(
        children: [
          SizedBox(
            height: 250, // 增加高度，使圆环更大
            child: _buildWindChart(context, windData),
          ),
          const SizedBox(height: 8),
          _buildWindInfo(context, windData),
          // 移除重复的不定风向指示，因为已经在_buildWindInfo中显示
        ],
      );
    } catch (e) {
      print('风向数据解析错误: $e');
      return _buildErrorDisplay(context, '风向风速数据解析失败: ${e.toString()}');
    }
  }

  Widget _buildWindChart(BuildContext context, WindVisualizationData windData) {
    // 确定风向值 - 如果是不定风向(VRB)，使用动画值
    final double directionValue = windData.isVariable ? _currentVrbDirection : windData.direction;
    
    return AnimatedContainer(
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeInOut,
      width: double.infinity, // 确保容器占据所有可用宽度
      constraints: const BoxConstraints(minWidth: 300), // 设置最小宽度约束
      child: gauges.SfRadialGauge(

        axes: <gauges.RadialAxis>[
          gauges.RadialAxis(
            minimum: 0,
            maximum: 360,
            startAngle: 270, // 从顶部开始
            endAngle: 270,   // 结束于顶部，形成完整圆环
            radiusFactor: 0.95, // 增加半径因子，使圆环更大
            showLabels: true,  // 显示度数标签
            labelOffset: 35, // 进一步增加标签偏移量，使其更靠近外部
            labelsPosition: gauges.ElementsPosition.outside, // 标签位置在外部
            showTicks: true,
            ticksPosition: gauges.ElementsPosition.outside,
            majorTickStyle: const gauges.MajorTickStyle(
              length: 15, // 增加刻度线长度以适应标签
              thickness: 1.5,
              color: Colors.grey,
            ),
            minorTickStyle: const gauges.MinorTickStyle(
              length: 8, // 增加刻度线长度以适应标签
              thickness: 1,
              color: Colors.grey,
            ),
            ranges: <gauges.GaugeRange>[
              gauges.GaugeRange(
                startValue: 0,
                endValue: 90,
                color: Colors.blue.withOpacity(0.1),
                startWidth: 10,
                endWidth: 10,
              ),
              gauges.GaugeRange(
                startValue: 90,
                endValue: 180,
                color: Colors.green.withOpacity(0.1),
                startWidth: 10,
                endWidth: 10,
              ),
              gauges.GaugeRange(
                startValue: 180,
                endValue: 270,
                color: Colors.orange.withOpacity(0.1),
                startWidth: 10,
                endWidth: 10,
              ),
              gauges.GaugeRange(
                startValue: 270,
                endValue: 360,
                color: Colors.red.withOpacity(0.1),
                startWidth: 10,
                endWidth: 10,
              ),
            ],
            pointers: <gauges.GaugePointer>[
              // 添加主刻度线 - 每30度一个
              for (int i = 0; i < 360; i += 30)
                gauges.MarkerPointer(
                  value: i.toDouble(),
                  markerType: gauges.MarkerType.rectangle,
                  markerHeight: 15,
                  markerWidth: 2.5,
                  color: i == 0 ? Colors.red : Colors.grey[700], // 北向刻度为红色
                  markerOffset: -5, // 将刻度线放在圆环内部，更靠近边缘
                ),
              // 添加次刻度线 - 每10度一个（排除已有的30度刻度）
              for (int i = 0; i < 360; i += 10)
                if (i % 30 != 0) // 避免与主刻度重叠
                  gauges.MarkerPointer(
                    value: i.toDouble(),
                    markerType: gauges.MarkerType.rectangle,
                    markerHeight: 8,
                    markerWidth: 1.5,
                    color: Colors.grey[500],
                    markerOffset: -5, // 将刻度线放在圆环内部，更靠近边缘
                  ),
              // 添加长箭头指针 - 更加突出的设计
              gauges.NeedlePointer(
                value: directionValue, // 使用可能动画的方向值
                needleLength: 0.9, // 更长的箭头，占半径的90%
                needleStartWidth: 3,
                needleEndWidth: 8,
                knobStyle: gauges.KnobStyle(
                  knobRadius: 12,
                  sizeUnit: gauges.GaugeSizeUnit.logicalPixel,
                  color: _getWindSpeedColor(windData.speed),
                  borderColor: Colors.white,
                  borderWidth: 1.5,
                ),
                tailStyle: gauges.TailStyle(
                  width: 3,
                  length: 0.2,
                  color: _getWindSpeedColor(windData.speed).withOpacity(0.7),
                  borderColor: Colors.white,
                  borderWidth: 0.5,
                ),
                needleColor: _getWindSpeedColor(windData.speed),
                enableAnimation: !windData.isVariable, // 如果是VRB，不使用内置动画，因为我们使用自定义动画
                animationDuration: 1000, // 必须大于0，否则会触发断言错误
                animationType: gauges.AnimationType.easeInCirc,
              ),
              // 添加风速值显示在指针上
              gauges.MarkerPointer(
                value: directionValue,
                markerType: gauges.MarkerType.circle,
                color: Colors.transparent,
                markerWidth: 1,
                markerHeight: 1,
                markerOffset: -60,
                offsetUnit: gauges.GaugeSizeUnit.logicalPixel,
              ),

            ],
            annotations: <gauges.GaugeAnnotation>[

              // 北方向标记 (N)
              gauges.GaugeAnnotation(
                angle: 0,
                positionFactor: 1.05, // 进一步增加位置因子，使其更靠近外部
                widget: const Text(
                  'N',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red),
                ),
              ),
              // 东方向标记 (E)
              gauges.GaugeAnnotation(
                angle: 90,
                positionFactor: 1.05, // 进一步增加位置因子，使其更靠近外部
                widget: const Text(
                  'E',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              // 南方向标记 (S)
              gauges.GaugeAnnotation(
                angle: 180,
                positionFactor: 1.05, // 进一步增加位置因子，使其更靠近外部
                widget: const Text(
                  'S',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              // 西方向标记 (W)
              gauges.GaugeAnnotation(
                angle: 270,
                positionFactor: 1.05, // 进一步增加位置因子，使其更靠近外部
                widget: const Text(
                  'W',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              // 移除中心风速显示
              // 移除重复的方向标记，因为已经在上面添加了
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWindInfo(BuildContext context, WindVisualizationData windData) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildInfoItem('风向', _getDirectionText(windData.direction), Icons.navigation),
          _buildInfoItem('风速', '${windData.speed.toStringAsFixed(1)} kt', Icons.speed),
          _buildInfoItem('阵风', windData.gust != null ? '${windData.gust!.toStringAsFixed(1)} kt' : '无', Icons.air),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(
          icon,
          size: 16,
          color: Colors.grey[600],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildDataQualityIndicator(BuildContext context) {
    final hasValidData = widget.weatherData.rawMetar.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: hasValidData ? Colors.green[100] : Colors.red[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasValidData ? Icons.check_circle : Icons.error,
            size: 12,
            color: hasValidData ? Colors.green[700] : Colors.red[700],
          ),
          const SizedBox(width: 4),
          Text(
            hasValidData ? '数据正常' : '数据异常',
            style: TextStyle(
              fontSize: 10,
              color: hasValidData ? Colors.green[700] : Colors.red[700],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalmWindDisplay(BuildContext context) {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.air,
              size: 48,
              color: Colors.blue[300],
            ),
            const SizedBox(height: 8),
            Text(
              '无风',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.blue[700],
              ),
            ),
            Text(
              '当前风速为0',
              style: TextStyle(
                fontSize: 14,
                color: Colors.blue[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorDisplay(BuildContext context, String message) {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Colors.red[400],
            ),
            const SizedBox(height: 8),
            Text(
              '数据错误',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.red[700],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  message,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.red[600],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getWindSpeedColor(double speed) {
    if (speed < 5) return Colors.green;
    if (speed < 15) return Colors.yellow[700]!;
    if (speed < 25) return Colors.orange;
    return Colors.red;
  }

  String _getDirectionText(double direction) {
    // 检查是否为不定风向
    final windData = getCachedData<WindVisualizationData>('windData', () => _parseWindData());
    if (windData.isVariable) {
      return 'VRB (不定风向)';
    }
    
    // 正常风向显示
    String cardinalDirection;
    if (direction >= 337.5 || direction < 22.5) {
      cardinalDirection = 'N';
    } else if (direction < 67.5) {
      cardinalDirection = 'NE';
    } else if (direction < 112.5) {
      cardinalDirection = 'E';
    } else if (direction < 157.5) {
      cardinalDirection = 'SE';
    } else if (direction < 202.5) {
      cardinalDirection = 'S';
    } else if (direction < 247.5) {
      cardinalDirection = 'SW';
    } else if (direction < 292.5) {
      cardinalDirection = 'W';
    } else {
      cardinalDirection = 'NW';
    }
    return '${direction.toInt()}° ($cardinalDirection)';
  }

  WindVisualizationData _parseWindData() {
    // 使用WeatherDataParser解析风向风速信息
    return WeatherDataParser.parseWindData(widget.weatherData);
  }
}

/// 能见度等级显示组件
class VisibilityLevelWidget extends WeatherVisualizationWidget {
  const VisibilityLevelWidget({
    Key? key,
    required WeatherData weatherData,
  }) : super(key: key, weatherData: weatherData);

  @override
  State<VisibilityLevelWidget> createState() => _VisibilityLevelWidgetState();
}

class _VisibilityLevelWidgetState extends WeatherVisualizationState<VisibilityLevelWidget> {
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Card(
      elevation: 4,
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.visibility,
                  color: Theme.of(context).primaryColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  '能见度等级',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildVisibilityContent(context),
          ],
        ),
      ),
    );
  }

  Widget _buildVisibilityContent(BuildContext context) {
    try {
      final visibilityData = getCachedData<VisibilityVisualizationData>('visibilityData', () => WeatherDataParser.parseVisibilityData(widget.weatherData));
      final level = visibilityData.level;
      
      return Column(
        children: [
          _buildVisibilityIndicator(context, visibilityData, level),
          const SizedBox(height: 12),
          _buildVisibilityDescription(context, level, visibilityData),
          const SizedBox(height: 8),
          _buildVisibilityDetails(context, visibilityData),
        ],
      );
    } catch (e) {
      print('能见度数据解析错误: $e');
      return _buildVisibilityError(context);
    }
  }

  Widget _buildVisibilityIndicator(BuildContext context, VisibilityVisualizationData visibilityData, VisibilityLevel level) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      height: 80,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          colors: _getVisibilityColors(level),
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: [
          BoxShadow(
            color: _getVisibilityColors(level)[1].withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          // 背景图案
          Positioned.fill(
            child: CustomPaint(
              painter: VisibilityPatternPainter(level),
            ),
          ),
          // 内容
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      level.description,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _getVisibilityCategory(visibilityData.visibility),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${visibilityData.visibility.toStringAsFixed(1)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'km',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVisibilityDescription(BuildContext context, VisibilityLevel level, VisibilityVisualizationData visibilityData) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          Icon(
            _getVisibilityIcon(level),
            color: _getVisibilityColors(level)[1],
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              visibilityData.description,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVisibilityDetails(BuildContext context, VisibilityVisualizationData visibilityData) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildDetailItem('原始数据', '${(visibilityData.visibility * 1000).toInt()}m', Icons.straighten),
        _buildDetailItem('等级', _getVisibilityLevelText(visibilityData.visibility), Icons.grade),
        _buildDetailItem('状态', _getVisibilityStatus(visibilityData.visibility), Icons.info),
      ],
    );
  }

  Widget _buildDetailItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(
          icon,
          size: 16,
          color: Colors.grey[600],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey[600],
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildVisibilityError(BuildContext context) {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange[200]!),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.visibility_off,
              size: 48,
              color: Colors.orange[400],
            ),
            const SizedBox(height: 8),
            Text(
              '能见度数据不可用',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.orange[700],
              ),
            ),
          ],
        ),
      ),
    );
  }



  String _getVisibilityCategory(double visibility) {
    if (visibility >= 10) return '极佳';
    if (visibility >= 5) return '良好';
    if (visibility >= 3) return '一般';
    if (visibility >= 1) return '较差';
    return '很差';
  }

  String _getVisibilityLevelText(double visibility) {
    if (visibility >= 10) return '1级';
    if (visibility >= 5) return '2级';
    if (visibility >= 3) return '3级';
    if (visibility >= 1) return '4级';
    return '5级';
  }

  String _getVisibilityStatus(double visibility) {
    if (visibility >= 10) return '优秀';
    if (visibility >= 5) return '良好';
    if (visibility >= 3) return '中等';
    if (visibility >= 1) return '较差';
    return '危险';
  }

  IconData _getVisibilityIcon(VisibilityLevel level) {
    switch (level) {
      case VisibilityLevel.excellent:
        return Icons.wb_sunny;
      case VisibilityLevel.good:
        return Icons.visibility;
      case VisibilityLevel.moderate:
        return Icons.remove_red_eye;
      case VisibilityLevel.poor:
        return Icons.visibility_off;
      case VisibilityLevel.veryPoor:
        return Icons.warning;
    }
  }



  List<Color> _getVisibilityColors(VisibilityLevel level) {
    switch (level) {
      case VisibilityLevel.excellent:
        return [Colors.green.shade400, Colors.green.shade600];
      case VisibilityLevel.good:
        return [Colors.lightGreen.shade400, Colors.lightGreen.shade600];
      case VisibilityLevel.moderate:
        return [Colors.yellow.shade400, Colors.orange.shade500];
      case VisibilityLevel.poor:
        return [Colors.orange.shade500, Colors.red.shade500];
      case VisibilityLevel.veryPoor:
        return [Colors.red.shade500, Colors.red.shade700];
    }
  }
}

/// 云底高度图可视化组件
class CloudHeightWidget extends WeatherVisualizationWidget {
  const CloudHeightWidget({
    Key? key,
    required WeatherData weatherData,
  }) : super(key: key, weatherData: weatherData);

  @override
  State<CloudHeightWidget> createState() => _CloudHeightWidgetState();
}

class _CloudHeightWidgetState extends WeatherVisualizationState<CloudHeightWidget> {
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Card(
      elevation: 4,
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.cloud,
                  color: Theme.of(context).primaryColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  '云底高度',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildCloudContent(context),
          ],
        ),
      ),
    );
  }

  Widget _buildCloudContent(BuildContext context) {
    try {
      final cloudData = getCachedData<List<CloudLayerVisualizationData>>('cloudData', () => WeatherDataParser.parseCloudData(widget.weatherData));
      
      if (cloudData.isEmpty) {
        return _buildNoCloudsDisplay(context);
      }
      
      return Column(
        children: [
          SizedBox(
            height: 220,
            child: _buildCloudChart(cloudData),
          ),
          const SizedBox(height: 16),
          _buildCloudSummary(context, cloudData),
        ],
      );
    } catch (e) {
      print('云层数据解析错误: $e');
      return _buildCloudError(context);
    }
  }

  Widget _buildCloudChart(List<CloudLayerVisualizationData> cloudData) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 800),
      child: SfCartesianChart(
        plotAreaBorderWidth: 0,
        primaryXAxis: CategoryAxis(
          title: AxisTitle(
            text: '云层类型',
            textStyle: const TextStyle(fontSize: 12),
          ),
          majorGridLines: const MajorGridLines(width: 0),
          axisLine: const AxisLine(width: 0),
        ),
        primaryYAxis: NumericAxis(
          title: AxisTitle(
            text: '高度 (ft)',
            textStyle: const TextStyle(fontSize: 12),
          ),
          minimum: 0,
          maximum: _getMaxHeight(cloudData) * 1.2,
          majorGridLines: MajorGridLines(
            width: 1,
            color: Colors.grey[300],
          ),
          axisLine: const AxisLine(width: 0),
        ),
        series: <CartesianSeries<dynamic, String>>[
          ColumnSeries<dynamic, String>(
            dataSource: cloudData,
            xValueMapper: (dynamic cloud, _) => _getCloudTypeDisplay(cloud.coverage),
            yValueMapper: (dynamic cloud, _) => cloud.height,
            pointColorMapper: (dynamic cloud, _) => _getCloudColorFromEnum(cloud.coverage),
            borderRadius: const BorderRadius.all(Radius.circular(8)),
            width: 0.8,
            spacing: 0.1,
            dataLabelSettings: const DataLabelSettings(
              isVisible: true,
              labelAlignment: ChartDataLabelAlignment.top,
              textStyle: TextStyle(fontSize: 10),
            ),
          ),
        ],
        tooltipBehavior: TooltipBehavior(
          enable: true,
          format: 'point.x: point.y ft',
          textStyle: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }

  Widget _buildCloudSummary(BuildContext context, List<CloudLayerVisualizationData> cloudData) {
    final totalLayers = cloudData.length;
    final lowestCloud = cloudData.isNotEmpty ? cloudData.reduce((a, b) => a.height < b.height ? a : b) : null;
    final highestCloud = cloudData.isNotEmpty ? cloudData.reduce((a, b) => a.height > b.height ? a : b) : null;
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildSummaryItem('云层数', '$totalLayers层', Icons.layers),
          if (lowestCloud != null)
            _buildSummaryItem('最低', '${lowestCloud.height}ft', Icons.arrow_downward),
          if (highestCloud != null)
            _buildSummaryItem('最高', '${highestCloud.height}ft', Icons.arrow_upward),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(
          icon,
          size: 16,
          color: Colors.blue[600],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.blue[600],
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildNoCloudsDisplay(BuildContext context) {
    return Container(
      height: 150,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.blue[100]!, Colors.blue[50]!],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.wb_sunny,
              size: 48,
              color: Colors.orange[400],
            ),
            const SizedBox(height: 8),
            Text(
              '晴空万里',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.blue[700],
              ),
            ),
            Text(
              '无云层数据',
              style: TextStyle(
                fontSize: 14,
                color: Colors.blue[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCloudError(BuildContext context) {
    return Container(
      height: 150,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off,
              size: 48,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 8),
            Text(
              '云层数据不可用',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _getMaxHeight(List<dynamic> cloudData) {
    if (cloudData.isEmpty) return 10000;
    final maxHeight = cloudData.map((cloud) => cloud.height).reduce((a, b) => a > b ? a : b);
    return maxHeight < 5000 ? 10000 : maxHeight;
  }

  String _getCloudTypeDisplay(dynamic coverage) {
    // Handle both CloudCoverage enum and String types
    String coverageStr;
    if (coverage is String) {
      coverageStr = coverage;
    } else {
      // Assume it's CloudCoverage enum, convert to string representation
      coverageStr = coverage.toString().split('.').last.toUpperCase();
      // Map enum values to METAR codes
      switch (coverageStr) {
        case 'FEW':
          coverageStr = 'FEW';
          break;
        case 'SCATTERED':
          coverageStr = 'SCT';
          break;
        case 'BROKEN':
          coverageStr = 'BKN';
          break;
        case 'OVERCAST':
          coverageStr = 'OVC';
          break;
        case 'CLEAR':
          coverageStr = 'CLR';
          break;
        default:
          coverageStr = 'CLR';
      }
    }
    
    return _getCloudTypeDisplayFromString(coverageStr);
  }

  String _getCloudTypeDisplayFromString(String coverage) {
    switch (coverage) {
      case 'FEW':
        return '少云';
      case 'SCT':
        return '散云';
      case 'BKN':
        return '多云';
      case 'OVC':
        return '阴天';
      case 'CLR':
        return '晴空';
      default:
        return coverage;
    }
  }



  Color _getCloudColor(String coverage) {
    switch (coverage) {
      case 'FEW':
        return Colors.lightBlue.shade200;
      case 'SCT':
        return Colors.blue.shade300;
      case 'BKN':
        return Colors.blue.shade500;
      case 'OVC':
        return Colors.grey.shade600;
      case 'CLR':
        return Colors.orange.shade200;
      default:
        return Colors.grey.shade300;
    }
  }

  Color _getCloudColorFromEnum(dynamic coverage) {
    // Handle both CloudCoverage enum and String types
    String coverageStr;
    if (coverage is String) {
      coverageStr = coverage;
    } else {
      // Assume it's CloudCoverage enum, convert to string representation
      coverageStr = coverage.toString().split('.').last.toUpperCase();
      // Map enum values to METAR codes
      switch (coverageStr) {
        case 'FEW':
          coverageStr = 'FEW';
          break;
        case 'SCATTERED':
          coverageStr = 'SCT';
          break;
        case 'BROKEN':
          coverageStr = 'BKN';
          break;
        case 'OVERCAST':
          coverageStr = 'OVC';
          break;
        case 'CLEAR':
          coverageStr = 'CLR';
          break;
        default:
          coverageStr = 'CLR';
      }
    }
    
    return _getCloudColor(coverageStr);
  }
}



/// 能见度图案绘制器
class VisibilityPatternPainter extends CustomPainter {
  final VisibilityLevel level;
  
  VisibilityPatternPainter(this.level);
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    
    // 根据能见度等级绘制不同的图案
    switch (level) {
      case VisibilityLevel.excellent:
        _drawSunPattern(canvas, size, paint);
        break;
      case VisibilityLevel.good:
        _drawClearPattern(canvas, size, paint);
        break;
      case VisibilityLevel.moderate:
        _drawHazePattern(canvas, size, paint);
        break;
      case VisibilityLevel.poor:
        _drawFogPattern(canvas, size, paint);
        break;
      case VisibilityLevel.veryPoor:
        _drawDenseFogPattern(canvas, size, paint);
        break;
    }
  }
  
  void _drawSunPattern(Canvas canvas, Size size, Paint paint) {
    // 绘制太阳光线图案
    final center = Offset(size.width * 0.8, size.height * 0.3);
    for (int i = 0; i < 8; i++) {
      final angle = i * 3.14159 / 4;
      final start = Offset(
        center.dx + 15 * math.cos(angle),
        center.dy + 15 * math.sin(angle),
      );
      final end = Offset(
        center.dx + 25 * math.cos(angle),
        center.dy + 25 * math.sin(angle),
      );
      canvas.drawLine(start, end, paint);
    }
  }
  
  void _drawClearPattern(Canvas canvas, Size size, Paint paint) {
    // 绘制清晰的波浪线
    final path = Path();
    path.moveTo(0, size.height * 0.7);
    for (double x = 0; x < size.width; x += 20) {
      path.lineTo(x + 10, size.height * 0.6);
      path.lineTo(x + 20, size.height * 0.7);
    }
    canvas.drawPath(path, paint);
  }
  
  void _drawHazePattern(Canvas canvas, Size size, Paint paint) {
    // 绘制薄雾图案
    for (int i = 0; i < 3; i++) {
      final y = size.height * (0.3 + i * 0.2);
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        paint..strokeWidth = 0.5,
      );
    }
  }
  
  void _drawFogPattern(Canvas canvas, Size size, Paint paint) {
    // 绘制雾气图案
    for (int i = 0; i < 5; i++) {
      final y = size.height * (0.2 + i * 0.15);
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width * 0.8, y),
        paint..strokeWidth = 1.0,
      );
    }
  }
  
  void _drawDenseFogPattern(Canvas canvas, Size size, Paint paint) {
    // 绘制浓雾图案
    for (int i = 0; i < 8; i++) {
      final y = size.height * (0.1 + i * 0.1);
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        paint..strokeWidth = 1.5,
      );
    }
  }
  
  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}