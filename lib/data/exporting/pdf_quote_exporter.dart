import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/formatting/argentine_number_formatter.dart';
import '../../core/money/money.dart';
import '../../domain/price_lists/price_list_models.dart';
import '../../domain/quotes/quote_models.dart';

final class PdfQuoteExporter {
  const PdfQuoteExporter();

  Future<GeneratedPriceListFile> export(QuoteAggregate aggregate) async {
    final quote = aggregate.quote;
    final pdf = pw.Document(
      title: 'Presupuesto - ${quote.customerName}',
      author: 'Manos Chacabuco',
      creator: 'Manos Chacabuco',
    );
    final regularFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
    );
    final boldFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Bold.ttf'),
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(38, 34, 38, 42),
        theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
        header: (context) => context.pageNumber == 1
            ? pw.SizedBox()
            : pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 12),
                child: pw.Text(
                  'MANOS CHACABUCO - PRESUPUESTO',
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
        footer: (context) => _footer(context),
        build: (_) => [
          _documentHeader(aggregate),
          pw.SizedBox(height: 22),
          _itemsTable(aggregate),
          pw.SizedBox(height: 18),
          _totals(aggregate),
          if (quote.notes?.trim().isNotEmpty ?? false) ...[
            pw.SizedBox(height: 20),
            pw.Text(
              'Observaciones',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 5),
            pw.Text(
              quote.notes!.trim(),
              style: const pw.TextStyle(fontSize: 9),
            ),
          ],
        ],
      ),
    );

    final bytes = await pdf.save();
    return GeneratedPriceListFile(
      name: _fileName(quote),
      mimeType: 'application/pdf',
      bytes: bytes,
      pageCount: 1,
    );
  }

  pw.Widget _documentHeader(QuoteAggregate aggregate) {
    final quote = aggregate.quote;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(
          'MANOS CHACABUCO',
          style: pw.TextStyle(
            fontSize: 18,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'PRESUPUESTO',
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 18),
        pw.Text(
          'Cliente: ${quote.customerName}',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 5),
        pw.Text(
          'Vigencia de la oferta: hasta el ${_date(quote.validUntil)} '
          '(${quote.validityDays} días)',
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Fecha: ${_date(quote.date)}  |  Precio ${quote.priceType == QuotePriceType.retail ? 'minorista' : 'mayorista'}',
          style: const pw.TextStyle(fontSize: 9),
        ),
        pw.SizedBox(height: 12),
        pw.Divider(color: PdfColors.black, thickness: 1),
      ],
    );
  }

  pw.Widget _itemsTable(QuoteAggregate aggregate) {
    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: [
          _cell('Producto', bold: true),
          _cell('Cant.', bold: true, align: pw.TextAlign.center),
          _cell('Unidad', bold: true, align: pw.TextAlign.center),
          _cell('Color', bold: true),
          _cell('Precio unit.', bold: true, align: pw.TextAlign.right),
          _cell('Subtotal', bold: true, align: pw.TextAlign.right),
        ],
      ),
      for (final item in aggregate.items)
        pw.TableRow(
          children: [
            _productCell(item),
            _cell('${item.quantity}', align: pw.TextAlign.center),
            _cell('u.', align: pw.TextAlign.center),
            _cell(_colors(item)),
            _cell(
              ArgentineNumberFormatter.commercialMoney(item.unitPrice),
              align: pw.TextAlign.right,
            ),
            _cell(
              ArgentineNumberFormatter.commercialMoney(_itemSubtotal(item)),
              align: pw.TextAlign.right,
              bold: true,
            ),
          ],
        ),
    ];
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(3.2),
        1: pw.FlexColumnWidth(0.7),
        2: pw.FlexColumnWidth(0.9),
        3: pw.FlexColumnWidth(1.5),
        4: pw.FlexColumnWidth(1.5),
        5: pw.FlexColumnWidth(1.5),
      },
      children: rows,
    );
  }

  pw.Widget _productCell(QuoteItem item) => pw.Padding(
    padding: const pw.EdgeInsets.all(7),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          item.name,
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        ),
        if (item.personalizationDescription?.trim().isNotEmpty ?? false) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            item.personalizationDescription!.trim(),
            style: const pw.TextStyle(fontSize: 7.5),
          ),
        ],
      ],
    ),
  );

  pw.Widget _cell(
    String value, {
    bool bold = false,
    pw.TextAlign align = pw.TextAlign.left,
  }) => pw.Padding(
    padding: const pw.EdgeInsets.all(7),
    child: pw.Text(
      value,
      textAlign: align,
      style: pw.TextStyle(
        fontSize: 8.5,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );

  pw.Widget _totals(QuoteAggregate aggregate) {
    final productSubtotal = _productSubtotal(aggregate);
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.SizedBox(
        width: 260,
        child: pw.Column(
          children: [
            _totalRow('Subtotal de productos', productSubtotal),
            for (final adjustment in aggregate.generalAdjustments)
              _totalRow(adjustment.description, adjustment.amount),
            pw.Divider(color: PdfColors.black, thickness: 1),
            _totalRow('TOTAL', aggregate.quote.total, strong: true),
          ],
        ),
      ),
    );
  }

  pw.Widget _totalRow(String label, Money amount, {bool strong = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 4),
        child: pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(
                label,
                style: pw.TextStyle(
                  fontSize: strong ? 11 : 9,
                  fontWeight: strong
                      ? pw.FontWeight.bold
                      : pw.FontWeight.normal,
                ),
              ),
            ),
            pw.Text(
              ArgentineNumberFormatter.commercialMoney(amount),
              style: pw.TextStyle(
                fontSize: strong ? 12 : 9,
                fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ],
        ),
      );

  pw.Widget _footer(pw.Context context) => pw.Container(
    padding: const pw.EdgeInsets.only(top: 8),
    decoration: const pw.BoxDecoration(
      border: pw.Border(top: pw.BorderSide(color: PdfColors.black, width: 0.6)),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Expanded(
          child: pw.Text(
            'Tel. 2352 443476 / 2364 697104\n'
            'Instagram: @manoschacabuco  |  Facebook: manoschacabuco',
            style: const pw.TextStyle(fontSize: 8),
          ),
        ),
        pw.Text(
          '${context.pageNumber} de ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8),
        ),
      ],
    ),
  );

  Money _itemSubtotal(QuoteItem item) => Money(
    minorUnits: item.unitPrice.minorUnits * item.quantity,
    currency: item.unitPrice.currency,
  );

  Money _productSubtotal(QuoteAggregate aggregate) {
    var total = Money(minorUnits: 0, currency: aggregate.quote.total.currency);
    for (final item in aggregate.items) {
      total = total + _itemSubtotal(item);
    }
    return total;
  }

  String _colors(QuoteItem item) {
    final values = <String>{
      for (final material in item.snapshot.materials)
        if (material.variantName?.trim().isNotEmpty ?? false)
          material.variantName!.trim(),
    };
    return values.isEmpty ? '-' : values.join(', ');
  }

  String _fileName(Quote quote) {
    final customer = quote.customerName
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final safeCustomer = customer.isEmpty ? 'Cliente' : customer;
    final date = quote.date.toLocal().toIso8601String().substring(0, 10);
    return 'Presupuesto_${safeCustomer}_$date.pdf';
  }

  String _date(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year}';
  }
}
