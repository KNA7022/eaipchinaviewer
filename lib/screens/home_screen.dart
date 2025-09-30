import 'package:flutter/material.dart';
import '../models/aic_model.dart';
import '../models/aip_model.dart';
import '../models/notam_model.dart';
import '../models/sup_model.dart';
import '../services/api_service.dart';
import 'pdf_viewer_screen.dart';
import '../services/auth_service.dart';
import '../models/version_model.dart'; 
import '../services/pdf_service.dart'; 
import '../services/cache_service.dart';
import 'package:intl/intl.dart';  
import '../screens/weather_screen.dart'; 
import '../services/theme_service.dart';
import '../services/update_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final List<AipItem> _aipItems = [];
  final List<SupItem> _supItems = [];
  final List<AicItem> _aicItems = [];
  final List<NotamItem> _notamItems = [];
  bool _isLoading = false;
  final double _drawerWidth = 300.0;
  bool _isDrawerOpen = true;
  String? _selectedPdfUrl;
  String? _selectedTitle;
  String _currentVersion = '';
  List<EaipVersion> _versions = [];
  DateTime? _lastRefreshTime;
  bool _isRefreshCooling = false;
  static const _refreshCooldown = Duration(seconds: 15);
  final List<AipItem> _filteredItems = [];
  final List<SupItem> _filteredSupItems = [];
  final List<AicItem> _filteredAicItems = [];
  final List<NotamItem> _filteredNotamItems = [];
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSearching = false;
  final Map<String, List<AipItem>> _searchIndex = {};
  // 显示类型：0 = AIP, 1 = SUP, 2 = AIC, 3 = NOTAM
  int _displayType = 0;
  final _themeService = ThemeService();
  final ScrollController _sidebarScrollController = ScrollController();
  double _lastScrollPosition = 0;
  // 记录每个版本的滚动位置
  final Map<String, double> _scrollPositions = {};
  final _sidebarScrollKey = const PageStorageKey<String>('sidebar_scroll');

  @override
  void initState() {
    super.initState();
    // 只调用 _loadVersions，因为它会自动加载当前版本的数据
    _loadVersions();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _sidebarScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadVersions() async {
    if (!mounted) return;
    try {
      setState(() => _isLoading = true);
      final api = ApiService();
      final packages = await api.getPackageList();
      if (!mounted) return;
      
      if (packages == null) {
        // 如果获取数据为空，直接跳转到登录界面
        final authService = AuthService();
        await authService.clearAuthData();
        Navigator.of(context).pushReplacementNamed('/login');
        return;
      }

      if (packages['data'] != null) {
        final List<dynamic> data = packages['data']['data'] as List;
        _versions = data.map((item) => EaipVersion.fromJson(item)).toList();
        
        _versions.sort((a, b) => b.effectiveDate.compareTo(a.effectiveDate));
        
        if (!mounted) return;
        
        // 先找到当前生效版本
        final currentVersion = _versions.firstWhere(
          (v) => v.status == 'CURRENTLY_ISSUE',
          orElse: () => _versions.first,
        );
        
        // 设置当前版本并加载数据
        _currentVersion = currentVersion.name;
        
        // 记录刷新时间和开始冷却
        _lastRefreshTime = DateTime.now();
        _startRefreshCooldown();
        
        // 加载当前版本的数据
        await _loadDataForVersion(_currentVersion);
      }
    } catch (e) {
      print('加载版本列表失败: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载版本列表失败: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // 添加检查刷新冷却的方法
  bool _canRefresh() {
    if (_lastRefreshTime == null) return true;
    final timeSinceLastRefresh = DateTime.now().difference(_lastRefreshTime!);
    return timeSinceLastRefresh >= _refreshCooldown;
  }

  void _startRefreshCooldown() {
    setState(() => _isRefreshCooling = true);
    Future.delayed(_refreshCooldown, () {
      if (mounted) {
        setState(() => _isRefreshCooling = false);
      }
    });
  }

  Future<void> _loadData() async {
    if (!_canRefresh()) {
      final remainingTime = _refreshCooldown - DateTime.now().difference(_lastRefreshTime!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('请等待${remainingTime.inSeconds}秒后再试'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    // 保存当前版本的滚动位置
    if (_sidebarScrollController.hasClients) {
      _scrollPositions[_currentVersion] = _sidebarScrollController.offset;
      _lastScrollPosition = _sidebarScrollController.offset;
    }

    try {
      setState(() => _isLoading = true);
      _lastRefreshTime = DateTime.now();  // 记录刷新时间
      _startRefreshCooldown();
      
      // 使用当前选中的版本刷新数据
      if (_currentVersion.isNotEmpty) {
        // 刷新不改变版本，所以不需要清除滚动位置
        await _loadCurrentVersionData();
      } else {
        // 如果没有当前版本（极少情况），则获取当前生效版本
        await _loadDefaultVersionData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载失败: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadDataForVersion(String version) async {
    if (!mounted) return;
    
    // 切换版本时清除滚动位置缓存，不保留上一个版本的位置
    _lastScrollPosition = 0;
    
    setState(() {
      _isLoading = true;
      _selectedPdfUrl = null;
      _selectedTitle = null;
      _searchController.clear();
      _searchQuery = '';
      _isSearching = false;
      _filteredItems.clear();
      _filteredSupItems.clear();
    });
    
    try {
      final api = ApiService();
      final Future<List<dynamic>?> aipFuture = api.getAipStructureForVersion(version);
      final Future<List<dynamic>?> supFuture = api.getSupStructureForVersion(version);
      final Future<List<dynamic>?> aicFuture = api.getAicStructureForVersion(version);
      final Future<List<dynamic>?> notamFuture = api.getNotamDataForVersion(version);
      
      final results = await Future.wait([aipFuture, supFuture, aicFuture, notamFuture]);
      final List<dynamic>? aipData = results[0];
      final List<dynamic>? supData = results[1];
      final List<dynamic>? aicData = results[2];
      final List<dynamic>? notamData = results[3];
      
      if (!mounted) return;

      if (aipData == null) {
        // token失效，直接清除认证数据并跳转到登录页面
        final authService = AuthService();
        await authService.clearAuthData();
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/login');
        return;
      }

      final aipItems = aipData.map((item) => 
        AipItem.fromJson(item as Map<String, dynamic>)
      ).toList();
      
      final sortedAipItems = _sortAndProcessItems(aipItems);
      
      final supItems = supData?.map((item) =>
        SupItem.fromJson(item as Map<String, dynamic>)
      ).toList() ?? [];
      
      // 按照发布日期降序排序SUP
      supItems.sort((a, b) => b.pubDate.compareTo(a.pubDate));

      final aicItems = aicData?.map((item) =>
        AicItem.fromJson(item as Map<String, dynamic>)
      ).toList() ?? [];
      
      // 按照发布日期降序排序AIC
      aicItems.sort((a, b) => b.pubDate.compareTo(a.pubDate));
      
      if (!mounted) return;
      final notamItems = notamData?.map((item) =>
        NotamItem.fromJson(item as Map<String, dynamic>)
      ).toList() ?? [];
      
      // 按照系列名称排序NOTAM
      notamItems.sort((a, b) => a.seriesName.compareTo(b.seriesName));

      setState(() {
        _currentVersion = version;
        _aipItems.clear();
        _aipItems.addAll(sortedAipItems);
        _supItems.clear();
        _supItems.addAll(supItems);
        _aicItems.clear();
        _aicItems.addAll(aicItems);
        _notamItems.clear();
        _notamItems.addAll(notamItems);
        _buildSearchIndex(sortedAipItems);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载失败: $e')),
      );
    }
  }

  void _handleVersionChange(String version) {
    setState(() {
      _currentVersion = version;
    });
    _loadDataForVersion(version);
  }

  void _handlePdfSelect(String? pdfUrl, String? title) {
    if (pdfUrl != null) {
      // 先保存当前的滚动位置
      if (_sidebarScrollController.hasClients) {
        _scrollPositions[_currentVersion] = _sidebarScrollController.offset;
        _lastScrollPosition = _sidebarScrollController.offset;
      }

      // 先设置为 null 强制重建组件
      setState(() {
        _selectedPdfUrl = null;
        _selectedTitle = null;
      });
      
      // 使用监听器获取最新的设置值
      final autoCollapse = _themeService.autoCollapseNotifier.value;
      if (autoCollapse) {
        setState(() {
          _isDrawerOpen = false;
        });
      }
      
      // 等待下一帧再设置新值
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _selectedPdfUrl = pdfUrl;
          _selectedTitle = title;
        });
        
        // 恢复滚动位置 (总是启用)
        if (_isDrawerOpen) {
          _restoreScrollPosition();
        }
      });
    }
  }
  
  // 添加单独的方法来恢复滚动位置
  void _restoreScrollPosition() {
    // 确保有有效的滚动位置
    if (_lastScrollPosition <= 0 && _scrollPositions.containsKey(_currentVersion)) {
      _lastScrollPosition = _scrollPositions[_currentVersion] ?? 0;
    }
    
    // 使用双重延迟确保在布局完成后恢复滚动位置
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && _sidebarScrollController.hasClients && _lastScrollPosition > 0) {
          try {
            // 确保不超出边界
            final maxScrollExtent = _sidebarScrollController.position.maxScrollExtent;
            final targetPosition = _lastScrollPosition.clamp(0.0, maxScrollExtent);
            _sidebarScrollController.jumpTo(targetPosition);
          } catch (e) {
            print('恢复滚动位置失败: $e');
          }
        }
      });
    });
  }

  List<AipItem> _sortAndProcessItems(List<AipItem> items) {
    // 先构建层级关系
    final processedItems = AipItem.buildHierarchy(items);
    
    // 添加调试输出
    for (var item in processedItems) {
      if (item.nameCn.startsWith('ENR')) {
        print('顶级项: ${item.nameCn}');
        for (var child in item.children) {
          print('  子项: ${child.nameCn}');
          for (var grandChild in child.children) {
            print('    孙项: ${grandChild.nameCn}');
          }
        }
      }
    }
    
    void recursiveSort(List<AipItem> items) {
      // 先对当前层级的项目进行排序
      items.sort((a, b) => a.compareTo(b));
      
      // 对每个项目的子项进行递归排序
      for (var item in items) {
        if (item.children.isNotEmpty) {
          recursiveSort(item.children);
        }
      }
    }

    recursiveSort(processedItems);
    return processedItems;
  }

  // 添加索引构建方法
  void _buildSearchIndex(List<AipItem> items) {
    _searchIndex.clear();
    
    void addToIndex(AipItem item) {
      // 将项目名称分词（按空格和常见分隔符）
      final words = item.nameCn.toLowerCase().split(RegExp(r'[\s\-_.,]'))
        ..removeWhere((word) => word.isEmpty);
      
      // 为每个词建立索引
      for (var word in words) {
        _searchIndex.putIfAbsent(word, () => []).add(item);
        
        // 为词的前缀也建立索引（实现模糊匹配）
        if (word.length > 2) {
          for (var i = 2; i < word.length; i++) {
            final prefix = word.substring(0, i);
            _searchIndex.putIfAbsent(prefix, () => []).add(item);
          }
        }
      }
      
      // 递归处理子项
      for (var child in item.children) {
        addToIndex(child);
      }
    }
    
    // 处理所有顶级项
    for (var item in items) {
      addToIndex(item);
    }
  }

  void _handleSearch(String query) {
    // 搜索时总是保存当前的滚动位置
    if (_sidebarScrollController.hasClients) {
      _scrollPositions[_currentVersion] = _sidebarScrollController.offset;
      _lastScrollPosition = _sidebarScrollController.offset;
    }
    
    setState(() {
      _searchQuery = query.toLowerCase();
      _isSearching = _searchQuery.isNotEmpty;
      _filteredItems.clear();
      _filteredSupItems.clear();
      _filteredAicItems.clear();
      
      if (_isSearching) {
        final searchWords = _searchQuery.split(RegExp(r'\s+'))
          ..removeWhere((word) => word.isEmpty);
        
        if (searchWords.isEmpty) return;
        
        if (_displayType == 1) {
          // 搜索SUP项
          _filteredSupItems.addAll(_supItems.where((item) {
            final searchText = '${item.serial} ${item.localSubject} ${item.subject} ${item.chapterType}'.toLowerCase();
            return searchWords.any((word) => searchText.contains(word));
          }));
          
          // 按相关度排序（包含更多搜索词的排在前面）
          _filteredSupItems.sort((a, b) {
            final aSearchText = '${a.serial} ${a.localSubject} ${a.subject} ${a.chapterType}'.toLowerCase();
            final bSearchText = '${b.serial} ${b.localSubject} ${b.subject} ${b.chapterType}'.toLowerCase();
            final aRelevance = searchWords.where((word) => aSearchText.contains(word)).length;
            final bRelevance = searchWords.where((word) => bSearchText.contains(word)).length;
            if (bRelevance != aRelevance) {
              return bRelevance.compareTo(aRelevance);
            }
            // 如果相关度相同，按发布日期降序排序
            return b.pubDate.compareTo(a.pubDate);
          });
        } else if (_displayType == 2) {
          // 搜索AIC项
          _filteredAicItems.addAll(_aicItems.where((item) {
            final searchText = '${item.serial} ${item.localSubject} ${item.subject} ${item.chapterType}'.toLowerCase();
            return searchWords.any((word) => searchText.contains(word));
          }));
          
          // 按相关度排序（包含更多搜索词的排在前面）
          _filteredAicItems.sort((a, b) {
            final aSearchText = '${a.serial} ${a.localSubject} ${a.subject} ${a.chapterType}'.toLowerCase();
            final bSearchText = '${b.serial} ${b.localSubject} ${b.subject} ${b.chapterType}'.toLowerCase();
            final aRelevance = searchWords.where((word) => aSearchText.contains(word)).length;
            final bRelevance = searchWords.where((word) => bSearchText.contains(word)).length;
            if (bRelevance != aRelevance) {
              return bRelevance.compareTo(aRelevance);
            }
            // 如果相关度相同，按发布日期降序排序
            return b.pubDate.compareTo(a.pubDate);
          });
        } else if (_displayType == 3) {
          // 搜索NOTAM项
          _filteredNotamItems.clear();
          _filteredNotamItems.addAll(_notamItems.where((item) {
            final searchText = '系列${item.seriesName}'.toLowerCase();
            return searchWords.any((word) => searchText.contains(word));
          }));
          
          // 按系列名称排序
          _filteredNotamItems.sort((a, b) => a.seriesName.compareTo(b.seriesName));
        } else {
          // 使用 Set 去重
          final resultSet = <AipItem>{};
          
          // 对每个搜索词进行查找
          for (var word in searchWords) {
            // 查找完整词匹配
            final exactMatches = _searchIndex[word] ?? [];
            resultSet.addAll(exactMatches);
            
            // 查找前缀匹配
            _searchIndex.forEach((key, items) {
              if (key.startsWith(word)) {
                resultSet.addAll(items);
              }
            });
          }
          
          _filteredItems.addAll(resultSet);
          
          // 按相关度排序（包含更多搜索词的排在前面）
          _filteredItems.sort((a, b) {
            final aRelevance = searchWords.where((word) => 
              a.nameCn.toLowerCase().contains(word)).length;
            final bRelevance = searchWords.where((word) => 
              b.nameCn.toLowerCase().contains(word)).length;
            return bRelevance.compareTo(aRelevance);
          });
        }
      } else if (_isDrawerOpen) {
        // 如果取消搜索，则恢复之前的位置
        _lastScrollPosition = _scrollPositions[_currentVersion] ?? 0;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _restoreScrollPosition();
        });
        return;
      }
    });
    
    // 搜索后，始终滚动到顶部
    if (_sidebarScrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _sidebarScrollController.jumpTo(0);
      });
    }
  }

  Widget _buildListItem(BuildContext context, AipItem item) {
    // 如果是空项，不显示
    if (item.nameCn.isEmpty && item.children.isEmpty) {
      return const SizedBox.shrink();
    }

    // 获取缓存状态
    final pdfService = PdfService();
    
    // 如果有子项，创建可展开的项（注意：空列表也被认为是空）
    if (item.children.isNotEmpty) {
      final validChildren = item.children
          .where((child) => child.nameCn.isNotEmpty)
          .toList();
          

      if (validChildren.isNotEmpty) {
        return Theme(
          data: Theme.of(context).copyWith(
            dividerColor: Colors.transparent,
          ),
          child: ExpansionTile(
            key: PageStorageKey<String>(item.nameCn),
            initiallyExpanded: false,  // 确保初始状态为折叠
            maintainState: false,      // 不保持展开状态
            controlAffinity: ListTileControlAffinity.leading,
            trailing: item.pdfPath != null && item.pdfPath!.isNotEmpty
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FutureBuilder<bool>(
                        future: item.pdfPath != null ? pdfService.isPdfCached(item.pdfPath!, version: _currentVersion) : Future.value(false),
                        builder: (context, snapshot) {
                          if (snapshot.hasData && snapshot.data == true) {
                            return const Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 16,
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.picture_as_pdf,
                          color: _selectedPdfUrl == item.pdfPath 
                              ? Theme.of(context).primaryColor 
                              : Colors.grey,
                        ),
                        onPressed: () => _handlePdfSelect(item.pdfPath, item.nameCn),
                        tooltip: '查看PDF',
                      ),
                    ],
                  )
                : null,
            title: Text(
              item.nameCn,
              style: TextStyle(
                // 使用 hasModifiedChildren 来决定颜色
                color: item.hasModifiedChildren ? Colors.red : null,
                fontWeight: _selectedTitle == item.nameCn ? FontWeight.bold : null,
              ),
            ),
            expandedAlignment: Alignment.centerLeft,
            tilePadding: const EdgeInsets.symmetric(horizontal: 16.0),
            iconColor: Colors.grey,
            collapsedIconColor: Colors.grey,
            children: validChildren
                .map((child) => Padding(
                      padding: const EdgeInsets.only(left: 20.0),
                      child: _buildListItem(context, child),
                    ))
                .toList(),
          ),
        );
      }
    }
    
    // 如果没有有效子项，创建普通列表项
    return ListTile(
      title: Text(
        item.nameCn,
        style: TextStyle(
          // 使用 hasModifiedChildren 来决定颜色
          color: item.hasModifiedChildren ? Colors.red : null,
          fontWeight: _selectedTitle == item.nameCn ? FontWeight.bold : null,
        ),
      ),
      trailing: item.pdfPath != null && item.pdfPath!.isNotEmpty
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FutureBuilder<bool>(
                  future: item.pdfPath != null ? pdfService.isPdfCached(item.pdfPath!, version: _currentVersion) : Future.value(false),
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data == true) {
                      return const Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 16,
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
                IconButton(
                  icon: Icon(
                    Icons.picture_as_pdf,
                    color: _selectedPdfUrl == item.pdfPath 
                        ? Theme.of(context).primaryColor 
                        : Colors.grey,
                  ),
                  onPressed: () => _handlePdfSelect(item.pdfPath, item.nameCn),
                  tooltip: '查看PDF',
                ),
              ],
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _themeService.autoCollapseNotifier,
      builder: (context, autoCollapseSidebar, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('航图查看器'),
            actions: [
              IconButton(
                icon: const Icon(Icons.thunderstorm),
                tooltip: '机场天气',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const WeatherScreen(),
                  ),
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.calendar_today),
                tooltip: '选择版本号',
                initialValue: _currentVersion,
                onSelected: _handleVersionChange,
                itemBuilder: (context) => _versions.map((version) {
                  final bool isCurrent = version.status == 'CURRENTLY_ISSUE';
                  final bool isExpired = version.effectiveDate.isBefore(DateTime.now());
                  final bool isUpcoming = version.effectiveDate.isAfter(DateTime.now());
                  
                  // 检查是否正在下载
                  final isDownloading = UpdateService.currentTask.value?.version == version.name &&
                      UpdateService.currentTask.value?.isDownloading == true;
                  
                  final statusConfig = isDownloading
                      ? _StatusConfig('下载中', Colors.blue)
                      : isCurrent
                          ? _StatusConfig('当前版本', Colors.green)
                          : isExpired
                              ? _StatusConfig('已失效', Colors.grey)
                              : isUpcoming
                                  ? _StatusConfig('即将生效', Colors.orange)
                                  : _StatusConfig('未知状态', Colors.grey);
                  
                  return PopupMenuItem(
                    value: version.name,
                    child: Container(
                      width: 280,
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      version.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: statusConfig.color.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: statusConfig.color),
                                      ),
                                      child: Text(
                                        statusConfig.text,
                                        style: TextStyle(
                                          color: statusConfig.color,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                RichText(
                                  text: TextSpan(
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey[600],
                                    ),
                                    children: [
                                      const TextSpan(text: '生效: '),
                                      TextSpan(
                                        text: DateFormat('yyyy-MM-dd').format(version.effectiveDate),
                                        style: const TextStyle(fontWeight: FontWeight.w500),
                                      ),
                                      const TextSpan(text: '  失效: '),
                                      TextSpan(
                                        text: version.deadlineDate != null 
                                            ? DateFormat('yyyy-MM-dd').format(version.deadlineDate!)
                                            : '${DateFormat('yyyy-MM-dd').format(version.effectiveDate.add(const Duration(days: 28)))} (预计)',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w500,
                                          fontStyle: version.deadlineDate == null ? FontStyle.italic : FontStyle.normal,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_currentVersion == version.name)
                            Icon(
                              Icons.check,
                              color: statusConfig.color,
                              size: 20,
                            ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: (_isLoading || !_canRefresh()) ? null : _loadData,
              ),
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () => Navigator.pushNamed(context, '/settings'),
              ),
              IconButton(
                icon: const Icon(Icons.download),
                tooltip: '下载当期航图包',
                onPressed: () async {
                  // 获取当前界面选中的版本对象
                  final current = _versions.firstWhere(
                    (v) => v.name == _currentVersion,
                    orElse: () => _versions.first,
                  );
                  if (current == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('未获取到当前版本信息')),
                    );
                    return;
                  }
                  // 从 filePath 提取 packageVersion（如 V1.4）
                  final reg = RegExp(r'EAIP\d{4}-\d{2}\.(V[\d.]+)');
                  final match = reg.firstMatch(current.filePath);
                  String packageVersion = 'V1.0';
                  if (match != null && match.groupCount >= 1) {
                    packageVersion = match.group(1)!;
                  }
                  // 调用下载
                  await UpdateService().downloadCurrentAipPackage(
                    context,
                    version: current.name,
                    packageVersion: packageVersion,
                  );
                },
              ),
            ],
          ),
          body: Stack(
            children: [
              Row(
                children: [
                  // 左侧抽屉
                  if (_isDrawerOpen)
                    SizedBox(
                      width: _drawerWidth,
                      child: _buildDrawer(),
                    ),
                  // 抽屉开关按钮
                  IconButton(
                    icon: Icon(_isDrawerOpen ? Icons.chevron_left : Icons.chevron_right),
                    onPressed: _toggleDrawer,
                  ),
                  // 右侧主内容区
                  Expanded(
                    child: _selectedPdfUrl != null
                        ? PdfViewerScreen(url: _selectedPdfUrl!, title: _selectedTitle ?? '', version: _currentVersion)
                        : const Center(child: Text('请选择要查看的文档')),
                  ),
                ],
              ),
              // 底部下载进度条
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ValueListenableBuilder<DownloadTask?>(
                  valueListenable: UpdateService.currentTask,
                  builder: (context, task, child) {
                    if (task == null || !task.isDownloading) return const SizedBox.shrink();
                    return Material(
                      color: Colors.transparent,
                      child: Container(
                        width: double.infinity,
                        color: Colors.black.withOpacity(0.7),
                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: LinearProgressIndicator(
                                value: task.progress,
                                minHeight: 4,
                                backgroundColor: Colors.black12,
                                valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '下载${task.version} ${(task.progress * 100).toStringAsFixed(1)}%',
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                            ),
                            const SizedBox(width: 12),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.white, size: 20),
                              onPressed: () {
                                showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('取消下载'),
                                    content: const Text('确定要取消当前版本的下载吗？'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx, false),
                                        child: const Text('继续下载'),
                                      ),
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx, true),
                                        child: const Text('取消'),
                                      ),
                                    ],
                                  ),
                                ).then((shouldCancel) {
                                  if (shouldCancel == true) {
                                    task.cancel();
                                  }
                                });
                              },
                              tooltip: '取消下载',
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      }
    );
  }

  Widget _buildDrawer() {
    return Container(
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        children: [
          // 切换按钮
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: Row(
              children: [
                Expanded(
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment<int>(
                        value: 0,
                        label: Text('AIP'),
                        icon: Icon(Icons.book),
                      ),
                      ButtonSegment<int>(
                        value: 1,
                        label: Text('SUP'),
                        icon: Icon(Icons.new_releases),
                      ),
                      ButtonSegment<int>(
                        value: 2,
                        label: Text('AIC'),
                        icon: Icon(Icons.info),
                      ),
                      ButtonSegment<int>(
                        value: 3,
                        label: Text('NOTAM'),
                        icon: Icon(Icons.notifications),
                      ),
                    ],
                    selected: {_displayType},
                    onSelectionChanged: (Set<int> newSelection) {
                      setState(() {
                        _displayType = newSelection.first;
                        _searchController.clear();
                        _searchQuery = '';
                        _isSearching = false;
                        _filteredItems.clear();
                        _filteredSupItems.clear();
                        _filteredAicItems.clear();
                        _filteredNotamItems.clear();
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          // 搜索框
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索${_displayType == 0 ? "航行资料" : _displayType == 1 ? "补充通告" : _displayType == 2 ? "航行通告" : "NOTAM"}...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _isSearching
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _handleSearch('');
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: _handleSearch,
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.toLowerCase();
                  _isSearching = _searchQuery.isNotEmpty;
                  if (!_isSearching) {
                    _filteredItems.clear();
                    _filteredSupItems.clear();
                    _filteredAicItems.clear();
                    _filteredNotamItems.clear();
                  }
                });
              },
            ),
          ),
          // 文档列表
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _displayType == 0
                    ? ListView(
                        key: _sidebarScrollKey,
                        controller: _sidebarScrollController,
                        children: (_isSearching ? _filteredItems : _aipItems)
                            .map((item) => _buildListItem(context, item))
                            .toList(),
                      )
                    : _displayType == 1
                        ? ListView.builder(
                            controller: _sidebarScrollController,
                            itemCount: _isSearching
                                ? _filteredSupItems.length
                                : _supItems.length,
                            itemBuilder: (context, index) {
                              final item = _isSearching
                                  ? _filteredSupItems[index]
                                  : _supItems[index];
                              return _buildSupListItem(item);
                            },
                          )
                        : _displayType == 2
                            ? ListView.builder(
                                controller: _sidebarScrollController,
                                itemCount: _isSearching
                                    ? _filteredAicItems.length
                                    : _aicItems.length,
                                itemBuilder: (context, index) {
                                  final item = _isSearching
                                      ? _filteredAicItems[index]
                                      : _aicItems[index];
                                  return _buildAicListItem(item);
                                },
                              )
                            : ListView.builder(
                                controller: _sidebarScrollController,
                                itemCount: _isSearching
                                    ? _filteredNotamItems.length
                                    : _notamItems.length,
                                itemBuilder: (context, index) {
                                  final item = _isSearching
                                      ? _filteredNotamItems[index]
                                      : _notamItems[index];
                                  return _buildNotamListItem(item);
                                },
                              ),
          ),
        ],
      ),
    );
  }

  Widget _buildSupListItem(SupItem item) {
    // 获取缓存状态
    final pdfService = PdfService();
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: ListTile(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                     color: item.isModifiedBool ? Colors.red.withOpacity(0.1) : Colors.blue.withOpacity(0.1),
                     borderRadius: BorderRadius.circular(4),
                     border: Border.all(
                       color: item.isModifiedBool ? Colors.red : Colors.blue,
                     ),
                   ),
                   child: Text(
                     item.serial,
                     style: TextStyle(
                       fontSize: 12,
                       color: item.isModifiedBool ? Colors.red : Colors.blue,
                     ),
                   ),
                ),
                const SizedBox(width: 8),
                if (item.chapterType.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.grey),
                    ),
                    child: Text(
                      item.chapterType,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              item.localSubject,
              style: TextStyle(
                fontSize: 14,
                fontWeight: _selectedTitle == item.localSubject ? FontWeight.bold : null,
              ),
            ),
            Text(
              item.subject,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    '发布: ${item.formattedPubDate}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    '生效: ${item.formattedEffectiveTime}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
              if (item.formattedOutDate.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.event_busy, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      '失效: ${item.formattedOutDate}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
            ],
          ),
        ),
        trailing: item.document.isNotEmpty
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FutureBuilder<bool>(
                    future: pdfService.isPdfCached(item.document, version: _currentVersion),
                    builder: (context, snapshot) {
                      if (snapshot.hasData && snapshot.data == true) {
                        return const Icon(
                          Icons.check_circle,
                          color: Colors.green,
                          size: 16,
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.picture_as_pdf,
                      color: _selectedPdfUrl == item.document
                          ? Theme.of(context).primaryColor
                          : Colors.grey,
                    ),
                    onPressed: () {
                      print('flutter: 开始加载SUP PDF: ${item.pdfUrl}');
                      if (item.pdfUrl != null) {
                        _handlePdfSelect(item.pdfUrl!, item.localSubject);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('无法加载PDF文件')),
                        );
                      }
                    },
                    tooltip: '查看PDF',
                  ),
                ],
              )
            : null,
      ),
    );
  }

  Widget _buildAicListItem(AicItem item) {
    // 获取缓存状态
    final pdfService = PdfService();
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: ListTile(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                     color: item.isModifiedBool ? Colors.red.withOpacity(0.1) : Colors.blue.withOpacity(0.1),
                     borderRadius: BorderRadius.circular(4),
                     border: Border.all(
                       color: item.isModifiedBool ? Colors.red : Colors.blue,
                     ),
                   ),
                   child: Text(
                     item.serial,
                     style: TextStyle(
                       fontSize: 12,
                       color: item.isModifiedBool ? Colors.red : Colors.blue,
                     ),
                   ),
                ),
                const SizedBox(width: 8),
                if (item.chapterType.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.grey),
                    ),
                    child: Text(
                      item.chapterType,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              item.localSubject,
              style: TextStyle(
                fontSize: 14,
                fontWeight: _selectedTitle == item.localSubject ? FontWeight.bold : null,
              ),
            ),
            Text(
              item.subject,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    '发布: ${item.formattedPubDate}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    '生效: ${item.formattedEffectiveTime}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
              if (item.formattedOutDate.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.event_busy, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      '失效: ${item.formattedOutDate}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
            ],
          ),
        ),
        trailing: item.document.isNotEmpty
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FutureBuilder<bool>(
                    future: pdfService.isPdfCached(item.document, version: _currentVersion),
                    builder: (context, snapshot) {
                      if (snapshot.hasData && snapshot.data == true) {
                        return const Icon(
                          Icons.check_circle,
                          color: Colors.green,
                          size: 16,
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.picture_as_pdf,
                      color: _selectedPdfUrl == item.document
                          ? Theme.of(context).primaryColor
                          : Colors.grey,
                    ),
                    onPressed: () {
                      print('flutter: 开始加载AIC PDF: ${item.pdfUrl}');
                      if (item.pdfUrl != null) {
                        _handlePdfSelect(item.pdfUrl!, item.localSubject);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('无法加载PDF文件')),
                        );
                      }
                    },
                    tooltip: '查看PDF',
                  ),
                ],
              )
            : null,
      ),
    );
  }

  Widget _buildNotamListItem(NotamItem item) {
    // 获取缓存状态
    final pdfService = PdfService();
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: ListTile(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.orange),
              ),
              child: Text(
                '系列${item.seriesName}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.orange,
                ),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Row(
            children: [
              Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text(
                '生成时间: ${item.formattedGenerateTime}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
        trailing: item.document.isNotEmpty
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FutureBuilder<bool>(
                    future: pdfService.isPdfCached(item.document, version: _currentVersion),
                    builder: (context, snapshot) {
                      if (snapshot.hasData && snapshot.data == true) {
                        return const Icon(
                          Icons.check_circle,
                          color: Colors.green,
                          size: 16,
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.picture_as_pdf,
                      color: _selectedPdfUrl == item.document
                          ? Theme.of(context).primaryColor
                          : Colors.grey,
                    ),
                    onPressed: () {
                      final api = ApiService();
                      final pdfUrl = api.buildPdfUrl(item.document);
                      print('flutter: 开始加载NOTAM PDF: $pdfUrl');
                      if (pdfUrl != null) {
                        _handlePdfSelect(pdfUrl, '系列${item.seriesName} NOTAM');
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('无法加载PDF文件')),
                        );
                      }
                    },
                    tooltip: '查看PDF',
                  ),
                ],
              )
            : null,
      ),
    );
  }

  void _toggleDrawer() {
    // 保存当前的滚动位置
    if (_isDrawerOpen && _sidebarScrollController.hasClients) {
      _scrollPositions[_currentVersion] = _sidebarScrollController.offset;
      _lastScrollPosition = _sidebarScrollController.offset;
    }
    
    final wasOpen = _isDrawerOpen;
    setState(() => _isDrawerOpen = !_isDrawerOpen);
    
    // 如果打开了抽屉，尝试恢复滚动位置
    if (!wasOpen) {
      _lastScrollPosition = _scrollPositions[_currentVersion] ?? 0;
      _restoreScrollPosition();
    }
  }

  // 添加用于加载当前版本数据的方法
  Future<void> _loadCurrentVersionData() async {
    if (!mounted) return;
    
    try {
      final api = ApiService();
      final List<dynamic>? data = await api.getAipStructureForVersion(_currentVersion);
      
      if (!mounted) return;

      if (data == null) {
        // token失效，直接清除认证数据并跳转到登录页面
        final authService = AuthService();
        await authService.clearAuthData();
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/login');
        return;
      }

      final items = data.map((item) => 
        AipItem.fromJson(item as Map<String, dynamic>)
      ).toList();
      
      final sortedItems = _sortAndProcessItems(items);
      
      if (!mounted) return;
      setState(() {
        _aipItems.clear();
        _aipItems.addAll(sortedItems);
        _buildSearchIndex(sortedItems);
        _isLoading = false;
      });
      
      // 恢复滚动位置
      if (_isDrawerOpen) {
        _restoreScrollPosition();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      throw e;
    }
  }

  // 添加用于加载默认版本数据的方法
  Future<void> _loadDefaultVersionData() async {
    if (!mounted) return;
    
    try {
      final api = ApiService();
      final List<dynamic>? data = await api.getCurrentAipStructure();
      
      if (data != null) {
        final items = data
            .map((item) => AipItem.fromJson(item as Map<String, dynamic>))
            .toList();
        final sortedItems = _sortAndProcessItems(items);
        
        _buildSearchIndex(sortedItems);
        
        setState(() {
          _aipItems.clear();
          _aipItems.addAll(sortedItems);
          _searchController.clear();
          _searchQuery = '';
          _isSearching = false;
          _filteredItems.clear();
          _isLoading = false;
        });
        
        // 恢复滚动位置
        if (_isDrawerOpen) {
          _restoreScrollPosition();
        }
      } else {
        final authService = AuthService();
        await authService.clearAuthData();
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/login');
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      throw e;
    }
  }
}

// 添加状态配置类
class _StatusConfig {
  final String text;
  final Color color;
  
  const _StatusConfig(this.text, this.color);
}
