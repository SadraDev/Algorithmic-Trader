class AccountStatusModel {
  final bool isOnline;
  final int login;
  final String server;
  final String currency;
  final double balance;
  final double equity;
  final double margin;
  final double freeMargin;
  final int activeInstancesCount;

  const AccountStatusModel({
    required this.isOnline,
    this.login = 0,
    this.server = 'MetaQuotes-Demo',
    this.currency = 'USD',
    this.balance = 0.0,
    this.equity = 0.0,
    this.margin = 0.0,
    this.freeMargin = 0.0,
    this.activeInstancesCount = 0,
  });

  factory AccountStatusModel.fromJson(Map<String, dynamic> json) {
    final account = (json['account'] as Map<String, dynamic>?) ?? {};
    return AccountStatusModel(
      isOnline: json['status'] == 'online',
      login: (account['login'] as num?)?.toInt() ?? 0,
      server: account['server'] ?? 'MetaQuotes-Demo',
      currency: account['currency'] ?? 'USD',
      balance: (account['balance'] as num?)?.toDouble() ?? 0.0,
      equity: (account['equity'] as num?)?.toDouble() ?? 0.0,
      margin: (account['margin'] as num?)?.toDouble() ?? 0.0,
      freeMargin: (account['margin_free'] as num?)?.toDouble() ?? 0.0,
      activeInstancesCount: (json['active_instances_count'] as num?)?.toInt() ?? 0,
    );
  }
}
