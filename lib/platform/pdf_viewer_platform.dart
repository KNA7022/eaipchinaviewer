import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cached_pdfview/flutter_cached_pdfview.dart';
import '../services/auth_service.dart';
import 'dart:io';
import 'package:http/io_client.dart';
import 'dart:convert';
import 'package:open_file/open_file.dart';
import '../services/pdf_service.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cross_file/cross_file.dart';  // 添加这行导入
import '../services/connectivity_service.dart';

abstract class PdfViewerPlatform extends StatefulWidget {
  final String url;
  final String title;
  final bool showAppBar;  // 添加这个字段

  const PdfViewerPlatform({
    super.key,
    required this.url,
    required this.title,
    this.showAppBar = true,  // 默认显示AppBar
  });

  factory PdfViewerPlatform.create({
    Key? key,  // 添加 key 参数
    required String url,
    required String title,
    bool showAppBar = true,  // 添加这个参数
  }) {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return WindowsPdfViewer(key: key, url: url, title: title, showAppBar: showAppBar);
    } else {
      return MobilePdfViewer(key: key, url: url, title: title, showAppBar: showAppBar);
    }
  }
}

// Windows平台实现
class WindowsPdfViewer extends PdfViewerPlatform {
  const WindowsPdfViewer({
    super.key,
    required super.url,
    required super.title,
    required bool showAppBar,
  }) : super(showAppBar: showAppBar);

  @override
  State<WindowsPdfViewer> createState() => _WindowsPdfViewerState();
}

// 移动平台实现
class MobilePdfViewer extends PdfViewerPlatform {
  const MobilePdfViewer({
    super.key,
    required super.url,
    required super.title,
    required bool showAppBar,
  }) : super(showAppBar: showAppBar);

  @override
  State<MobilePdfViewer> createState() => _MobilePdfViewerState();
}

// Windows平台状态实现
class _WindowsPdfViewerState extends State<WindowsPdfViewer> {
  // ... 这里保留原来的 Windows Webview 实现 ...
  @override
  Widget build(BuildContext context) {
    return Container(); // 临时占位
  }
}

// 移动平台状态实现
class _MobilePdfViewerState extends State<MobilePdfViewer> {
  final PdfService _pdfService = PdfService();
  final ConnectivityService _connectivityService = ConnectivityService();
  bool _isLoading = true;
  bool _isOffline = false;
  String? _localPath;
  int? _totalPages = 0;
  int? _currentPage = 0;
  
  @override
  void initState() {
    super.initState();
    _setupConnectivity();
    _loadPdf();
  }

  void _setupConnectivity() {
    _connectivityService.onConnectivityChanged.listen((isOnline) {
      setState(() => _isOffline = !isOnline);
      if (isOnline && _localPath == null) {
        _loadPdf();
      }
    });
  }

  Future<void> _loadPdf() async {
    if (!_connectivityService.isOnline) {
      setState(() => _isOffline = true);
      return;
    }

    setState(() {
      _isLoading = true;
      _isOffline = false;
    });

    try {
      final filePath = await _pdfService.downloadAndSavePdf(
        widget.url,
        onProgress: (current, total) {
          print('下载进度: ${(current / total * 100).toStringAsFixed(1)}%');
        },
      );
      if (mounted) {
        setState(() {
          _localPath = filePath;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('PDF加载失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF加载失败: $e')),
        );
      }
    }
  }

  Future<void> _handleLongPress() async {
    if (_localPath == null) return;

    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.save_alt),
                title: const Text('保存文件'),
                onTap: () async {
                  Navigator.pop(context);
                  await _savePdfToDownloads();
                },
              ),
              ListTile(
                leading: const Icon(Icons.share),
                title: const Text('分享文件'),
                onTap: () async {
                  Navigator.pop(context);
                  await _sharePdf();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _savePdfToDownloads() async {
    try {
      // 请求存储权限
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('需要存储权限来保存文件')),
          );
        }
        return;
      }

      // 创建目标目录
      final downloadsDir = Directory('/storage/emulated/0/Download/EaipChinaViewer');
      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }

      // 生成目标文件路径
      final fileName = '${widget.title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')}.pdf';
      final targetPath = '${downloadsDir.path}/$fileName';

      // 复制文件
      final File sourceFile = File(_localPath!);
      await sourceFile.copy(targetPath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('文件已保存到: $targetPath')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存文件失败: $e')),
        );
      }
    }
  }

  Future<void> _sharePdf() async {
    try {
      if (_localPath != null) {
        final result = await Share.shareXFiles(
          [XFile(_localPath!)],
          text: widget.title,
        );

        if (result.status == ShareResultStatus.dismissed) {
          print('用户取消了分享');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分享失败: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _connectivityService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget pdfView = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _isOffline
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.cloud_off,
                      size: 48,
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 16),
                    const Text('无网络连接'),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: _loadPdf,
                      child: const Text('重试'),
                    ),
                  ],
                ),
              )
            : _localPath == null
                ? Center(
                    child: ElevatedButton(
                      onPressed: _loadPdf,
                      child: const Text('重试'),
                    ),
                  )
                : GestureDetector(
                    onLongPress: _handleLongPress,
                    child: Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        PDFView(
                          filePath: _localPath!,
                          enableSwipe: true,
                          swipeHorizontal: true,
                          autoSpacing: true,
                          pageFling: true,
                          pageSnap: true,
                          defaultPage: 0,
                          fitPolicy: FitPolicy.BOTH,
                          preventLinkNavigation: false,
                          onRender: (pages) {
                            setState(() => _totalPages = pages);
                          },
                          onError: (error) {
                            print('PDF渲染错误: $error');
                          },
                          onPageError: (page, error) {
                            print('第$page页加载错误: $error');
                          },
                          onPageChanged: (page, total) {
                            setState(() => _currentPage = page);
                          },
                        ),
                        if (!_isLoading && _localPath != null)
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                            margin: const EdgeInsets.only(bottom: 20),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${(_currentPage ?? 0) + 1}/${_totalPages ?? 0}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );

    if (!widget.showAppBar) {
      return pdfView;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (!_isLoading && _localPath != null) ...[
            Center(
              child: Text(
                '${(_currentPage ?? 0) + 1}/${_totalPages ?? 0}',  // 修改这里，页数加1
                style: const TextStyle(fontSize: 16),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadPdf,
            ),
            IconButton(
              icon: const Icon(Icons.open_in_new),
              onPressed: () async {
                if (_localPath != null) {
                  await OpenFile.open(_localPath!);
                }
              },
            ),
          ],
        ],
      ),
      body: pdfView,
    );
  }
}