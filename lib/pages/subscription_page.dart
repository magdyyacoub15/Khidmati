import 'package:flutter/material.dart';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:appwrite/appwrite.dart';
import '../services/appwrite_service.dart';
import '../services/subscription_service.dart';
import 'dart:async';
import 'package:appwrite/models.dart' as models;
import '../services/data_cache_service.dart'; // 🚀 Added Cache Service
import '../l10n/app_translations.dart';

class SubscriptionPage extends StatefulWidget {
  final String groupId;
  const SubscriptionPage({super.key, required this.groupId});

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage>
    with SingleTickerProviderStateMixin {
  final SubscriptionService _subscriptionService = SubscriptionService();
  final Databases _databases = AppwriteService().databases;
  static const String databaseId = AppwriteService.databaseId;
  static const String groupsCollectionId = 'groups';

  AnimationController? _animationController;

  SubscriptionStatus _status = SubscriptionStatus.trial;
  int _daysRemaining = 0;
  bool _isLoading = true;
  String _groupEmail = '';

  final String _vodafoneNumber = "01061438566";
  final String _instapayNumber = "01112800404";
  final String _whatsappNumber = "+201112800404";

  // Dynamic Prices
  String _price1m = "75 ج.م";
  String _price3m = "199 ج.م";
  String _price6m = "349 ج.م";
  String _price1y = "599 ج.م";

  final Realtime _realtime = AppwriteService().realtime;
  StreamSubscription? _priceSubscription;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    )..repeat();
    _loadStatus();
    _loadPrices();
    _subscribeToPriceChanges();
  }

  @override
  void dispose() {
    _animationController?.dispose();
    _priceSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    // 1. Try Loading from Cache
    final cached = await DataCacheService().getCachedSubscriptionStatus(
      widget.groupId,
    );
    if (cached != null) {
      if (mounted) {
        setState(() {
          _status = SubscriptionStatus
              .values[cached['statusIndex'] ?? 2]; // Default trial
          _daysRemaining = cached['days'] ?? 0;
          _groupEmail = cached['email'] ?? '';
          _isLoading = false;
        });
      }
    }

    // 2. Fetch Fresh Data (Background)
    try {
      final status = await _subscriptionService.checkSubscriptionStatus(
        widget.groupId,
      );
      final days = await _subscriptionService.getDaysRemaining(widget.groupId);

      // Fetch group email
      String email = '';
      try {
        final doc = await _databases.getDocument(
          databaseId: databaseId,
          collectionId: groupsCollectionId,
          documentId: widget.groupId,
        );
        email = doc.data['adminEmail'] ?? '';
      } catch (e) {
        debugPrint("Error fetching group email: $e");
      }

      // 3. Update Cache & UI
      final statusData = {
        'statusIndex': status.index,
        'days': days,
        'email': email,
      };
      await DataCacheService().cacheSubscriptionStatus(
        widget.groupId,
        statusData,
      );

      if (mounted) {
        setState(() {
          _status = status;
          _daysRemaining = days;
          _groupEmail = email;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading subscription status: $e");
      // If we failed and have no cache, stop loading
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadPrices() async {
    // 1. Load from Cache
    final cached = await DataCacheService().getCachedSubscriptionPrices();
    if (cached != null) {
      if (mounted) {
        setState(() {
          _price1m = cached['price_1m'] ?? _price1m;
          _price3m = cached['price_3m'] ?? _price3m;
          _price6m = cached['price_6m'] ?? _price6m;
          _price1y = cached['price_1y'] ?? _price1y;
        });
      }
    }

    // 2. Fetch Fresh Data
    try {
      final doc = await _databases.getDocument(
        databaseId: databaseId,
        collectionId: AppwriteService.appConfigCollectionId,
        documentId: AppwriteService.subscriptionPricesDocId,
      );

      final data = doc.data;
      await DataCacheService().cacheSubscriptionPrices(data);

      if (mounted) {
        setState(() {
          _price1m = data['price_1m'] ?? _price1m;
          _price3m = data['price_3m'] ?? _price3m;
          _price6m = data['price_6m'] ?? _price6m;
          _price1y = data['price_1y'] ?? _price1y;
        });
      }
    } catch (e) {
      debugPrint("Error loading prices: $e");
    }
  }

  void _subscribeToPriceChanges() {
    final channel =
        'databases.$databaseId.collections.${AppwriteService.appConfigCollectionId}.documents.${AppwriteService.subscriptionPricesDocId}';
    _priceSubscription = _realtime.subscribe([channel]).stream.listen((event) {
      if (event.events.any((e) => e.contains('.documents.'))) {
        final data = event.payload;
        // Update Cache
        DataCacheService().cacheSubscriptionPrices(data);

        if (mounted) {
          setState(() {
            _price1m = data['price_1m'] ?? _price1m;
            _price3m = data['price_3m'] ?? _price3m;
            _price6m = data['price_6m'] ?? _price6m;
            _price1y = data['price_1y'] ?? _price1y;
          });
        }
      }
    });
  }

  void _showPriceEditDialog() {
    final TextEditingController p1m = TextEditingController(text: _price1m);
    final TextEditingController p3m = TextEditingController(text: _price3m);
    final TextEditingController p6m = TextEditingController(text: _price6m);
    final TextEditingController p1y = TextEditingController(text: _price1y);
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            'edit_subscription_prices'.tr(context),
            textAlign: TextAlign.right,
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildPriceField(p1m, 'price_1_month'.tr(context)),
                _buildPriceField(p3m, 'price_3_months'.tr(context)),
                _buildPriceField(p6m, 'price_6_months'.tr(context)),
                _buildPriceField(p1y, 'price_1_year'.tr(context)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('cancel_btn'.tr(context)),
            ),
            if (isSaving)
              const CircularProgressIndicator()
            else
              ElevatedButton(
                onPressed: () async {
                  setDialogState(() => isSaving = true);
                  final data = {
                    'price_1m': p1m.text,
                    'price_3m': p3m.text,
                    'price_6m': p6m.text,
                    'price_1y': p1y.text,
                  };

                  try {
                    try {
                      await _databases.updateDocument(
                        databaseId: databaseId,
                        collectionId: AppwriteService.appConfigCollectionId,
                        documentId: AppwriteService.subscriptionPricesDocId,
                        data: data,
                      );
                    } catch (e) {
                      // If document doesn't exist, create it
                      await _databases.createDocument(
                        databaseId: databaseId,
                        collectionId: AppwriteService.appConfigCollectionId,
                        documentId: AppwriteService.subscriptionPricesDocId,
                        data: data,
                      );
                    }
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('prices_updated_success'.tr(context)),
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      setDialogState(() => isSaving = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'error_updating_prices'
                                .tr(context)
                                .replaceFirst('%s', e.toString()),
                          ),
                        ),
                      );
                    }
                  }
                },
                child: Text('save_changes_btn'.tr(context)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceField(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        textAlign: TextAlign.right,
        decoration: InputDecoration(
          labelText: label,
          hintText: 'price_hint'.tr(context),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  Future<void> _launchWhatsApp() async {
    final String msg = 'whatsapp_subscription_msg'
        .tr(context)
        .replaceFirst('%s', _groupEmail);
    final Uri url = Uri.parse(
      "https://wa.me/$_whatsappNumber?text=${Uri.encodeComponent(msg)}",
    );
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('cannot_open_whatsapp'.tr(context))),
        );
      }
    }
  }

  Future<void> _copyNumber(String number) async {
    await Clipboard.setData(ClipboardData(text: number));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('number_copied'.tr(context))));
    }
  }

  Widget _buildPremiumBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0D47A1), Color(0xFF1976D2), Color(0xFF42A5F5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          if (_animationController != null)
            AnimatedBuilder(
              animation: _animationController!,
              builder: (context, child) {
                return Stack(
                  children: [
                    _buildAnimatedBlob(
                      top: -50,
                      left: -50,
                      offset: Offset(
                        sin(_animationController!.value * 2 * pi) * 60,
                        cos(_animationController!.value * 2 * pi) * 40,
                      ),
                      color: Colors.white.withValues(alpha: 0.1),
                      size: 300,
                    ),
                    _buildAnimatedBlob(
                      top: 300,
                      left: 150,
                      offset: Offset(
                        cos(_animationController!.value * 2 * pi) * 70,
                        sin(_animationController!.value * 2 * pi) * 50,
                      ),
                      color: Colors.white.withValues(alpha: 0.07),
                      size: 250,
                    ),
                    _buildAnimatedBlob(
                      top: 600,
                      left: -30,
                      offset: Offset(
                        sin(_animationController!.value * 2 * pi) * 40,
                        -cos(_animationController!.value * 2 * pi) * 60,
                      ),
                      color: Colors.white.withValues(alpha: 0.05),
                      size: 200,
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildAnimatedBlob({
    double? top,
    double? left,
    required Offset offset,
    required Color color,
    required double size,
  }) {
    return Positioned(
      top: top,
      left: left,
      child: Transform.translate(
        offset: offset,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text('subscriptions_title'.tr(context)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        actions: [
          FutureBuilder<models.User>(
            future: AppwriteService().account.get(),
            builder: (context, snapshot) {
              if (snapshot.hasData &&
                  snapshot.data!.email == 'magdyyacoub41@gmail.com') {
                return IconButton(
                  icon: const Icon(Icons.edit_calendar_rounded),
                  onPressed: _showPriceEditDialog,
                  tooltip: 'edit_prices_tooltip'.tr(context),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          _buildPremiumBackground(),
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SafeArea(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      await _loadStatus();
                      await _loadPrices();
                    },
                    child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        _buildStatusCard(),
                        const SizedBox(height: 20),
                        Text(
                          'subscription_plans'.tr(context),
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _buildPlanCard(
                          'one_month_duration'.tr(context),
                          _price1m,
                        ),
                        _buildPlanCard(
                          'three_months_duration'.tr(context),
                          _price3m,
                        ),
                        _buildPlanCard(
                          'six_months_duration'.tr(context),
                          _price6m,
                        ),
                        _buildPlanCard(
                          'one_year_duration'.tr(context),
                          _price1y,
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.info_outline,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'subscription_note'.tr(context),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 30),
                        Text(
                          'payment_methods'.tr(context),
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _buildPaymentMethod("Vodafone Cash", _vodafoneNumber),
                        _buildPaymentMethod("Instapay", _instapayNumber),
                        const SizedBox(height: 30),
                        ElevatedButton.icon(
                          onPressed: _launchWhatsApp,
                          icon: const Icon(Icons.chat),
                          label: Text('send_transfer_whatsapp'.tr(context)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.all(16),
                            minimumSize: const Size(double.infinity, 50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    IconData icon;
    Color statusColor;

    switch (_status) {
      case SubscriptionStatus.offline:
        statusColor = Colors.grey;
        icon = Icons.wifi_off;
        break;
      case SubscriptionStatus.active:
        statusColor = Colors.greenAccent;
        icon = Icons.check_circle;
        break;
      case SubscriptionStatus.trial:
        statusColor = Colors.lightBlueAccent;
        icon = Icons.access_time;
        break;
      case SubscriptionStatus.expired:
        statusColor = Colors.redAccent;
        icon = Icons.cancel;
        break;
    }

    return Card(
      color: Colors.white.withValues(alpha: 0.1),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(icon, color: statusColor, size: 40),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'subscription_status'.tr(context),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'remaining_days'
                        .tr(context)
                        .replaceFirst('%s', '$_daysRemaining'),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Colors.white70,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanCard(String duration, String price) {
    return Card(
      color: Colors.white.withValues(alpha: 0.1),
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: ListTile(
        title: Text(
          duration,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        trailing: Text(
          price,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.amber,
          ),
        ),
        leading: const Icon(Icons.star, color: Colors.amber),
      ),
    );
  }

  Widget _buildPaymentMethod(String name, String number) {
    return Card(
      color: Colors.white.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: ListTile(
        title: Text(name, style: const TextStyle(color: Colors.white70)),
        subtitle: Text(
          number,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.copy, color: Colors.white70),
          onPressed: () => _copyNumber(number),
        ),
      ),
    );
  }
}
