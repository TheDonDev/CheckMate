// lib/services/iap_service.dart
import 'dart:async';
// Required for Platform check

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
// If using in_app_purchase_android for specific features:
// import 'package:in_app_purchase_android/in_app_purchase_android.dart';
// import 'package:in_app_purchase_android/billing_client_wrappers.dart';

// Define your product ID (MUST match Google Play/App Store Connect)
const String _premiumProductId = 'premium_upgrade_checkmate'; // CHANGE THIS if needed

class IapService with ChangeNotifier {
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  // Internal state
  bool _isAvailable = false;
  List<ProductDetails> _products = [];
  final Set<String> _purchasedProductIds = {}; // Store IDs of purchased non-consumables
  bool _isLoading = true;
  String? _errorMessage;

  // Public getters
  bool get isAvailable => _isAvailable;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<ProductDetails> get products => _products;

  // Key getter: Checks if the premium upgrade has been purchased
  bool get isPremiumUser => _purchasedProductIds.contains(_premiumProductId);

  IapService() {
    _initialize();
  }

  Future<void> _initialize() async {
    _isAvailable = await _iap.isAvailable();
    if (kDebugMode) print("IAP Available: $_isAvailable");

    if (_isAvailable) {
      // Listen to purchase updates
      _subscription = _iap.purchaseStream.listen(
        _onPurchaseUpdate,
        onDone: () => _subscription?.cancel(),
        onError: (error) {
          if (kDebugMode) print("IAP Stream Error: $error");
          _setError("Error listening to purchases.");
        },
      );

      // Load products and past purchases
      await _loadProducts();
      await _restorePurchases(); // Important for persistence
    } else {
      _setError("In-App Purchases are not available on this device.");
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _loadProducts() async {
    try {
      final ProductDetailsResponse response =
          await _iap.queryProductDetails({_premiumProductId});

      if (response.error != null) {
        if (kDebugMode) print("IAP Product Query Error: ${response.error}");
        _setError("Failed to load upgrade options.");
        _products = [];
      } else if (response.productDetails.isEmpty) {
        if (kDebugMode) print("IAP: Product '$_premiumProductId' not found.");
        _setError("Upgrade option not found. Check store configuration.");
        _products = [];
      } else {
        _products = response.productDetails;
        if (kDebugMode) print("IAP Products loaded: ${_products.map((p) => p.id).join(', ')}");
        _clearError(); // Clear error if products load successfully
      }
    } catch (e) {
       if (kDebugMode) print("IAP Exception during product load: $e");
       _setError("An error occurred while fetching upgrade options.");
       _products = [];
    }
    notifyListeners();
  }

  Future<void> _restorePurchases() async {
    try {
      // Querying past purchases might be needed on app start or user request
      // This automatically happens for non-consumables on stream init for Google Play
      // but explicit call might be needed for robustness / other platforms.
      await _iap.restorePurchases();
      if (kDebugMode) print("IAP: Attempted to restore purchases.");
      // The _onPurchaseUpdate listener will handle any restored purchases found.
    } catch (e) {
       if (kDebugMode) print("IAP Exception during restore purchases: $e");
       // Don't necessarily set an error here, might just mean no past purchases
    }
     // No need to notifyListeners here, _onPurchaseUpdate will do it if needed
  }

  void _onPurchaseUpdate(List<PurchaseDetails> purchaseDetailsList) {
    bool premiumStatusChanged = false;
    for (var purchase in purchaseDetailsList) {
      if (kDebugMode) print("IAP Purchase Update: ID=${purchase.productID}, Status=${purchase.status}, Error=${purchase.error}");

      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored: // Treat restored same as purchased
          if (purchase.productID == _premiumProductId) {
             // --- IMPORTANT: Verification ---
             // You SHOULD verify the purchase here (client-side minimum, server-side recommended)
             // to ensure it's legitimate before granting premium access.
             // For this example, we assume client-side verification passes if status is purchased/restored.
             if (kDebugMode) print("IAP: Purchase/Restore successful for ${purchase.productID}. Granting premium.");

             if (_purchasedProductIds.add(purchase.productID)) {
                premiumStatusChanged = true; // Status changed only if it was newly added
             }
             _completePurchase(purchase);
          } else {
             if (kDebugMode) print("IAP: Purchased unknown product: ${purchase.productID}");
             // Handle unexpected product purchases if necessary
             _completePurchase(purchase); // Still complete it
          }
          _clearError();
          break;
        case PurchaseStatus.pending:
          // Inform user purchase is pending (e.g., requires parental approval)
          if (kDebugMode) print("IAP: Purchase pending for ${purchase.productID}");
          // You might want to show a specific UI state here
          break;
        case PurchaseStatus.error:
          if (kDebugMode) print("IAP Purchase Error: ${purchase.error}");
          _setError("Purchase failed: ${purchase.error?.message ?? 'Unknown error'}");
          _completePurchase(purchase); // Still try to complete to clear the queue
          break;
        case PurchaseStatus.canceled: // Specific to App Store
           if (kDebugMode) print("IAP: Purchase cancelled for ${purchase.productID}");
           _clearError();
           _completePurchase(purchase); // Still try to complete to clear the queue
           break;
      }
    }
    if (premiumStatusChanged) {
       if (kDebugMode) print("IAP: Premium status changed. Notifying listeners.");
       notifyListeners(); // Notify if the premium status actually changed
    }
  }

  Future<void> _completePurchase(PurchaseDetails purchase) async {
    if (purchase.pendingCompletePurchase) {
      try {
        await _iap.completePurchase(purchase);
        if (kDebugMode) print("IAP: Purchase completed for ${purchase.productID}");
      } catch (e) {
         if (kDebugMode) print("IAP Error completing purchase ${purchase.productID}: $e");
         // Handle completion error if necessary
      }
    }
  }

  Future<bool> purchasePremium() async {
    if (_isLoading || !_isAvailable) {
      _setError("Cannot purchase: IAP not ready or available.");
      notifyListeners();
      return false;
    }

    final ProductDetails? productToBuy = _products.firstWhere(
      (p) => p.id == _premiumProductId,
      orElse: () => throw Exception("Product not found"), // Throw an exception if not found
    );

    if (productToBuy == null) {
      if (kDebugMode) print("IAP Error: Premium product '$_premiumProductId' not found in loaded products.");
      _setError("Upgrade option is currently unavailable. Please try again later.");
      notifyListeners();
      await _loadProducts(); // Try reloading products
      return false;
    }

    final PurchaseParam purchaseParam = PurchaseParam(productDetails: productToBuy);

    try {
      // Use buyNonConsumable for one-time upgrades
      final bool success = await _iap.buyNonConsumable(purchaseParam: purchaseParam);
      if (kDebugMode) print("IAP buyNonConsumable initiated: Success=$success");
      _clearError(); // Clear previous errors on initiating purchase
      notifyListeners();
      return success; // Indicates if the purchase flow started, not if it succeeded yet
    } catch (e) {
      if (kDebugMode) print("IAP Exception during buyNonConsumable: $e");
      _setError("An error occurred while starting the purchase.");
      notifyListeners();
      return false;
    }
  }

  void _setError(String message) {
    _errorMessage = message;
    _isLoading = false; // Usually stop loading on error
    notifyListeners();
  }

   void _clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
