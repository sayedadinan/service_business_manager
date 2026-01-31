import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;

class PdfService {
  Future<File> generateInvoice({
    required String clientName,
    required String description,
    required double amount,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text("Al-Rawda - Fabrication & Sign Board",
                  style: pw.TextStyle(
                      fontSize: 24, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              pw.Text("To,"),
              pw.Text(clientName),
              pw.SizedBox(height: 20),
              pw.Text("Description: $description"),
              pw.SizedBox(height: 10),
              pw.Text("Amount: \$${amount.toStringAsFixed(2)}"),
            ],
          );
        },
      ),
    );

    return _savePdf(pdf);
  }

  Future<File> _savePdf(pw.Document pdf) async {
    final output = await getTemporaryDirectory();
    final file = File("${output.path}/invoice.pdf");
    await file.writeAsBytes(await pdf.save());
    return file;
  }
}
