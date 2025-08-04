import 'package:flutter/material.dart';
import '../platform/pdf_viewer_platform.dart';

class PdfViewerScreen extends StatelessWidget {
  final String url;
  final String title;

  const PdfViewerScreen({
    super.key,
    required this.url,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return PdfViewerPlatform(
      key: ValueKey(url), // 添加 key 以强制重建
      pdfUrl: url,
      title: title,
      showAppBar: false, 
    );
  }
}
