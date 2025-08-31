import 'package:intl/intl.dart';

class CurrencyFormatter {
  static final NumberFormat _formatter = NumberFormat('#,###', 'en_US');

  /// Formats a double price to Rwandan Francs with comma separators and no decimals
  static String formatPrice(double price) {
    return '${_formatter.format(price.round())} Rwf';
  }

  /// Formats a price change with sign and percentage
  static String formatPriceChange(double change, double originalPrice) {
    final changePercent = (change / originalPrice) * 100;
    final prefix = change >= 0 ? '+' : '';
    final formattedChange = _formatter.format(change.abs().round());

    return '$prefix$formattedChange Rwf ($prefix${changePercent.toStringAsFixed(1)}%)';
  }

  /// Parses a string input to a double (removes commas and handles Rwf prefix)
  static double parsePrice(String priceText) {
    // Remove Rwf prefix and commas, then parse
    String cleanText =
        priceText.replaceAll('Rwf', '').replaceAll(',', '').trim();
    return double.parse(cleanText);
  }
}
