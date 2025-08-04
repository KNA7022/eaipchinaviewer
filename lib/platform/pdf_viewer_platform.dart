import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'dart:async';
import 'package:pdfx/pdfx.dart';
import '../services/auth_service.dart';
import 'dart:io';
import 'package:http/io_client.dart';
import 'dart:convert';
import 'package:open_file/open_file.dart';
import '../services/pdf_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cross_file/cross_file.dart';
import '../services/connectivity_service.dart';

class PdfViewerPlatform extends StatefulWidget {
  final String pdfUrl;
  final String title;
  final bool showAppBar;
  final bool isLocalFile;

  const PdfViewerPlatform({
    Key? key,
    required this.pdfUrl,
    required this.title,
    this.showAppBar = true,
    this.isLocalFile = false,
  }) : super(key: key);

  @override
  _PdfViewerPlatformState createState() => _PdfViewerPlatformState();
}

class _PdfViewerPlatformState extends State<PdfViewerPlatform> {
  // 根据平台选择不同的控制器类型
  PdfControllerPinch? _pdfControllerPinch;
  PdfController? _pdfController;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isOnline = true;
  String? _localFilePath;
  late StreamSubscription<bool> _connectivitySubscription;
  late ConnectivityService _connectivityService;
  
  // 防止重复加载的标志
  bool _isPdfLoading = false;
  Completer<void>? _loadPdfCompleter;
  
  // 下载进度相关
  double _downloadProgress = 0.0;
  
  // 判断是否为Windows平台
  bool get _isWindows => defaultTargetPlatform == TargetPlatform.windows;
  bool _isDownloading = false;
  
  // Windows平台的缩放和滚动控制
  double _zoomLevel = 1.0;
  final double _minZoom = 0.5;
  final double _maxZoom = 3.0;
  final double _zoomStep = 0.1;
  
  // 中键双击检测
  DateTime? _lastMiddleClickTime;
  final Duration _doubleClickThreshold = const Duration(milliseconds: 500);
  
  // 页数显示相关
  int _currentPage = 1;
  int _totalPages = 0;

  @override
  void initState() {
    super.initState();
    _connectivityService = ConnectivityService();
    _setupConnectivity();
    _loadPdf();
  }

  void _setupConnectivity() {
    _connectivitySubscription = _connectivityService.onConnectivityChanged.listen((isOnline) {
      if (mounted) {
        setState(() {
          _isOnline = isOnline;
        });
        // 只有在从离线变为在线时才重新加载
        if (isOnline && _pdfController == null && !_isPdfLoading) {
          _loadPdf();
        }
      }
    });
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    _connectivityService.dispose();
    _pdfControllerPinch?.dispose();
    _pdfController?.dispose();
    super.dispose();
  }

  Future<void> _loadPdf() async {
    // 如果已经有加载操作在进行，等待其完成
    if (_loadPdfCompleter != null && !_loadPdfCompleter!.isCompleted) {
      print('flutter: PDF正在加载中，等待完成');
      return _loadPdfCompleter!.future;
    }
    
    if (_isPdfLoading) {
      print('flutter: PDF加载标志已设置，跳过重复调用');
      return;
    }

    _isPdfLoading = true;
    _loadPdfCompleter = Completer<void>();
    
    print('flutter: 开始加载PDF: ${widget.pdfUrl}');

    try {
      if (mounted) {
        setState(() {
          _isLoading = true;
          _errorMessage = null;
        });
      }

      String filePath;
      
      if (widget.isLocalFile) {
        filePath = widget.pdfUrl;
        print('flutter: 使用本地文件: $filePath');
      } else {
        if (!_connectivityService.isOnline) {
          throw Exception('网络连接不可用');
        }
        
        setState(() {
          _isDownloading = true;
          _downloadProgress = 0.0;
        });
        
        final pdfService = PdfService();
        filePath = await pdfService.downloadAndSavePdf(
          widget.pdfUrl,
          onProgress: (current, total) {
            if (mounted && total > 0) {
              setState(() {
                _downloadProgress = current / total;
              });
            }
          },
        );
        
        setState(() {
          _isDownloading = false;
        });
        
        _localFilePath = filePath;
        print('flutter: PDF下载完成: $filePath');
      }

      // 检查文件是否存在
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('PDF文件不存在: $filePath');
      }

      // 检查是否已经有控制器并释放
      if (_pdfControllerPinch != null) {
        print('flutter: PDF控制器(Pinch)已存在，先释放');
        _pdfControllerPinch!.dispose();
        _pdfControllerPinch = null;
      }
      if (_pdfController != null) {
        print('flutter: PDF控制器已存在，先释放');
        _pdfController!.dispose();
        _pdfController = null;
      }

      print('flutter: 创建PDF控制器');
      final document = PdfDocument.openFile(filePath);
      
      if (mounted) {
        // 获取总页数
        final doc = await document;
        final totalPages = doc.pagesCount;
        
        if (_isWindows) {
          // Windows平台使用PdfController
          final controller = PdfController(
            document: document,
          );
          setState(() {
            _pdfController = controller;
            _isLoading = false;
            _errorMessage = null;
            _totalPages = totalPages;
            _currentPage = 1;
          });
          print('flutter: PDF控制器(Windows)创建成功，总页数: $totalPages');
        } else {
          // 移动端使用PdfControllerPinch
          final controller = PdfControllerPinch(
            document: document,
          );
          setState(() {
            _pdfControllerPinch = controller;
            _isLoading = false;
            _errorMessage = null;
            _totalPages = totalPages;
            _currentPage = 1;
          });
          print('flutter: PDF控制器(Pinch)创建成功，总页数: $totalPages');
        }
      } else {
        // 如果组件已卸载，文档会由控制器自动管理
        // PdfDocument不需要手动释放
      }
    } catch (e) {
      print('flutter: PDF加载失败: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF加载失败: ${e.toString()}')),
        );
      }
    } finally {
      _isPdfLoading = false;
      if (_loadPdfCompleter != null && !_loadPdfCompleter!.isCompleted) {
        _loadPdfCompleter!.complete();
      }
    }
  }

  Future<void> _refreshPdf() async {
    print('flutter: 刷新PDF');
    if (_pdfControllerPinch != null) {
      _pdfControllerPinch!.dispose();
      _pdfControllerPinch = null;
    }
    if (_pdfController != null) {
      _pdfController!.dispose();
      _pdfController = null;
    }
    _isPdfLoading = false;
    _loadPdfCompleter = null;
    
    // 重置状态
    setState(() {
      _downloadProgress = 0.0;
      _isDownloading = false;
      _currentPage = 1;
      _totalPages = 0;
    });
    
    await _loadPdf();
  }

  // 处理中键点击事件
  void _handleMiddleClick() {
    final now = DateTime.now();
    if (_lastMiddleClickTime != null && 
        now.difference(_lastMiddleClickTime!) < _doubleClickThreshold) {
      // 双击中键，重置缩放
      setState(() {
        _zoomLevel = 1.0;
      });
      print('flutter: 中键双击，重置缩放级别');
      _lastMiddleClickTime = null;
    } else {
      // 单击中键，记录时间
      _lastMiddleClickTime = now;
    }
  }

  Widget _buildPdfView() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isDownloading) ...[
              CircularProgressIndicator(value: _downloadProgress),
              const SizedBox(height: 16),
              Text('下载中... ${(_downloadProgress * 100).toStringAsFixed(1)}%'),
            ] else ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('正在加载PDF...'),
            ],
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              '加载失败',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _refreshPdf,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    // 检查控制器是否初始化
    if (_isWindows && _pdfController == null) {
      return const Center(
        child: Text('PDF控制器未初始化'),
      );
    }
    if (!_isWindows && _pdfControllerPinch == null) {
      return const Center(
        child: Text('PDF控制器未初始化'),
      );
    }

    return Stack(
      children: [
        GestureDetector(
          onLongPress: () {
            _showSaveShareDialog();
          },
          child: _isWindows
              ? Listener(
                  onPointerSignal: (pointerSignal) {
                    if (pointerSignal is PointerScrollEvent) {
                      final delta = pointerSignal.scrollDelta.dy;
                      
                      // 检查是否按住Ctrl键进行缩放
                      if (RawKeyboard.instance.keysPressed.contains(LogicalKeyboardKey.controlLeft) ||
                          RawKeyboard.instance.keysPressed.contains(LogicalKeyboardKey.controlRight)) {
                        // 缩放功能
                        setState(() {
                          if (delta > 0) {
                            _zoomLevel = (_zoomLevel - _zoomStep).clamp(_minZoom, _maxZoom);
                          } else {
                            _zoomLevel = (_zoomLevel + _zoomStep).clamp(_minZoom, _maxZoom);
                          }
                        });
                        print('flutter: 缩放级别: $_zoomLevel');
                      } else {
                        // 滚动功能 - 翻页
                        if (delta > 0 && _currentPage < _totalPages) {
                          _pdfController?.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        } else if (delta < 0 && _currentPage > 1) {
                          _pdfController?.previousPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        }
                      }
                    }
                  },
                  onPointerDown: (event) {
                    if (event.buttons == kMiddleMouseButton) {
                      _handleMiddleClick();
                    }
                  },
                  child: Transform.scale(
                    scale: _zoomLevel,
                    child: PdfView(
                      controller: _pdfController!,
                      onDocumentLoaded: (document) {
                        print('flutter: PDF文档加载完成，总页数: ${document.pagesCount}');
                      },
                      onPageChanged: (page) {
                        if (mounted) {
                          setState(() {
                            _currentPage = page;
                          });
                        }
                        print('flutter: 当前页面: $page');
                      },
                    ),
                  ),
                )
              : PdfViewPinch(
                  controller: _pdfControllerPinch!,
                  onDocumentLoaded: (document) {
                    print('flutter: PDF文档加载完成，总页数: ${document.pagesCount}');
                  },
                  onPageChanged: (page) {
                    if (mounted) {
                      setState(() {
                        _currentPage = page;
                      });
                    }
                    print('flutter: 当前页面: $page');
                  },
                ),
        ),
        if (_totalPages > 0)
          Positioned(
            bottom: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$_currentPage / $_totalPages',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        // Windows平台显示缩放级别
        if (_isWindows && _zoomLevel != 1.0)
          Positioned(
            bottom: 20,
            left: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${(_zoomLevel * 100).toInt()}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        // Windows平台操作提示
        if (_isWindows)
          Positioned(
            top: 20,
            left: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.7),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Text(
                'Ctrl+滚轮缩放 | 滚轮翻页 | 双击滚轮重置缩放',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget pdfView = _buildPdfView();

    if (!widget.showAppBar) {
      return Scaffold(
        body: pdfView,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (!_isOnline)
            const Padding(
              padding: EdgeInsets.only(right: 8.0),
              child: Icon(Icons.wifi_off, color: Colors.red),
            ),
          if ((_pdfController != null || _pdfControllerPinch != null) && _localFilePath != null) ...
            _buildAppBarActions(),
        ],
      ),
      body: pdfView,
    );
  }

  List<Widget> _buildAppBarActions() {
    return [
      IconButton(
        icon: const Icon(Icons.refresh),
        onPressed: _refreshPdf,
        tooltip: '刷新',
      ),
      if (!kIsWeb && _localFilePath != null) ...
        [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _sharePdf,
            tooltip: '分享',
          ),
          IconButton(
            icon: const Icon(Icons.open_in_new),
            onPressed: _openInExternalApp,
            tooltip: '用其他应用打开',
          ),
        ],
    ];
  }

  Future<void> _sharePdf() async {
    if (_localFilePath == null) return;
    
    try {
      final xFile = XFile(_localFilePath!);
      await Share.shareXFiles([xFile], text: widget.title);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分享失败: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _openInExternalApp() async {
    if (_localFilePath == null) return;
    
    try {
      final result = await OpenFile.open(_localFilePath!);
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开失败: ${result.message}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开失败: ${e.toString()}')),
        );
      }
    }
  }

  void _showSaveShareDialog() {
    if (_localFilePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF文件不可用')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '选择操作',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.save_alt),
                title: const Text('保存到本地'),
                onTap: () {
                  Navigator.pop(context);
                  _savePdfToGallery();
                },
              ),
              ListTile(
                leading: const Icon(Icons.share),
                title: const Text('分享PDF'),
                onTap: () {
                  Navigator.pop(context);
                  _sharePdf();
                },
              ),
              ListTile(
                leading: const Icon(Icons.open_in_new),
                title: const Text('用其他应用打开'),
                onTap: () {
                  Navigator.pop(context);
                  _openInExternalApp();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _savePdfToGallery() async {
    if (_localFilePath == null) return;
    
    try {
      // 请求存储权限
      var status = await Permission.storage.status;
      if (!status.isGranted) {
        status = await Permission.storage.request();
        if (!status.isGranted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('需要存储权限才能保存文件')),
            );
          }
          return;
        }
      }

      // 获取下载目录并创建EaipChinaViewer文件夹
      Directory baseDir;
      if (Platform.isAndroid) {
        // 尝试外部存储目录，如果失败则使用应用目录
        try {
          final externalDir = await getExternalStorageDirectory();
          if (externalDir != null) {
            baseDir = Directory('${externalDir.path}/Download');
          } else {
            baseDir = await getApplicationDocumentsDirectory();
          }
        } catch (e) {
          baseDir = await getApplicationDocumentsDirectory();
        }
      } else if (Platform.isIOS) {
        baseDir = await getApplicationDocumentsDirectory();
      } else {
        final downloadsDir = await getDownloadsDirectory();
        baseDir = downloadsDir ?? await getApplicationDocumentsDirectory();
      }

      // 创建EaipChinaViewer文件夹
      final saveDir = Directory('${baseDir.path}/EaipChinaViewer');
      if (!await saveDir.exists()) {
        await saveDir.create(recursive: true);
      }

      // 创建安全的文件名
      final safeTitle = widget.title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
      final fileName = '${safeTitle}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final targetPath = '${saveDir.path}/$fileName';

      // 复制文件
      final sourceFile = File(_localFilePath!);
      await sourceFile.copy(targetPath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF已保存到: $targetPath'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('保存PDF失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: ${e.toString()}')),
        );
      }
    }
  }
}