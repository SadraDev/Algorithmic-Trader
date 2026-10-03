import 'dart:async';
import 'package:flutter/material.dart';

import 'constants/app_colors.dart';
import 'services/api_service.dart';
import 'screens/dashboard_screen.dart';
import 'screens/algorithms_screen.dart';
import 'screens/history_screen.dart';
import 'screens/settings_screen.dart';

export 'constants/app_colors.dart';
export 'constants/app_styles.dart';
export 'widgets/sparkline_chart.dart';

void main() {
  runApp(const AlgorithmicTraderApp());
}

// =============================================================================
// MAIN APPLICATION ENTRY & THEME
// =============================================================================
class AlgorithmicTraderApp extends StatelessWidget {
  const AlgorithmicTraderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Algorithmic Trader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.green,
          surface: AppColors.surface,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.background,
          elevation: 0,
          centerTitle: true,
        ),
      ),
      home: const MainNavigationShell(),
    );
  }
}

// =============================================================================
// MAIN NAVIGATION SHELL
// =============================================================================
class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _currentNavIndex = 0;
  Timer? _pollingTimer;

  bool _isLoading = false;
  bool _isMt5Connected = false;
  double _accountBalance = 0.0;
  double _accountEquity = 0.0;
  double _accountProfit = 0.0;
  double _accountFreeMargin = 0.0;
  int _accountLeverage = 1;
  String _serverName = 'N/A';
  int _loginAccount = 0;
  String _currency = 'USD';

  List<Map<String, dynamic>> _strategyConfigs = [];
  List<Map<String, dynamic>> _activeInstances = [];
  List<Map<String, dynamic>> _historyDeals = [];

  @override
  void initState() {
    super.initState();
    _fetchBackendData();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (mounted && _currentNavIndex == 0) {
        _fetchBackendData(showLoading: false);
      }
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchBackendData({bool showLoading = true}) async {
    if (showLoading) setState(() => _isLoading = true);

    try {
      final status = await ApiService.getAccountStatus();
      final configs = await ApiService.getStrategyConfigs();
      final instances = await ApiService.getActiveInstances();
      final history = await ApiService.getHistory();

      if (mounted) {
        setState(() {
          _isMt5Connected = status['status'] == 'online';
          final acc = status['account'];
          if (acc != null) {
            _accountBalance = (acc['balance'] as num?)?.toDouble() ?? 0.0;
            _accountEquity = (acc['equity'] as num?)?.toDouble() ?? 0.0;
            _accountProfit = (acc['profit'] as num?)?.toDouble() ?? 0.0;
            _accountFreeMargin = (acc['margin_free'] as num?)?.toDouble() ?? 0.0;
            _accountLeverage = (acc['leverage'] as num?)?.toInt() ?? 1;
            _serverName = acc['server']?.toString() ?? 'MT5 Terminal';
            _loginAccount = (acc['login'] as num?)?.toInt() ?? 0;
            _currency = acc['currency']?.toString() ?? 'USD';
          }
          _strategyConfigs = configs;
          _activeInstances = instances;
          _historyDeals = history;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted && showLoading) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _stopInstance(String instanceId) async {
    await ApiService.stopInstance(instanceId);
    _fetchBackendData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: IndexedStack(
        index: _currentNavIndex,
        children: [
          DashboardScreen(
            isMt5Connected: _isMt5Connected,
            loginAccount: _loginAccount,
            serverName: _serverName,
            accountBalance: _accountBalance,
            accountEquity: _accountEquity,
            accountProfit: _accountProfit,
            accountFreeMargin: _accountFreeMargin,
            accountLeverage: _accountLeverage,
            currency: _currency,
            activeInstances: _activeInstances,
            historyDeals: _historyDeals,
            onRefresh: _fetchBackendData,
            onPauseInstance: (id) => _stopInstance(id),
            onStopInstance: (id) => _stopInstance(id),
          ),
          AlgorithmsView(
            strategyConfigs: _strategyConfigs,
            onRefreshConfigs: _fetchBackendData,
            onStartInstance: () {
              setState(() => _currentNavIndex = 0);
              _fetchBackendData();
            },
          ),
          HistoryView(
            historyDeals: _historyDeals,
            onRefreshLogs: _fetchBackendData,
          ),
          SettingsView(
            serverName: _serverName,
            loginAccount: _loginAccount,
            balance: _accountBalance,
            currency: _currency,
            isConnected: _isMt5Connected,
            onRefresh: _fetchBackendData,
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    const titles = ['DASHBOARD', 'ALGORITHMS', 'TRADE HISTORY', 'SETTINGS'];

    return AppBar(
      leadingWidth: 56,
      leading: const Padding(
        padding: EdgeInsets.only(left: 16.0),
        child: CircleAvatar(
          backgroundColor: AppColors.surfaceLight,
          child: Icon(
            Icons.person,
            color: AppColors.white,
            size: 20,
          ),
        ),
      ),
      title: Text(
        titles[_currentNavIndex],
        style: const TextStyle(
          color: AppColors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
      actions: [
        IconButton(
          icon: Icon(
            Icons.refresh,
            color: _isLoading ? AppColors.amber : AppColors.white,
          ),
          onPressed: _fetchBackendData,
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildBottomNavigationBar() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.border, width: 1.0),
        ),
      ),
      child: BottomNavigationBar(
        currentIndex: _currentNavIndex,
        onTap: (index) {
          setState(() {
            _currentNavIndex = index;
          });
        },
        backgroundColor: AppColors.surface,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.green,
        unselectedItemColor: AppColors.mutedText,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        elevation: 0,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.memory_outlined),
            activeIcon: Icon(Icons.memory),
            label: 'Algorithms',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history_outlined),
            activeIcon: Icon(Icons.history),
            label: 'History',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
