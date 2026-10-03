import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_styles.dart';
import '../services/api_service.dart';

class SettingsView extends StatefulWidget {
  final String serverName;
  final int loginAccount;
  final double balance;
  final String currency;
  final bool isConnected;
  final VoidCallback onRefresh;

  const SettingsView({
    super.key,
    required this.serverName,
    required this.loginAccount,
    required this.balance,
    required this.currency,
    required this.isConnected,
    required this.onRefresh,
  });

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late TextEditingController _endpointCtrl;
  bool _isSavingUrl = false;

  @override
  void initState() {
    super.initState();
    _endpointCtrl = TextEditingController(text: ApiService.baseUrl);
  }

  @override
  void dispose() {
    _endpointCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveEndpointUrl() async {
    setState(() => _isSavingUrl = true);
    final newUrl = _endpointCtrl.text.trim();

    final success = await ApiService.saveCustomBaseUrl(newUrl);

    if (mounted) {
      setState(() => _isSavingUrl = false);
      if (success) {
        widget.onRefresh();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('API Bridge Endpoint saved: ${ApiService.baseUrl}')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid Endpoint URL')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SYSTEM & TERMINAL CONFIGURATION',
            style: TextStyle(color: AppColors.white, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.8),
          ),
          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14.0),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('METATRADER 5 TERMINAL BINDING', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: (widget.isConnected ? AppColors.green : AppColors.amber).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        widget.isConnected ? 'ACTIVE' : 'STANDBY',
                        style: TextStyle(color: widget.isConnected ? AppColors.green : AppColors.amber, fontWeight: FontWeight.bold, fontSize: 10),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(color: AppColors.border, height: 1),
                const SizedBox(height: 12),

                _buildSettingRow('Terminal Server', widget.serverName),
                _buildSettingRow('Login Account', widget.loginAccount > 0 ? widget.loginAccount.toString() : 'MT5 Terminal'),
                _buildSettingRow('Account Balance', '\$${widget.balance.toStringAsFixed(2)} ${widget.currency}'),
                const SizedBox(height: 12),

                // Editable API Endpoint TextField
                const Text('API BRIDGE ENDPOINT (EDITABLE & PERSISTED)', style: TextStyle(color: AppColors.mutedText, fontSize: 10, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: _endpointCtrl,
                  style: AppTextStyles.mono.copyWith(fontSize: 12),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.surfaceLight,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                    hintText: 'http://10.0.2.2:8000/api/trading',
                  ),
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.green,
                          foregroundColor: AppColors.background,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: _isSavingUrl ? null : _saveEndpointUrl,
                        icon: const Icon(Icons.save, size: 16),
                        label: const Text('SAVE ENDPOINT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.surfaceLight,
                          foregroundColor: AppColors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: widget.onRefresh,
                        icon: const Icon(Icons.sync, size: 16),
                        label: const Text('RE-INITIALIZE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.mutedText, fontSize: 12)),
          Flexible(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.mono.copyWith(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
