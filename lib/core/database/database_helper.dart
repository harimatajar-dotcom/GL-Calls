import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'glcalls.db');

    return await openDatabase(
      path,
      version: 3,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Call logs table
    await db.execute('''
      CREATE TABLE call_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        number TEXT NOT NULL,
        formatted_number TEXT,
        call_type TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        duration INTEGER NOT NULL,
        cached_name TEXT,
        synced INTEGER DEFAULT 0,
        UNIQUE(number, timestamp)
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_call_logs_timestamp ON call_logs(timestamp DESC)
    ''');

    await db.execute('''
      CREATE INDEX idx_call_logs_call_type ON call_logs(call_type)
    ''');

    // Recordings table
    await _createRecordingsTable(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createRecordingsTable(db);
    }
    if (oldVersion < 3) {
      // Add upload tracking columns to recordings table
      await db.execute('ALTER TABLE recordings ADD COLUMN is_uploaded INTEGER DEFAULT 0');
      await db.execute('ALTER TABLE recordings ADD COLUMN upload_url TEXT');
      await db.execute('ALTER TABLE recordings ADD COLUMN s3_path TEXT');
      await db.execute('ALTER TABLE recordings ADD COLUMN uploaded_at INTEGER');
    }
  }

  Future<void> _createRecordingsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS recordings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        file_name TEXT NOT NULL,
        file_path TEXT NOT NULL,
        local_path TEXT,
        phone_number TEXT,
        contact_name TEXT,
        duration INTEGER NOT NULL DEFAULT 0,
        file_size INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        synced_at INTEGER,
        is_synced INTEGER DEFAULT 0,
        is_uploaded INTEGER DEFAULT 0,
        upload_url TEXT,
        s3_path TEXT,
        uploaded_at INTEGER,
        UNIQUE(file_path)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_recordings_created_at ON recordings(created_at DESC)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_recordings_phone_number ON recordings(phone_number)
    ''');
  }

  Future<void> close() async {
    final db = await database;
    db.close();
    _database = null;
  }
}

final databaseHelper = DatabaseHelper();
