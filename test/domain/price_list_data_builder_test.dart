import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:manos_chacabuco/core/money/money.dart';
import 'package:manos_chacabuco/domain/price_lists/price_list_models.dart';
import 'package:manos_chacabuco/domain/services/price_list_data_builder.dart';
import 'package:manos_chacabuco/domain/services/price_list_paginator.dart';

void main() {
  const builder = PriceListDataBuilder();
  final generatedAt = DateTime.utc(2026, 9, 3);

  test('minorista usa el precio minorista y excluye faltantes e inactivos', () {
    final document = builder.build(
      products: _sources,
      config: const PriceListConfig(
        priceType: PriceListType.retail,
        selectedProductIds: {'a', 'b', 'c'},
      ),
      businessName: 'Manos Chacabuco',
      generatedAt: generatedAt,
    );

    expect(document.items, hasLength(1));
    expect(document.items.single.productId, 'a');
    expect(document.items.single.price, const Money.ars(2500000));
    expect(document.wholesaleMinimum, isNull);
  });

  test(
    'mayorista usa precio mayorista y muestra mínimo sólo si corresponde',
    () {
      final wholesale = builder.build(
        products: _sources,
        config: const PriceListConfig(
          priceType: PriceListType.wholesale,
          selectedProductIds: {'a', 'b'},
          showWholesaleMinimum: true,
        ),
        businessName: 'Manos Chacabuco',
        generatedAt: generatedAt,
        minimumWholesaleAmount: const Money.ars(15000000),
      );
      final retail = builder.build(
        products: _sources,
        config: const PriceListConfig(
          priceType: PriceListType.retail,
          selectedProductIds: {'a'},
          showWholesaleMinimum: true,
        ),
        businessName: 'Manos Chacabuco',
        generatedAt: generatedAt,
        minimumWholesaleAmount: const Money.ars(15000000),
      );

      expect(wholesale.items.map((item) => item.price), [
        const Money.ars(3000000),
        const Money.ars(2000000),
      ]);
      expect(wholesale.wholesaleMinimum, const Money.ars(15000000));
      expect(retail.wholesaleMinimum, isNull);
    },
  );

  test(
    'contenido opcional no deja textos vacíos y preserva fallback de foto',
    () {
      final visible = builder.build(
        products: _sources,
        config: const PriceListConfig(
          priceType: PriceListType.wholesale,
          selectedProductIds: {'a', 'b'},
          showPhotos: true,
          showDimensions: true,
          showMaterial: true,
        ),
        businessName: 'Manos Chacabuco',
        generatedAt: generatedAt,
      );
      final compact = builder.build(
        products: _sources,
        config: const PriceListConfig(
          priceType: PriceListType.wholesale,
          selectedProductIds: {'a'},
          showPhotos: false,
          showDimensions: false,
          showMaterial: false,
        ),
        businessName: 'Manos Chacabuco',
        generatedAt: generatedAt,
      );

      final withPhoto = visible.items.firstWhere(
        (item) => item.productId == 'a',
      );
      final withoutPhoto = visible.items.firstWhere(
        (item) => item.productId == 'b',
      );
      expect(withPhoto.photoPath, 'foto.png');
      expect(withoutPhoto.photoPath, isNull);
      expect(withoutPhoto.dimensionsText, isNull);
      expect(compact.items.single.photoPath, isNull);
      expect(compact.items.single.dimensionsText, isNull);
      expect(compact.items.single.materialText, isNull);
    },
  );

  test('ordena por nombre, categoría y ambos sentidos de precio', () {
    List<String> names(PriceListSort sort) => builder
        .build(
          products: _sources,
          config: PriceListConfig(
            priceType: PriceListType.wholesale,
            selectedProductIds: const {'a', 'b'},
            groupByCategory: false,
            sort: sort,
          ),
          businessName: 'Manos Chacabuco',
          generatedAt: generatedAt,
        )
        .items
        .map((item) => item.name)
        .toList();

    expect(names(PriceListSort.name), ['Cesto grande', 'Macetero natural']);
    expect(names(PriceListSort.category), ['Cesto grande', 'Macetero natural']);
    expect(names(PriceListSort.priceAscending), [
      'Macetero natural',
      'Cesto grande',
    ]);
    expect(names(PriceListSort.priceDescending), [
      'Cesto grande',
      'Macetero natural',
    ]);
  });

  test('agrupa sin categorías vacías y pagina de forma determinista', () {
    final document = builder.build(
      products: _sources,
      config: const PriceListConfig(
        priceType: PriceListType.wholesale,
        selectedProductIds: {'a', 'b'},
        groupByCategory: true,
      ),
      businessName: 'Manos Chacabuco',
      generatedAt: generatedAt,
    );
    final pages = const PriceListPaginator().paginate(
      document,
      target: PriceListRenderTarget.image,
    );

    expect(document.groups.map((group) => group.name), ['Cestos', 'Maceteros']);
    expect(document.groups.every((group) => group.items.isNotEmpty), isTrue);
    expect(pages.single.items.map((item) => item.productId), ['b', 'a']);
  });

  test('modelo client-facing no contiene ningún dato interno', () {
    final document = builder.build(
      products: _sources,
      config: const PriceListConfig(
        priceType: PriceListType.wholesale,
        selectedProductIds: {'a'},
      ),
      businessName: 'Manos Chacabuco',
      generatedAt: generatedAt,
    );
    final json = jsonEncode(document.toClientJson()).toLowerCase();

    for (final forbidden in [
      'totalcost',
      'materialcost',
      'threadcost',
      'wastecost',
      'multiplier',
      'internalnotes',
      'costbreakdown',
    ]) {
      expect(json, isNot(contains(forbidden)));
    }
  });

  test('paginación reserva espacio para encabezados de muchas categorías', () {
    PriceListDocument document({
      required bool showPhotos,
      required int count,
    }) => PriceListDocument(
      businessName: 'Manos Chacabuco',
      generatedAt: generatedAt,
      type: PriceListType.retail,
      showPhotos: showPhotos,
      showUpdatedDate: true,
      groups: [
        for (var index = 0; index < count; index++)
          PriceListGroup(
            name: 'Categoría $index',
            items: [
              PriceListItem(
                productId: 'producto-$index',
                name: 'Producto $index',
                categoryName: 'Categoría $index',
                price: Money.ars(1000000 + index),
              ),
            ],
          ),
      ],
    );

    final photoPages = const PriceListPaginator().paginate(
      document(showPhotos: true, count: 4),
      target: PriceListRenderTarget.image,
    );
    final editorialPages = const PriceListPaginator().paginate(
      document(showPhotos: false, count: 8),
      target: PriceListRenderTarget.image,
    );

    expect(photoPages, hasLength(2));
    expect(photoPages.every((page) => page.groups.length <= 2), isTrue);
    expect(editorialPages, hasLength(1));
    expect(editorialPages.single.editorialColumns, hasLength(2));
    expect(editorialPages.expand((page) => page.items), hasLength(8));
    expect(
      editorialPages
          .expand((page) => page.editorialColumns)
          .expand((column) => column.groups)
          .every((group) => group.items.isNotEmpty),
      isTrue,
    );
  });
}

const _sources = [
  PriceListSourceProduct(
    productId: 'a',
    name: 'Macetero natural',
    categoryId: 'maceteros',
    categoryName: 'Maceteros',
    isActive: true,
    photoPath: 'foto.png',
    dimensionsText: 'Ø 20 × 18 cm',
    materialText: 'Cordón de algodón N°7',
    wholesalePrice: Money.ars(2000000),
    retailPrice: Money.ars(2500000),
  ),
  PriceListSourceProduct(
    productId: 'b',
    name: 'Cesto grande',
    categoryId: 'cestos',
    categoryName: 'Cestos',
    isActive: true,
    wholesalePrice: Money.ars(3000000),
  ),
  PriceListSourceProduct(
    productId: 'c',
    name: 'Producto inactivo',
    categoryId: 'otros',
    categoryName: 'Otros',
    isActive: false,
    wholesalePrice: Money.ars(1000000),
    retailPrice: Money.ars(1200000),
  ),
];
