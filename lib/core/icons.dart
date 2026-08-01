import 'package:flutter/material.dart';

/// Category marks are drawn, not typed. Each category stores a short key;
/// this resolves it to a line icon so the whole app shares one visual
/// weight instead of a pile of mismatched emoji.
abstract final class LedgerIcons {
  static const fallback = Icons.circle_outlined;

  /// Key → glyph. Keys are stable and stored in the database; the glyphs
  /// behind them can change without a migration.
  static const catalogue = <String, IconData>{
    // everyday
    'cup': Icons.local_cafe_outlined,
    'meal': Icons.restaurant_outlined,
    'basket': Icons.shopping_basket_outlined,
    'bag': Icons.shopping_bag_outlined,
    'bus': Icons.directions_bus_outlined,
    'train': Icons.tram_outlined,
    'fuel': Icons.local_gas_station_outlined,
    'car': Icons.directions_car_outlined,
    // home & bills
    'home': Icons.home_outlined,
    'bill': Icons.receipt_long_outlined,
    'phone': Icons.smartphone_outlined,
    'bolt': Icons.bolt_outlined,
    'wifi': Icons.wifi_outlined,
    // life
    'film': Icons.movie_outlined,
    'music': Icons.headphones_outlined,
    'book': Icons.menu_book_outlined,
    'gift': Icons.card_giftcard_outlined,
    'health': Icons.local_hospital_outlined,
    'gym': Icons.fitness_center_outlined,
    'pet': Icons.pets_outlined,
    'travel': Icons.flight_takeoff_outlined,
    'people': Icons.group_outlined,
    'school': Icons.school_outlined,
    'tools': Icons.build_outlined,
    'shirt': Icons.checkroom_outlined,
    // money
    'work': Icons.work_outline,
    'up': Icons.trending_up,
    'save': Icons.savings_outlined,
    'bank': Icons.account_balance_outlined,
    'card': Icons.credit_card_outlined,
    'cash': Icons.payments_outlined,
    'phone_pay': Icons.qr_code_2_outlined,
    'circle': Icons.circle_outlined,
  };

  static IconData resolve(String? key) => catalogue[key] ?? fallback;

  /// The picker's order — everyday things first.
  static List<String> get keys => catalogue.keys.toList();

  /// Account kinds get their own marks.
  static const account = <String, IconData>{
    'bank': Icons.account_balance_outlined,
    'upi': Icons.qr_code_2_outlined,
    'cash': Icons.payments_outlined,
    'card': Icons.credit_card_outlined,
    'asset': Icons.trending_up,
    'liability': Icons.trending_down,
  };
}
