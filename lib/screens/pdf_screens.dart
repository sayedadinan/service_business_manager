import 'package:alrawda_app/colors.dart';
import 'package:alrawda_app/screens/invoice_form_screen.dart';
import 'package:alrawda_app/services/database_helper.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'dart:io';
import 'package:printing/printing.dart';

class HomeScreen extends StatefulWidget {
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Key to control the RefreshIndicator and trigger manual refreshes
  final _refreshKey = GlobalKey<RefreshIndicatorState>();
  // Future to hold the invoice data, allowing manual refresh
  late Future<List<Map<String, dynamic>>> _invoicesFuture;

  @override
  void initState() {
    super.initState();
    // Initialize the future for invoices
    _invoicesFuture = DatabaseHelper.instance.getInvoices();
  }

  // Method to refresh the invoice list
  Future<void> _refreshInvoices() async {
    setState(() {
      _invoicesFuture = DatabaseHelper.instance.getInvoices();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Al-Rawda Invoices", style: TextStyle(color: Colors.white)),
        centerTitle: true,
        backgroundColor: AppColors.primaryColor,
        elevation: 4,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Refresh Invoices',
            onPressed: _refreshInvoices,
          ),
        ],
      ),
      body: RefreshIndicator(
        key: _refreshKey,
        onRefresh: _refreshInvoices,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _invoicesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text("Error loading invoices: ${snapshot.error}"),
                    SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _refreshInvoices,
                      child: Text("Retry"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryColor,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              );
            }
            final invoices = snapshot.data ?? [];
            if (invoices.isEmpty) {
              return Center(
                child: Text(
                  "No invoices saved.",
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              );
            }
            return ListView.builder(
              padding: EdgeInsets.all(16),
              itemCount: invoices.length,
              itemBuilder: (context, index) {
                final invoice = invoices[index];
                return Card(
                  elevation: 3,
                  margin: EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    title: Text(
                      invoice['clientName']?.toString() ?? 'Unnamed Client',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      'Date: ${invoice['selectedDate'] != null ? DateFormat('dd/MM/yyyy').format(DateTime.parse(invoice['selectedDate'])) : 'N/A'} | Type: ${invoice['pdfType']?.toString() ?? 'N/A'}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (invoice['pdfPath'] != null)
                          IconButton(
                            icon: Icon(Icons.picture_as_pdf, color: AppColors.primaryColor),
                            tooltip: 'View PDF',
                            onPressed: () async {
                              final pdfPath = invoice['pdfPath'] as String?;
                              if (pdfPath != null && await File(pdfPath).exists()) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => PDFViewerScreen(pdfPath: pdfPath),
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('PDF file not found')),
                                );
                              }
                            },
                          ),
                        IconButton(
                          icon: Icon(Icons.delete, color: Colors.red),
                          tooltip: 'Delete Invoice',
                          onPressed: () async {
                            try {
                              await DatabaseHelper.instance.deleteInvoice(
                                invoice['id'] as int,
                                invoice['pdfPath'] as String?,
                              );
                              // Refresh the invoice list after deletion
                              await _refreshInvoices();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Invoice deleted successfully')),
                              );
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error deleting invoice: $e')),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => InvoiceFormScreen(invoice: invoice,context: context,),
                        ),
                      ).then((_) {
                        // Refresh invoices when returning from InvoiceFormScreen
                        _refreshInvoices();
                      });
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primaryColor,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => InvoiceFormScreen(context: context,)),
          ).then((_) {
            // Refresh invoices when returning from InvoiceFormScreen
            _refreshInvoices();
          });
        },
        child: Icon(Icons.add, color: Colors.white),
        tooltip: 'Create New Invoice',
      ),
    );
  }
}

class PDFViewerScreen extends StatelessWidget {
  final String pdfPath;

  const PDFViewerScreen({required this.pdfPath, super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("View PDF", style: TextStyle(color: Colors.white)),
        backgroundColor: AppColors.primaryColor,
        actions: [
          IconButton(
            icon: Icon(Icons.share, color: Colors.white),
            tooltip: 'Share PDF',
            onPressed: () async {
              if (await File(pdfPath).exists()) {
                await Printing.sharePdf(
                  bytes: await File(pdfPath).readAsBytes(),
                  filename: 'invoice.pdf',
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('PDF file not found')),
                );
              }
            },
          ),
        ],
      ),
      body: PDFView(
        filePath: pdfPath,
        onError: (error) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error loading PDF: $error')),
          );
        },
      ),
    );
  }
}