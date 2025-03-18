import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PolicyScreen extends StatefulWidget {
  final String type;
  final bool isFirstRun;

  const PolicyScreen({
    super.key,
    required this.type,
    this.isFirstRun = false,
  });

  @override
  State<PolicyScreen> createState() => _PolicyScreenState();
}

class _PolicyScreenState extends State<PolicyScreen> {
  String _privacyContent = '';
  String _termsContent = '';
  bool _isLoading = true;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadContents();
  }

  Future<void> _loadContents() async {
    try {
      final privacy = await rootBundle.loadString('assets/privacy_policy.md');
      final terms = await rootBundle.loadString('assets/terms_of_service.md');
      setState(() {
        _privacyContent = privacy;
        _termsContent = terms;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _privacyContent = '加载失败: $e';
        _termsContent = '加载失败: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _handleDecision(bool accepted) async {
    if (widget.isFirstRun) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('first_run', false);
      await prefs.setBool('policy_accepted', accepted);
    }
    
    if (mounted) {
      Navigator.of(context).pushReplacementNamed(
        '/login',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    Widget mainContent = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              if (widget.isFirstRun) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  color: theme.colorScheme.primary.withOpacity(0.1),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, 
                           color: theme.colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '请仔细阅读以下协议，了解我们如何保护您的权益',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const TabBar(
                  tabs: [
                    Tab(text: '隐私政策'),
                    Tab(text: '用户协议'),
                  ],
                ),
              ],
              Expanded(
                child: TabBarView(
                  children: [
                    Markdown(data: _privacyContent),
                    Markdown(data: _termsContent),
                  ],
                ),
              ),
              if (widget.isFirstRun)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _handleDecision(false),
                          child: const Text('不同意'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => _handleDecision(true),
                          child: const Text('同意'),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );

    return widget.isFirstRun
        ? DefaultTabController(
            length: 2,
            child: Scaffold(
              appBar: AppBar(
                title: const Text('用户协议与隐私政策'),
                centerTitle: true,
              ),
              body: mainContent,
            ),
          )
        : Scaffold(
            appBar: AppBar(
              title: Text(_currentIndex == 0 ? '隐私政策' : '用户协议'),
              centerTitle: true,
              actions: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            body: mainContent,
          );
  }
}
