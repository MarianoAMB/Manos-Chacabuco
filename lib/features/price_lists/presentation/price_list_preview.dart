import 'package:flutter/material.dart';

import '../../../core/design_system/app_colors.dart';
import '../../../core/design_system/app_tokens.dart';
import '../../../core/design_system/components/app_file_image.dart';
import '../../../core/formatting/argentine_number_formatter.dart';
import '../../../domain/price_lists/price_list_models.dart';
import '../../../domain/services/price_list_paginator.dart';

final class PriceListPreview extends StatelessWidget {
  const PriceListPreview({required this.document, super.key});

  final PriceListDocument document;

  @override
  Widget build(BuildContext context) {
    final pages = const PriceListPaginator().paginate(
      document,
      target: PriceListRenderTarget.image,
    );
    if (pages.isEmpty) {
      return const _EmptyPreview();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < pages.length; index++) ...[
          _PreviewPage(
            document: document,
            page: pages[index],
            pageCount: pages.length,
          ),
          if (index < pages.length - 1) const SizedBox(height: AppSpacing.lg),
        ],
      ],
    );
  }
}

final class _PreviewPage extends StatelessWidget {
  const _PreviewPage({
    required this.document,
    required this.page,
    required this.pageCount,
  });

  final PriceListDocument document;
  final PriceListPage page;
  final int pageCount;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 600),
      child: AspectRatio(
        aspectRatio: PngPreviewSize.width / PngPreviewSize.height,
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: 600,
            height: 750,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.canvas,
                borderRadius: BorderRadius.circular(AppRadii.sm),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.09),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _PreviewHeader(document: document),
                    if (document.wholesaleMinimum != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.sageSoft,
                          borderRadius: BorderRadius.circular(AppRadii.sm),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.xs,
                          ),
                          child: Text(
                            'Compra mínima mayorista: ${ArgentineNumberFormatter.commercialMoney(document.wholesaleMinimum!)}',
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    Expanded(
                      child: document.showPhotos
                          ? _PhotoPreview(groups: page.groups)
                          : _EditorialPreview(columns: page.editorialColumns),
                    ),
                    const Divider(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            document.footerNote ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: AppColors.mutedInk),
                          ),
                        ),
                        Text(
                          '${page.number} de $pageCount',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: AppColors.mutedInk),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

final class _PreviewHeader extends StatelessWidget {
  const _PreviewHeader({required this.document});

  final PriceListDocument document;

  @override
  Widget build(BuildContext context) {
    final logo = document.logoPath;
    final hasLogo = logo != null;
    return Row(
      children: [
        if (hasLogo) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.sm),
            child: SizedBox.square(
              dimension: 46,
              child: AppFileImage(
                path: logo,
                cacheWidth: 128,
                cacheHeight: 128,
                semanticLabel: 'Logo de ${document.businessName}',
                fallback: const ColoredBox(color: AppColors.surface),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                document.businessName.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.7),
              ),
              Text(
                document.type.title,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.terracotta,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        if (document.showUpdatedDate)
          Text(
            'Actualizado: ${_date(document.generatedAt)}',
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: AppColors.mutedInk),
          ),
      ],
    );
  }

  String _date(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year}';
  }
}

final class _PhotoPreview extends StatelessWidget {
  const _PhotoPreview({required this.groups});

  final List<PriceListGroup> groups;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    physics: const NeverScrollableScrollPhysics(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final group in groups) ...[
          if (group.name != null) _CategoryTitle(group.name!),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: group.items.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: AppSpacing.xs,
              mainAxisSpacing: AppSpacing.xs,
              childAspectRatio: 1.75,
            ),
            itemBuilder: (context, index) =>
                _ProductCard(item: group.items[index]),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
      ],
    ),
  );
}

final class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.item});

  final PriceListItem item;

  @override
  Widget build(BuildContext context) {
    final path = item.photoPath;
    final details = [
      item.dimensionsText,
      item.materialText,
    ].whereType<String>().where((value) => value.isNotEmpty).join(' · ');
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: AppColors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.sm),
              child: SizedBox.square(
                dimension: 70,
                child: path != null
                    ? AppFileImage(
                        path: path,
                        cacheWidth: 180,
                        cacheHeight: 180,
                        semanticLabel: 'Foto de ${item.name}',
                        fallback: const _MissingPhoto(),
                      )
                    : const ColoredBox(
                        color: AppColors.terracottaSoft,
                        child: Center(
                          child: Text(
                            'Sin foto',
                            style: TextStyle(
                              color: AppColors.terracotta,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (details.isNotEmpty)
                    Text(
                      details,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: AppColors.mutedInk),
                    ),
                  const Spacer(),
                  Text(
                    ArgentineNumberFormatter.commercialMoney(item.price),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: AppColors.terracotta,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _MissingPhoto extends StatelessWidget {
  const _MissingPhoto();

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: AppColors.terracottaSoft,
    child: Center(
      child: Text(
        'Sin foto',
        style: TextStyle(
          color: AppColors.terracotta,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
  );
}

final class _EditorialPreview extends StatelessWidget {
  const _EditorialPreview({required this.columns});

  final List<PriceListColumn> columns;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var index = 0; index < 2; index++) ...[
        Expanded(
          child: index < columns.length
              ? _EditorialColumn(column: columns[index])
              : const SizedBox(),
        ),
        if (index == 0) const SizedBox(width: AppSpacing.md),
      ],
    ],
  );
}

final class _EditorialColumn extends StatelessWidget {
  const _EditorialColumn({required this.column});

  final PriceListColumn column;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final group in column.groups) ...[
        if (group.name != null) _EditorialCategoryTitle(group.name!),
        for (final item in group.items) _EditorialItem(item: item),
        const SizedBox(height: AppSpacing.xs),
      ],
    ],
  );
}

final class _EditorialItem extends StatelessWidget {
  const _EditorialItem({required this.item});

  final PriceListItem item;

  @override
  Widget build(BuildContext context) {
    final details = [
      item.dimensionsText,
      item.materialText,
    ].whereType<String>().where((value) => value.isNotEmpty).join(' · ');
    return SizedBox(
      height: 48,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.outline)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (details.isNotEmpty)
                      Text(
                        details,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 8,
                          color: AppColors.mutedInk,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Text(
                ArgentineNumberFormatter.commercialMoney(item.price),
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.terracotta,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _EditorialCategoryTitle extends StatelessWidget {
  const _EditorialCategoryTitle(this.name);

  final String name;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: AppSpacing.xxs),
    height: 24,
    alignment: Alignment.centerLeft,
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
    decoration: BoxDecoration(
      color: AppColors.terracottaSoft,
      borderRadius: BorderRadius.circular(AppRadii.sm),
    ),
    child: Text(
      name.toUpperCase(),
      style: const TextStyle(
        fontSize: 8,
        color: AppColors.terracotta,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.7,
      ),
    ),
  );
}

final class _CategoryTitle extends StatelessWidget {
  const _CategoryTitle(this.name);

  final String name;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
    child: Text(
      name.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium
          ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.8),
    ),
  );
}

final class _EmptyPreview extends StatelessWidget {
  const _EmptyPreview();

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 320),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: AppColors.softSurface,
      borderRadius: BorderRadius.circular(AppRadii.md),
      border: Border.all(color: AppColors.outline),
    ),
    padding: const EdgeInsets.all(AppSpacing.xl),
    child: const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.visibility_outlined, color: AppColors.mutedInk, size: 40),
        SizedBox(height: AppSpacing.sm),
        Text('Elegí productos con precio para ver la lista.'),
      ],
    ),
  );
}

abstract final class PngPreviewSize {
  static const width = 1080.0;
  static const height = 1350.0;
}
