import 'package:flutter_test/flutter_test.dart';
import 'package:manos_chacabuco/core/money/decimal_value.dart';
import 'package:manos_chacabuco/core/money/money.dart';
import 'package:manos_chacabuco/domain/common/sync_metadata.dart';
import 'package:manos_chacabuco/domain/quotes/quote_models.dart';
import 'package:manos_chacabuco/domain/services/quote_engine.dart';

void main() {
  const engine = QuoteEngine();
  final now = DateTime.utc(2026, 9, 2);

  test('calcula cantidad, múltiples ítems y ajustes generales', () {
    final first = _item(id: 'a', unitPriceMinor: 1000000, quantity: 3);
    final second = _item(id: 'b', unitPriceMinor: 500000, quantity: 2);
    final general = _adjustment(
      id: 'g',
      description: 'Descuento',
      amountMinor: -100000,
    );

    expect(engine.itemSubtotal(first), const Money.ars(3000000));
    expect(
      engine.total(items: [first, second], generalAdjustments: [general]),
      const Money.ars(3900000),
    );
  });

  test('aplica ajustes positivos y negativos al precio final por unidad', () {
    final positive = engine.finalUnitPrice(
      calculatedPrice: const Money.ars(1000000),
      itemAdjustments: [
        _adjustment(
          id: 'positive',
          description: 'Tapa especial',
          amountMinor: 200000,
        ),
      ],
    );
    final negative = engine.finalUnitPrice(
      calculatedPrice: const Money.ars(1000000),
      itemAdjustments: [
        _adjustment(
          id: 'negative',
          description: 'Descuento',
          amountMinor: -100000,
        ),
      ],
    );

    expect(positive, const Money.ars(1200000));
    expect(
      engine.itemSubtotal(
        _item(
          id: 'positive-item',
          unitPriceMinor: positive.minorUnits,
          quantity: 2,
        ),
      ),
      const Money.ars(2400000),
    );
    expect(negative, const Money.ars(900000));
  });

  test('calcula validez, estado y nueva fecha al duplicar', () {
    final date = DateTime.utc(2026, 9, 2);
    expect(engine.calculateValidUntil(date, 15), DateTime.utc(2026, 9, 17));
    expect(engine.calculateValidityDays(date, DateTime.utc(2026, 9, 17)), 15);
    final quote = Quote(
      metadata: SyncMetadata(id: 'q', createdAt: now, updatedAt: now),
      customerName: 'María',
      date: date,
      validityDays: 15,
      validUntil: DateTime.utc(2026, 9, 17),
      priceType: QuotePriceType.retail,
      total: const Money.ars(1000000),
    );
    expect(
      engine.validityStatus(quote, DateTime.utc(2026, 9, 17)),
      QuoteValidityStatus.current,
    );
    expect(
      engine.validityStatus(quote, DateTime.utc(2026, 9, 18)),
      QuoteValidityStatus.expired,
    );
    expect(
      engine.calculateValidUntil(DateTime.utc(2026, 9, 20), 15),
      DateTime.utc(2026, 10, 5),
    );
  });

  test('advierte mínimo mayorista solamente cuando corresponde', () {
    expect(
      engine.isBelowWholesaleMinimum(
        priceType: QuotePriceType.wholesale,
        total: const Money.ars(9000000),
        minimum: const Money.ars(10000000),
      ),
      isTrue,
    );
    expect(
      engine.isBelowWholesaleMinimum(
        priceType: QuotePriceType.wholesale,
        total: const Money.ars(11000000),
        minimum: const Money.ars(10000000),
      ),
      isFalse,
    );
    expect(
      engine.isBelowWholesaleMinimum(
        priceType: QuotePriceType.retail,
        total: const Money.ars(100),
        minimum: const Money.ars(10000000),
      ),
      isFalse,
    );
  });
}

QuoteItem _item({
  required String id,
  required int unitPriceMinor,
  required int quantity,
}) {
  final now = DateTime.utc(2026, 9, 2);
  final price = Money.ars(unitPriceMinor);
  return QuoteItem(
    metadata: SyncMetadata(id: id, createdAt: now, updatedAt: now),
    quoteId: 'quote',
    name: id,
    quantity: quantity,
    priceMultiplier: DecimalValue.one,
    usages: const [],
    snapshot: _snapshot(price, now),
    unitPrice: price,
  );
}

QuoteAdjustment _adjustment({
  required String id,
  required String description,
  required int amountMinor,
}) {
  final now = DateTime.utc(2026, 9, 2);
  return QuoteAdjustment(
    metadata: SyncMetadata(id: id, createdAt: now, updatedAt: now),
    quoteId: 'quote',
    description: description,
    amount: Money.ars(amountMinor),
  );
}

QuoteItemSnapshot _snapshot(Money price, DateTime now) => QuoteItemSnapshot(
  materials: const [],
  primaryMaterials: Money.ars(price.minorUnits),
  thread: Money.zeroArs,
  waste: Money.zeroArs,
  complementaryMaterials: Money.zeroArs,
  totalCost: Money.ars(price.minorUnits),
  threadPercentage: DecimalValue.zero,
  wastePercentage: DecimalValue.zero,
  multiplier: DecimalValue.one,
  wholesalePrice: price,
  retailPercentage: null,
  capturedAt: now,
);
