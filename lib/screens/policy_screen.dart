import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PolicyScreen extends StatefulWidget {
  final String type;
  final bool isFirstRun;
  final bool showBothPolicies;  

  const PolicyScreen({
    super.key,
    required this.type,
    this.isFirstRun = false,
    this.showBothPolicies = false,  // 默认为false
  });

  @override
  State<PolicyScreen> createState() => _PolicyScreenState();
}

class _PolicyScreenState extends State<PolicyScreen> with SingleTickerProviderStateMixin {
  String _privacyContent = '';
  String _termsContent = '';
  bool _isLoading = true;
  int _currentIndex = 0;
  bool _isAccepted = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.type == 'privacy' ? 0 : 1,
    );
    _loadContents();
    _loadAcceptanceStatus();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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

  Future<void> _loadAcceptanceStatus() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isAccepted = prefs.getBool('policy_accepted') ?? false;
    });
  }

  Future<void> _toggleAcceptance() async {
    final prefs = await SharedPreferences.getInstance();
    final newStatus = !_isAccepted;
    await prefs.setBool('policy_accepted', newStatus);
    setState(() {
      _isAccepted = newStatus;
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newStatus ? '已同意协议' : '已撤销同意'),
          duration: const Duration(seconds: 2),
        ),
      );
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
        : widget.showBothPolicies
            ? Column(
                children: [
                  TabBar(
                    controller: _tabController,
                    labelColor: theme.colorScheme.primary,
                    unselectedLabelColor: Colors.grey,
                    indicatorColor: theme.colorScheme.primary,
                    tabs: const [
                      Tab(text: '隐私政策'),
                      Tab(text: '用户协议'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildMarkdownView(_privacyContent),
                        _buildMarkdownView(_termsContent),
                      ],
                    ),
                  ),
                ],
              )
            : _buildMarkdownView(
                widget.type == 'privacy' ? _privacyContent : _termsContent,
              );

    return widget.isFirstRun || widget.showBothPolicies
        ? DefaultTabController(
            length: 2,
            child: Scaffold(
              appBar: AppBar(
                title: Text(widget.isFirstRun 
                    ? '用户协议与隐私政策'
                    : '法律条款'),
                centerTitle: true,
                actions: _buildAppBarActions(),
              ),
              body: mainContent,
            ),
          )
        : Scaffold(
            appBar: AppBar(
              title: Text(widget.type == 'privacy' ? '隐私政策' : '用户协议'),
              centerTitle: true,
              actions: _buildAppBarActions(),
            ),
            body: mainContent,
          );
  }

  Widget _buildMarkdownView(String content) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.isFirstRun) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, 
                       color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      '请仔细阅读以下协议，了解我们如何保护您的权益',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          MarkdownBody(
            data: content,
            selectable: true,
            styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
              h1: Theme.of(context).textTheme.headlineSmall,
              h2: Theme.of(context).textTheme.titleLarge,
              h3: Theme.of(context).textTheme.titleMedium,
              p: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          if (widget.isFirstRun) ...[
            const SizedBox(height: 16),
            Row(
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
          ],
        ],
      ),
    );
  }

  List<Widget> _buildAppBarActions() {
    if (widget.isFirstRun) return [];
    
    return [
      TextButton.icon(
        icon: Icon(
          _isAccepted ? Icons.check_circle : Icons.radio_button_unchecked,
          color: _isAccepted ? Colors.green : null,
        ),
        label: Text(_isAccepted ? '已同意' : '同意'),
        onPressed: _toggleAcceptance,
      ),
      IconButton(
        icon: const Icon(Icons.close),
        onPressed: () => Navigator.of(context).pop(),
      ),
    ];
  }
}
