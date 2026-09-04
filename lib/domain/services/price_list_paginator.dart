import '../price_lists/price_list_models.dart';

final class PriceListPaginator {
  const PriceListPaginator();

  List<PriceListPage> paginate(
    PriceListDocument document, {
    required PriceListRenderTarget target,
  }) => document.showPhotos
      ? _paginatePhotoLayout(document, target)
      : _paginateEditorialLayout(document, target);

  List<PriceListPage> _paginatePhotoLayout(
    PriceListDocument document,
    PriceListRenderTarget target,
  ) {
    final rowCapacity = target == PriceListRenderTarget.pdf ? 3 : 2;
    final pageGroups = <List<PriceListGroup>>[];
    var current = <PriceListGroup>[];
    var remainingRows = rowCapacity;

    for (final group in document.groups) {
      var offset = 0;
      while (offset < group.items.length) {
        if (remainingRows == 0) {
          pageGroups.add(current);
          current = <PriceListGroup>[];
          remainingRows = rowCapacity;
        }
        final available = group.items.length - offset;
        final pageItemCapacity = remainingRows * 2;
        final count = available < pageItemCapacity
            ? available
            : pageItemCapacity;
        final items = group.items.sublist(offset, offset + count);
        current.add(PriceListGroup(name: group.name, items: items));
        offset += count;
        remainingRows -= (count + 1) ~/ 2;
      }
    }
    if (current.isNotEmpty) pageGroups.add(current);

    return _numbered(pageGroups);
  }

  List<PriceListPage> _paginateEditorialLayout(
    PriceListDocument document,
    PriceListRenderTarget target,
  ) {
    final heightCapacity = target == PriceListRenderTarget.pdf ? 625 : 990;
    final itemHeight = target == PriceListRenderTarget.pdf ? 47 : 88;
    final namedGroupOverhead = target == PriceListRenderTarget.pdf ? 27 : 46;
    final pageColumns = <List<PriceListColumn>>[];
    var currentPage = <PriceListColumn>[];
    var currentGroups = <PriceListGroup>[];
    var remainingHeight = heightCapacity;

    void finishColumn() {
      if (currentGroups.isNotEmpty) {
        currentPage.add(PriceListColumn(groups: currentGroups));
      }
      currentGroups = <PriceListGroup>[];
      remainingHeight = heightCapacity;
      if (currentPage.length == 2) {
        pageColumns.add(currentPage);
        currentPage = <PriceListColumn>[];
      }
    }

    for (final group in document.groups) {
      var offset = 0;
      while (offset < group.items.length) {
        final overhead = group.name == null ? 0 : namedGroupOverhead;
        var byHeight = (remainingHeight - overhead) ~/ itemHeight;
        if (byHeight <= 0) {
          finishColumn();
          byHeight = (remainingHeight - overhead) ~/ itemHeight;
        }
        final available = group.items.length - offset;
        final count = available < byHeight ? available : byHeight;
        final items = group.items.sublist(offset, offset + count);
        currentGroups.add(PriceListGroup(name: group.name, items: items));
        offset += count;
        remainingHeight -= overhead + count * itemHeight;
        if (offset < group.items.length) finishColumn();
      }
    }
    finishColumn();
    if (currentPage.isNotEmpty) pageColumns.add(currentPage);
    if (pageColumns.isNotEmpty) {
      pageColumns[pageColumns.length - 1] = _balanceFinalEditorialPage(
        pageColumns.last,
        heightCapacity: heightCapacity,
        itemHeight: itemHeight,
        groupOverhead: namedGroupOverhead,
      );
    }

    return [
      for (var index = 0; index < pageColumns.length; index++)
        PriceListPage(
          number: index + 1,
          editorialColumns: pageColumns[index],
          groups: [for (final column in pageColumns[index]) ...column.groups],
        ),
    ];
  }

  List<PriceListColumn> _balanceFinalEditorialPage(
    List<PriceListColumn> columns, {
    required int heightCapacity,
    required int itemHeight,
    required int groupOverhead,
  }) {
    final groups = <PriceListGroup>[];
    for (final column in columns) {
      for (final group in column.groups) {
        if (groups.isNotEmpty && groups.last.name == group.name) {
          final previous = groups.removeLast();
          groups.add(
            PriceListGroup(
              name: group.name,
              items: [...previous.items, ...group.items],
            ),
          );
        } else {
          groups.add(group);
        }
      }
    }
    final itemCount = groups.fold<int>(
      0,
      (total, group) => total + group.items.length,
    );
    if (itemCount < 2) return columns;

    List<PriceListGroup> slice(int start, int end) {
      final result = <PriceListGroup>[];
      var cursor = 0;
      for (final group in groups) {
        final groupStart = cursor;
        final groupEnd = cursor + group.items.length;
        final sliceStart = start > groupStart ? start : groupStart;
        final sliceEnd = end < groupEnd ? end : groupEnd;
        if (sliceStart < sliceEnd) {
          result.add(
            PriceListGroup(
              name: group.name,
              items: group.items.sublist(
                sliceStart - groupStart,
                sliceEnd - groupStart,
              ),
            ),
          );
        }
        cursor = groupEnd;
      }
      return result;
    }

    int height(List<PriceListGroup> value) => value.fold<int>(
      0,
      (total, group) =>
          total +
          (group.name == null ? 0 : groupOverhead) +
          group.items.length * itemHeight,
    );

    List<PriceListColumn>? best;
    var bestDifference = 1 << 30;
    for (var split = 1; split < itemCount; split++) {
      final left = slice(0, split);
      final right = slice(split, itemCount);
      final leftHeight = height(left);
      final rightHeight = height(right);
      if (leftHeight > heightCapacity || rightHeight > heightCapacity) {
        continue;
      }
      final difference = (leftHeight - rightHeight).abs();
      if (difference < bestDifference) {
        bestDifference = difference;
        best = [PriceListColumn(groups: left), PriceListColumn(groups: right)];
      }
    }
    return best ?? columns;
  }

  List<PriceListPage> _numbered(List<List<PriceListGroup>> pageGroups) => [
    for (var index = 0; index < pageGroups.length; index++)
      PriceListPage(number: index + 1, groups: pageGroups[index]),
  ];
}
