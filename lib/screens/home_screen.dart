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

  @override
  void initState() {
    super.initState();
    _loadVersions();
    _loadData();
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
    List<AipItem> sortedItems = List.from(items); // 创建副本以避免修改原始列表
    
    void recursiveSort(List<AipItem> items) {
      // 先对当前层级的项目进行排序
      items.sort((a, b) => a.compareTo(b));
      
      // 对每个项目的子项进行递归排序
      for (var item in items) {
        if (item.children.isNotEmpty) {
          List<AipItem> sortedChildren = List.from(item.children);
          recursiveSort(sortedChildren);
          item.children.clear();
          item.children.addAll(sortedChildren);
        }
      }
    }

    recursiveSort(sortedItems);
    return sortedItems;
  }

  Widget _buildListItem(BuildContext context, int index) {
    final item = _aipItems[index];
    
    // 如果是空项，不显示
    if (item.nameCn.isEmpty && item.children.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return ExpansionTile(
      title: Row(
        children: [
          Expanded(
            child: Text(
              item.nameCn,
              style: TextStyle(
                color: item.isModified == 'Y' ? Colors.red : null,
                fontWeight: _selectedTitle == item.nameCn ? FontWeight.bold : null,
              ),
            ),
          ),
          if (item.pdfPath?.isNotEmpty == true)
            IconButton(
              icon: Icon(
                Icons.picture_as_pdf,
                color: _selectedPdfUrl == item.pdfPath ? Theme.of(context).primaryColor : Colors.grey,
              ),
              onPressed: () => _handlePdfSelect(item.pdfPath, item.nameCn),
              tooltip: '查看PDF',
            ),
        ],
      ),
      children: item.children
          .where((child) => child.nameCn.isNotEmpty || child.children.isNotEmpty)
          .map((child) => _buildListItem(context, _aipItems.indexOf(child)))
          .toList(),
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
            tooltip: '切换版本',
            initialValue: _currentVersion,
            onSelected: _handleVersionChange,  // 修改这里
            itemBuilder: (context) => _versions.map((version) {
              return PopupMenuItem(
                value: version.name,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(version.name),
                          Text(
                            '生效日期: ${DateFormat('yyyy-MM-dd').format(version.effectiveDate)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: version.statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: version.statusColor,
                            width: 1,
                          ),
                        ),
                        child: Text(
                          version.statusText,
                          style: TextStyle(
                            color: version.statusColor,
                            fontSize: 12,
                          ),
                        ),
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
              decoration: const InputDecoration(
                hintText: '搜索...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                // TODO: 实现搜索功能
              },
            ),
          ),
          // 文档列表
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _aipItems.length,
                    itemBuilder: (context, index) => _buildListItem(context, index),
                  ),
          ),
        ],
      ),
    );
  }
}
