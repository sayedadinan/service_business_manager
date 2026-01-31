import 'dart:typed_data';
import 'package:alrawda_app/colors.dart';
import 'package:alrawda_app/screens/pdf_screens.dart';
import 'package:alrawda_app/services/database_helper.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';

class InvoiceFormScreen extends StatefulWidget {
  final Map<String, dynamic>? invoice; // Optional invoice for editing
final BuildContext context;
  InvoiceFormScreen({this.invoice, required this.context});

  @override
  _InvoiceFormScreenState createState() => _InvoiceFormScreenState();
}

class _InvoiceFormScreenState extends State<InvoiceFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController clientNameController = TextEditingController();
  final TextEditingController totalAmountController = TextEditingController();
  final TextEditingController advanceAmountController = TextEditingController();
  DateTime? selectedDate;
  String pdfType = 'Estimate';
  bool isVatEnabled = false;
  double vatPercentage = 5.0;
  bool isDiscountEnabled = false;
  double discountAmount = 0.0;
  List<TextEditingController> itemDescriptionControllers = [];
  List<TextEditingController> amountControllers = [];
  int? editingInvoiceId;
  String? currentPdfPath;
  Uint8List? _logoBytes; // Store logo image data

  @override
  void initState() {
    super.initState();
    // Load logo image in initState
    loadLogoImage(widget.context);
    if (widget.invoice != null) {
      _loadInvoice(widget.invoice!);
    } else {
      _addItemRow();
    }
  }

 

  @override
  void dispose() {
    clientNameController.dispose();
    totalAmountController.dispose();
    advanceAmountController.dispose();
    itemDescriptionControllers.forEach((controller) => controller.dispose());
    amountControllers.forEach((controller) => controller.dispose());
    super.dispose();
  }

  void _addItemRow() {
    setState(() {
      itemDescriptionControllers.add(TextEditingController());
      amountControllers.add(TextEditingController());
    });
  }

  void _removeItemRow(int index) {
    setState(() {
      if (itemDescriptionControllers.length > 1) {
        itemDescriptionControllers[index].dispose();
        amountControllers[index].dispose();
        itemDescriptionControllers.removeAt(index);
        amountControllers.removeAt(index);
      }
    });
  }

 

  Future<void> _saveFormData({bool goBack = false}) async {
    if (!_formKey.currentState!.validate()) return;

    final formData = {
      'clientName': clientNameController.text,
      'totalAmount': totalAmountController.text,
      'advanceAmount': advanceAmountController.text,
      'selectedDate': selectedDate?.toIso8601String(),
      'pdfType': pdfType,
      'isVatEnabled': isVatEnabled ? 1 : 0,
      'isDiscountEnabled': isDiscountEnabled ? 1 : 0,
      'discountAmount': discountAmount,
      'items': jsonEncode(itemDescriptionControllers
          .asMap()
          .entries
          .map((entry) => {
                'description': entry.value.text,
                'amount': amountControllers[entry.key].text,
              })
          .toList()),
      'pdfPath': currentPdfPath,
    };

    try {
      if (editingInvoiceId == null) {
        await DatabaseHelper.instance.insertInvoice(formData);
      } else {
        formData['id'] = editingInvoiceId;
        await DatabaseHelper.instance.updateInvoice(editingInvoiceId!, formData);
      }

      if (goBack) {
        DatabaseHelper.instance.getInvoices();
        Navigator.pop(widget.context);
      } else {
        _clearForm();
        ScaffoldMessenger.of(widget.context).showSnackBar(
          SnackBar(content: Text('Invoice saved successfully')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(widget.context).showSnackBar(
        SnackBar(content: Text('Error saving invoice: $e')),
      );
    }
  }

  void _clearForm() {
    setState(() {
      clientNameController.clear();
      totalAmountController.clear();
      advanceAmountController.clear();
      selectedDate = null;
      pdfType = 'Estimate';
      isVatEnabled = false;
      isDiscountEnabled = false;
      discountAmount = 0.0;
      itemDescriptionControllers.forEach((controller) => controller.dispose());
      amountControllers.forEach((controller) => controller.dispose());
      itemDescriptionControllers.clear();
      amountControllers.clear();
      editingInvoiceId = null;
      currentPdfPath = null;
      _addItemRow();
    });
  }

  void _loadInvoice(Map<String, dynamic> invoice) {
    setState(() {
      clientNameController.text = invoice['clientName']?.toString() ?? '';
      totalAmountController.text = invoice['totalAmount']?.toString() ?? '';
      advanceAmountController.text = invoice['advanceAmount']?.toString() ?? '';
      selectedDate = invoice['selectedDate'] != null
          ? DateTime.tryParse(invoice['selectedDate'])
          : null;
      pdfType = invoice['pdfType']?.toString() ?? 'Estimate';
      isVatEnabled = (invoice['isVatEnabled'] == 1);
      isDiscountEnabled = (invoice['isDiscountEnabled'] == 1);
      discountAmount = invoice['discountAmount']?.toDouble() ?? 0.0;
      currentPdfPath = invoice['pdfPath']?.toString();

      // Clear existing controllers
      itemDescriptionControllers.forEach((controller) => controller.dispose());
      amountControllers.forEach((controller) => controller.dispose());
      itemDescriptionControllers.clear();
      amountControllers.clear();

      // Parse items safely
      try {
        final items = jsonDecode(invoice['items'] ?? '[]') as List<dynamic>;
        for (var item in items) {
          itemDescriptionControllers.add(TextEditingController(text: item['description']?.toString() ?? ''));
          amountControllers.add(TextEditingController(text: item['amount']?.toString() ?? ''));
        }
      } catch (e) {
        print('Error parsing items: $e');
        // Initialize with one empty row if parsing fails
        _addItemRow();
      }

      editingInvoiceId = invoice['id'] as int?;
    });
  }

   Future<void> _generatePDF() async {
  if (!_formKey.currentState!.validate()) return;

  // Check if logo is loaded
  if (_logoBytes == null) {
    ScaffoldMessenger.of(widget.context).showSnackBar(
      SnackBar(content: Text('Failed to load logo image')),
    );
    return;
  }

  final pdf = pw.Document();
  final totalAmount = calculateTotalAmount();
  String currentDate = selectedDate != null
      ? DateFormat('dd.MM.yyyy').format(selectedDate!)
      : DateFormat('dd.MM.yyyy').format(DateTime.now());

  List<List<String>> itemList = [];
  for (int i = 0; i < itemDescriptionControllers.length; i++) {
    itemList.add([
      itemDescriptionControllers[i].text,
      amountControllers[i].text.isNotEmpty ? amountControllers[i].text : '0.0',
    ]);
  }

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (pw.Context context) {
        return [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(children: [
                    pw.Image(pw.MemoryImage(_logoBytes!), width: 50, height: 50),
                    pw.Text(
                      'Al-Rawda',
                      style: pw.TextStyle(
                        fontStyle: pw.FontStyle.italic,
                        fontSize: 37,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ]),
                  pw.SizedBox(height: 5),
                  pw.Row(
                    children: [
                      pw.SizedBox(height: 15),
                      pw.Text(
                        'Technical Services'.toUpperCase(),
                        style: pw.TextStyle(fontSize: 10),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 5),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Row(children: [
                    pw.Text('Fujairah, UAE', style: pw.TextStyle(fontSize: 12)),
                    pw.SizedBox(width: 4),
                    pw.Text('| 559290849 , 569173049', style: pw.TextStyle(fontSize: 12)),
                  ]),
                  pw.Row(children: [
                    pw.SizedBox(width: 5),
                    pw.Text('shahulmakkattmakkatt@gmail.com', style: pw.TextStyle(fontSize: 13)),
                  ]),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Row(
            children: [
              pw.Expanded(child: pw.Container(height: 1, color: PdfColors.black)),
              pw.Expanded(child: pw.Container(height: 1, color: PdfColors.blue)),
            ],
          ),
          pw.SizedBox(height: 25),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Text('Date: $currentDate', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            ],
          ),
          pw.Center(
            child: pw.Container(
              padding: const pw.EdgeInsets.all(6.0),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey,
                borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Text(
                pdfType.toUpperCase(),
                style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
              ),
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Text('To,'),
          pw.SizedBox(height: 5),
          pw.Text(
            'M/s. ${clientNameController.text}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 12),
          pw.Text('Dear Sir'),
          pw.SizedBox(height: 7),
          pw.Text(
            pdfType == 'Estimate'
                ? 'Pls. find the below Estimation details for the work we have done for you and kindly arrange the payment at the earliest.'
                : 'We hereby submit our lowest rate of quotation for providing you the work of name board and other jobs. Material specification is follows:',
          ),
          pw.SizedBox(height: 7),
          pw.Table(
            border: pw.TableBorder.all(),
            columnWidths: {
              0: pw.FlexColumnWidth(3),
              1: pw.FlexColumnWidth(1),
            },
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: PdfColors.lightBlue100),
                children: [
                  pw.Padding(
                    padding: pw.EdgeInsets.all(4),
                    child: pw.Text('Description', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.Padding(
                    padding: pw.EdgeInsets.all(4),
                    child: pw.Text('Amount', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ),
                ],
              ),
              ...itemList.map((item) {
                return pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: pw.EdgeInsets.all(4),
                      child: pw.Text(item[0], softWrap: true),
                    ),
                    pw.Padding(
                      padding: pw.EdgeInsets.all(4),
                      child: pw.Text(item[1]),
                    ),
                  ],
                );
              }).toList(),
              if (isVatEnabled)
                pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: pw.EdgeInsets.all(4),
                      child: pw.Text('VAT (${vatPercentage.toStringAsFixed(2)}%)'),
                    ),
                    pw.Padding(
                      padding: pw.EdgeInsets.all(4),
                      child: pw.Text((totalAmount * vatPercentage / 100).toStringAsFixed(2)),
                    ),
                  ],
                ),
              pw.TableRow(
                children: [
                  pw.Padding(
                    padding: pw.EdgeInsets.all(4),
                    child: pw.Text('Total Amount', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.Padding(
                    padding: pw.EdgeInsets.all(4),
                    child: pw.Text(
                      calculateTotalWithVATOnly(totalAmount).toStringAsFixed(2),
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                ],
              ),
              if (advanceAmountController.text.isNotEmpty)
                pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: pw.EdgeInsets.all(4),
                      child: pw.Text('Advance Amount'),
                    ),
                    pw.Padding(
                      padding: pw.EdgeInsets.all(4),
                      child: pw.Text(advanceAmountController.text),
                    ),
                  ],
                ),
              if (isDiscountEnabled)
                pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: pw.EdgeInsets.all(4),
                      child: pw.Text('Discount Applied'),
                    ),
                    pw.Padding(
                      padding: pw.EdgeInsets.all(4),
                      child: pw.Text('-${discountAmount.toStringAsFixed(2)}'),
                    ),
                  ],
                ),
              if (advanceAmountController.text.isNotEmpty)
                pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: pw.EdgeInsets.all(4),
                      child: pw.Text('Balance Amount', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    ),
                    pw.Padding(
                      padding: pw.EdgeInsets.all(4),
                      child: pw.Text(
                        (calculateTotalWithVATOnly(totalAmount) - 
                                (isDiscountEnabled ? discountAmount : 0.0) -
                                (double.tryParse(advanceAmountController.text) ?? 0.0))
                            .toStringAsFixed(2),
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            'All amounts in Dirhams',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          if (pdfType == 'Quotation') ...[
            pw.SizedBox(height: 5),
            pw.Text(
              'Payment Terms: 50% advance and 50% after delivery',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
          ],
          pw.SizedBox(height: 28),
          pw.Text(
            pdfType == 'Estimate'
                ? 'Thank you for your interest with us and assure our best service always.'
                : 'We hope this quotation meets your approval and look forward to your order.',
            style: pw.TextStyle(fontSize: 14),
          ),
          pw.SizedBox(height: 58),
          pw.Text('Best Regards,'),
          pw.SizedBox(height: 16),
          pw.Text(
            'Al Rawda Technical Services.',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 7),
          pw.Spacer(),
          pw.Row(
            children: [
              pw.Expanded(child: pw.Container(height: 1, color: PdfColors.black)),
              pw.Expanded(child: pw.Container(height: 1, color: PdfColors.blue)),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.SizedBox(width: 10),
              pw.Text('ACP WORKS'),
              pw.SizedBox(width: 10),
              pw.Container(width: 1, height: 12, color: PdfColors.black),
              pw.SizedBox(width: 10),
              pw.Text('LED BOARD'),
              pw.SizedBox(width: 10),
              pw.Container(width: 1, height: 12, color: PdfColors.black),
              pw.SizedBox(width: 10),
              pw.Text('VNYL PRINTING & INSTALLING'),
            ],
          ),
        ];
      },
    ),
  );

  try {
    // Save PDF to local storage
    final directory = await getApplicationDocumentsDirectory();
    final pdfPath = join(directory.path, 'invoice_${DateTime.now().millisecondsSinceEpoch}.pdf');
    final file = File(pdfPath);
    await file.writeAsBytes(await pdf.save());

    // Save invoice data to database
    setState(() {
      currentPdfPath = pdfPath;
    });
    await _saveFormData(goBack: false);

    // Show PDF
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );

    // Notify user of successful generation and save
    ScaffoldMessenger.of(widget.context).showSnackBar(
      SnackBar(content: Text('PDF generated and invoice saved successfully')),
    );
  } catch (e) {
    ScaffoldMessenger.of(widget.context).showSnackBar(
      SnackBar(content: Text('Error generating or saving PDF: $e')),
    );
  }
}
 Future<void> loadLogoImage(BuildContext context) async {
    try {
      final bytes = await loadImage('assets/images/alrawda_logo.png', context);
      setState(() {
        _logoBytes = bytes;
      });
    } catch (e) {
      print('Error loading logo: $e');
      // Optionally handle error (e.g., show a default image or notify user)
    }
  }
  double calculateTotalAmount() {
    double total = 0;
    for (var controller in amountControllers) {
      final value = double.tryParse(controller.text) ?? 0.0;
      total += value;
    }
    return total;
  }

  double calculateTotalWithVATOnly(double baseAmount) {
    double finalAmount = baseAmount;
    
    // Apply VAT only (no discount applied to total)
    if (isVatEnabled) {
      finalAmount = baseAmount * (1 + vatPercentage / 100);
    }
    
    return finalAmount;
  }

  double calculateFinalAmount(double baseAmount) {
    double finalAmount = baseAmount;
    
    // Apply discount first if enabled
    if (isDiscountEnabled) {
      finalAmount = baseAmount - discountAmount;
    }
    
    // Apply VAT on the discounted amount if VAT is enabled
    if (isVatEnabled) {
      finalAmount = finalAmount * (1 + vatPercentage / 100);
    }
    
    return finalAmount;
  }

  @override
  Widget build(BuildContext context) {
     // Load logo image from assets
 
    return Scaffold(
      appBar: AppBar(
        title: Text(
          editingInvoiceId == null ? "Create Invoice" : "Edit Invoice",
          style: TextStyle(color: Colors.white),
        ),
        centerTitle: true,
        backgroundColor: AppColors.primaryColor,
        elevation: 4,
      ),
      backgroundColor: AppColors.backgroundColor,
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              children: [
                _buildSectionCard(
                  child: DropdownButtonFormField<String>(
                    value: pdfType,
                    decoration: _inputDecoration("Select PDF Type"),
                    items: ['Estimate', 'Quotation'].map((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value, style: TextStyle(color: AppColors.secondaryColor)),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      setState(() {
                        pdfType = newValue!;
                      });
                    },
                  ),
                ),
                _buildSectionCard(
                  child: TextFormField(
                    controller: clientNameController,
                    decoration: _inputDecoration("Client Name", icon: Icons.person),
                    validator: (value) => value!.isEmpty ? 'Please enter client name' : null,
                  ),
                ),
                _buildSectionCard(
                  child: Column(children: _buildItemRows()),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    onPressed: _addItemRow,
                    icon: Icon(Icons.add, color: AppColors.whiteColor),
                    label: Text("Add Item", style: TextStyle(color: AppColors.whiteColor)),
                    style: _buttonStyle(),
                  ),
                ),
                _buildSectionCard(
                  child: TextFormField(
                    controller: advanceAmountController,
                    decoration: _inputDecoration("Advance Amount", icon: Icons.money),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value != null && value.isNotEmpty) {
                        final number = double.tryParse(value);
                        if (number == null || number < 0) {
                          return 'Please enter a valid amount';
                        }
                      }
                      return null;
                    },
                  ),
                ),
                _buildSectionCard(
                  child: TextFormField(
                    controller: totalAmountController,
                    decoration: _inputDecoration("Total Amount", icon: Icons.attach_money),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter total amount';
                      }
                      final number = double.tryParse(value);
                      if (number == null || number <= 0) {
                        return 'Please enter a valid positive amount';
                      }
                      return null;
                    },
                  ),
                ),
                _buildSectionCard(
                  child: SwitchListTile(
                    title: Text("Add VAT (5%)"),
                    value: isVatEnabled,
                    onChanged: (value) {
                      setState(() {
                        isVatEnabled = value;
                      });
                    },
                  ),
                ),
                _buildSectionCard(
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: Text("Add Discount"),
                        value: isDiscountEnabled,
                        onChanged: (value) {
                          setState(() {
                            isDiscountEnabled = value;
                            if (!value) {
                              discountAmount = 0.0;
                            }
                          });
                        },
                      ),
                      if (isDiscountEnabled)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: TextFormField(
                            initialValue: discountAmount.toString(),
                            decoration: _inputDecoration("Discount Amount", icon: Icons.money_off),
                            keyboardType: TextInputType.number,
                            onChanged: (value) {
                              setState(() {
                                discountAmount = double.tryParse(value) ?? 0.0;
                              });
                            },
                            validator: (value) {
                              if (isDiscountEnabled) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter discount amount';
                                }
                                final number = double.tryParse(value);
                                if (number == null || number < 0) {
                                  return 'Please enter a valid discount amount';
                                }
                              }
                              return null;
                            },
                          ),
                        ),
                    ],
                  ),
                ), 
                _buildSectionCard(
                  child: ElevatedButton.icon(
                    onPressed: () async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
      });
    }
  },
                    icon: Icon(Icons.calendar_today, color: AppColors.whiteColor),
                    label: Text(
                      selectedDate != null
                          ? 'Selected Date: ${DateFormat('dd/MM/yyyy').format(selectedDate!)}'
                          : 'Select Date',
                      style: TextStyle(color: AppColors.whiteColor),
                    ),
                    style: _buttonStyle(),
                  ),
                ),
                _buildSectionCard(
                  child: ElevatedButton.icon(
                    onPressed: () => _saveFormData(goBack: true),
                    icon: Icon(Icons.save, color: AppColors.whiteColor),
                    label: Text(
                      "Save and Go Back",
                      style: TextStyle(color: AppColors.whiteColor),
                    ),
                    style: _buttonStyle(),
                  ),
                ),
                if (currentPdfPath != null)
                  _buildSectionCard(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        if (await File(currentPdfPath!).exists()) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PDFViewerScreen(pdfPath: currentPdfPath!),
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('PDF file not found')),
                          );
                        }
                      },
                      icon: Icon(Icons.picture_as_pdf, color: AppColors.whiteColor),
                      label: Text("View Saved PDF", style: TextStyle(color: AppColors.whiteColor)),
                      style: _buttonStyle(),
                    ),
                  ),
                SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _generatePDF,
                    icon: Icon(Icons.picture_as_pdf, color: AppColors.whiteColor),
                    label: Text("Generate PDF And Save", style: TextStyle(color: AppColors.whiteColor)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryColor,
                      padding: EdgeInsets.symmetric(vertical: 18),
                      textStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    
  }

  List<Widget> _buildItemRows() {
    List<Widget> itemRows = [];
    for (int i = 0; i < itemDescriptionControllers.length; i++) {
      itemRows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6.0),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: itemDescriptionControllers[i],
                  decoration: InputDecoration(
                    labelText: 'Item Description',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value!.isEmpty ? 'Please enter item description' : null,
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: amountControllers[i],
                  decoration: InputDecoration(
                    labelText: 'Amount',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter amount';
                    }
                    final number = double.tryParse(value);
                    if (number == null || number <= 0) {
                      return 'Please enter a valid positive amount';
                    }
                    return null;
                  },
                ),
              ),
              SizedBox(width: 10),
              IconButton(
                icon: Icon(Icons.remove_circle, color: Colors.red),
                onPressed: itemDescriptionControllers.length > 1
                    ? () => _removeItemRow(i)
                    : null,
              ),
            ],
          ),
        ),
      );
    }
    return itemRows;
  }

  InputDecoration _inputDecoration(String label, {IconData? icon}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: icon != null ? Icon(icon, color: AppColors.primaryColor) : null,
      labelStyle: TextStyle(color: AppColors.secondaryColor),
      filled: true,
      fillColor: Colors.white,
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.dividerColor),
        borderRadius: BorderRadius.circular(16),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.primaryColor, width: 2),
        borderRadius: BorderRadius.circular(16),
      ),
      errorBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.red, width: 1),
        borderRadius: BorderRadius.circular(16),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.red, width: 2),
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }

  Widget _buildSectionCard({required Widget child}) {
    return Card(
      margin: EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 3,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: child,
      ),
    );
  }

  ButtonStyle _buttonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: AppColors.primaryColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: EdgeInsets.symmetric(vertical: 12, horizontal: 20),
      textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
    );
  }

  Future<Uint8List> loadImage(String path,BuildContext context) async {
    final byteData = await DefaultAssetBundle.of(context).load(path);
    return byteData.buffer.asUint8List();
  }
}