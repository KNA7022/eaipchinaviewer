import 'package:flutter/material.dart';
import '../models/aip_model.dart';
import '../services/api_service.dart';
import 'pdf_viewer_screen.dart';
import '../services/auth_service.dart';
import '../models/version_model.dart';  
import 'package:intl/intl.dart';  
import '../screens/weather_screen.dart'; 
import '../services/theme_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final List<AipItem> _aipItems = [];
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
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSearching = false;
  final Map<String, List<AipItem>> _searchIndex = {};
  final _themeService = ThemeService();

  @override
  void initState() {
    super.initState();
    // 只调用 _loadVersions，因为它会自动加载当前版本的数据
    _loadVersions();
  }

  @override
  void dispose() {
    _searchController.dispose();
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

    try {
      setState(() => _isLoading = true);
      _lastRefreshTime = DateTime.now();  // 记录刷新时间
      _startRefreshCooldown();
      
      // 使用当前选中的版本刷新数据
      if (_currentVersion.isNotEmpty) {
        await _loadDataForVersion(_currentVersion);
      } else {
        // 如果没有当前版本（极少情况），则获取当前生效版本
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
          });
        } else {
          final authService = AuthService();
          await authService.clearAuthData();
          if (mounted) {
            Navigator.of(context).pushReplacementNamed('/login');
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载失败: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadDataForVersion(String version) async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
      _selectedPdfUrl = null;
      _selectedTitle = null;
      _searchController.clear();
      _searchQuery = '';
      _isSearching = false;
      _filteredItems.clear();
    });
    
    try {
      final api = ApiService();
      final List<dynamic>? data = await api.getAipStructureForVersion(version);
      
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
      });
    }
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
    setState(() {
      _searchQuery = query.toLowerCase();
      _isSearching = _searchQuery.isNotEmpty;
      _filteredItems.clear();
      
      if (_isSearching) {
        final searchWords = _searchQuery.split(RegExp(r'\s+'))
          ..removeWhere((word) => word.isEmpty);
        
        if (searchWords.isEmpty) return;
        
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
    });
  }

  Widget _buildListItem(BuildContext context, AipItem item) {
    // 如果是空项，不显示
    if (item.nameCn.isEmpty && item.children.isEmpty) {
      return const SizedBox.shrink();
    }

    
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
            trailing: item.pdfPath?.isNotEmpty == true
                ? IconButton(
                    icon: Icon(
                      Icons.picture_as_pdf,
                      color: _selectedPdfUrl == item.pdfPath 
                          ? Theme.of(context).primaryColor 
                          : Colors.grey,
                    ),
                    onPressed: () => _handlePdfSelect(item.pdfPath, item.nameCn),
                    tooltip: '查看PDF',
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
      trailing: item.pdfPath?.isNotEmpty == true
          ? IconButton(
              icon: Icon(
                Icons.picture_as_pdf,
                color: _selectedPdfUrl == item.pdfPath 
                    ? Theme.of(context).primaryColor 
                    : Colors.grey,
              ),
              onPressed: () => _handlePdfSelect(item.pdfPath, item.nameCn),
              tooltip: '查看PDF',
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
                  
                  final statusConfig = isCurrent
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
            ],
          ),
          body: Row(
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
                onPressed: () => setState(() => _isDrawerOpen = !_isDrawerOpen),
              ),
              // 右侧主内容区
              Expanded(
                child: _selectedPdfUrl != null
                    ? PdfViewerScreen(url: _selectedPdfUrl!, title: _selectedTitle ?? '')
                    : const Center(child: Text('请选择要查看的文档')),
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
          // 搜索框
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '输入关键词后按回车搜索...',
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
              textInputAction: TextInputAction.search, // 设置键盘回车键为搜索
              onSubmitted: _handleSearch, // 按下回车时触发搜索
              onChanged: (value) {
                // 仅更新搜索框状态，不执行搜索
                setState(() {
                  _searchQuery = value.toLowerCase();
                  _isSearching = _searchQuery.isNotEmpty;
                  if (!_isSearching) {
                    _filteredItems.clear();
                  }
                });
              },
            ),
          ),
          // 文档列表
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    children: (_isSearching ? _filteredItems : _aipItems)
                        .map((item) => _buildListItem(context, item))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

// 添加状态配置类
class _StatusConfig {
  final String text;
  final Color color;
  
  const _StatusConfig(this.text, this.color);
}
