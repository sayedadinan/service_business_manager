import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('invoices.db');
    return _database!;
  }

  Future<Database> _initDB(String fileName) async {
    final directory = await getApplicationDocumentsDirectory();
    final path = join(directory.path, fileName);
    return await openDatabase(
      path, 
      version: 3, 
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add discount columns if upgrading from version 1
      await db.execute('ALTER TABLE invoices ADD COLUMN isDiscountEnabled INTEGER DEFAULT 0');
      await db.execute('ALTER TABLE invoices ADD COLUMN discountAmount REAL DEFAULT 0.0');
    }
    if (oldVersion < 3) {
      // Update discountPercentage column name to discountAmount if upgrading from version 2
      try {
        await db.execute('ALTER TABLE invoices RENAME COLUMN discountPercentage TO discountAmount');
      } catch (e) {
        // Column might not exist or already renamed, ignore error
        print('Column rename error (likely already correct): $e');
      }
    }
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE invoices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        clientName TEXT,
        totalAmount TEXT,
        advanceAmount TEXT,
        selectedDate TEXT,
        pdfType TEXT,
        isVatEnabled INTEGER,
        isDiscountEnabled INTEGER DEFAULT 0,
        discountAmount REAL DEFAULT 0.0,
        items TEXT,
        pdfPath TEXT
      )
    ''');
  }

  Future<void> insertInvoice(Map<String, dynamic> invoice) async {
    final db = await database;
    await db.insert('invoices', invoice);
  }

  Future<List<Map<String, dynamic>>> getInvoices() async {
    final db = await database;
    return await db.query('invoices');
  }

  Future<void> updateInvoice(int id, Map<String, dynamic> invoice) async {
    final db = await database;
    await db.update('invoices', invoice, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteInvoice(int id, String? pdfPath) async {
    final db = await database;
    await db.delete('invoices', where: 'id = ?', whereArgs: [id]);
    if (pdfPath != null && await File(pdfPath).exists()) {
      await File(pdfPath).delete();
    }
  }
}