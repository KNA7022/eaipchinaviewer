import 'package:flutter/material.dart';
import '../models/aip_model.dart';
import '../services/api_service.dart';
import 'pdf_viewer_screen.dart';
import '../services/auth_service.dart';
import '../models/version_model.dart';  // 添加这个导入
import 'package:intl/intl.dart';  // 添加这一行导入

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

  // 添加搜索相关的状态变量
  final List<AipItem> _filteredItems = [];
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _loadVersions();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadVersions() async {
    try {
      final api = ApiService();
      final packages = await api.getPackageList();
      if (packages != null && packages['data'] != null) {
        final List<dynamic> data = packages['data']['data'] as List;
        _versions = data.map((item) => EaipVersion.fromJson(item)).toList();
        
        // 按日期和版本号排序
        _versions.sort((a, b) => b.effectiveDate.compareTo(a.effectiveDate));
        
        // 设置当前版本
        final currentVersion = _versions.firstWhere(
          (v) => v.status == 'CURRENTLY_ISSUE',
          orElse: () => _versions.first,
        );
        setState(() {
          _currentVersion = currentVersion.name;
          _loadDataForVersion(_currentVersion);
        });
      }
    } catch (e) {
      print('加载版本列表失败: $e');
    }
  }

  Future<void> _loadData() async {
    try {
      setState(() => _isLoading = true);
      
      final api = ApiService();
      final List<dynamic>? data = await api.getCurrentAipStructure();
      
      if (data != null) {
        // 创建项目列表并立即排序
        final items = data
            .map((item) => AipItem.fromJson(item as Map<String, dynamic>))
            .toList();
        final sortedItems = _sortAndProcessItems(items);
        
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
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载失败: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadDataForVersion(String version) async {
    setState(() {
      _isLoading = true;
      _selectedPdfUrl = null;  // 清空当前选中的PDF
      _selectedTitle = null;
      _searchController.clear();
      _searchQuery = '';
      _isSearching = false;
      _filteredItems.clear();
    });
    
    try {
      final api = ApiService();
      final List<dynamic>? data = await api.getAipStructureForVersion(version);
      
      if (data != null) {
        final items = data.map((item) => 
          AipItem.fromJson(item as Map<String, dynamic>)
        ).toList();
        
        // 对所有项目进行递归排序
        final sortedItems = _sortAndProcessItems(items);
        
        setState(() {
          _aipItems.clear();
          _aipItems.addAll(sortedItems);
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('获取数据失败')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载失败: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
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

  // 添加搜索方法
  void _handleSearch(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
      _isSearching = _searchQuery.isNotEmpty;
      _filteredItems.clear();
      
      if (_isSearching) {
        // 递归搜索函数
        void searchInItems(List<AipItem> items) {
          for (var item in items) {
            if (item.nameCn.toLowerCase().contains(_searchQuery)) {
              _filteredItems.add(item);
            }
            if (item.children.isNotEmpty) {
              searchInItems(item.children);
            }
          }
        }
        
        searchInItems(_aipItems);
      }
    });
  }

  Widget _buildListItem(BuildContext context, AipItem item) {
    // 如果是空项，不显示
    if (item.nameCn.isEmpty && item.children.isEmpty) {
      return const SizedBox.shrink();
    }

    // 调试输出
    if (item.nameCn.startsWith('ENR')) {
      print('构建项: ${item.nameCn}, 子项数量: ${item.children.length}');
    }
    
    // 如果有子项，创建可展开的项（注意：空列表也被认为是空）
    if (item.children.isNotEmpty) {
      final validChildren = item.children
          .where((child) => child.nameCn.isNotEmpty)
          .toList();
          
      print('有效子项数量: ${validChildren.length}');

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('航图查看器'),
        actions: [
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
                            // 添加生效和失效日期显示
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
            onPressed: _isLoading ? null : _loadData,
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
                hintText: '搜索...',
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
              onChanged: _handleSearch,
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
