import '../formatting/argentine_number_formatter.dart';
import 'money.dart';

final class MoneyFormatter {
  MoneyFormatter({this.locale = 'es_AR'});

  final String locale;

  String format(Money money) => ArgentineNumberFormatter.money(money);
}
