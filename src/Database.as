namespace Database {
    const string COLUMNS      = """(
        authorId    CHAR(36),
        lastPlayed  INT,
        mapId       CHAR(36),
        mapUid      VARCHAR(27) PRIMARY KEY,
        nameRaw     TEXT,
        ordinal     INT,
        source      INT,
        tmxId       INT,
        type        INT
    )""";
    const string COLUMN_NAMES = """(
        authorId,
        lastPlayed,
        mapId,
        mapUid,
        nameRaw,
        ordinal,
        source,
        tmxId,
        type
    )""";
    const string FILE         = IO::FromStorageFolder("history.db");
    const string FILE_OLD     = IO::FromStorageFolder("history.json");
    const string FILE_OLD_BAD = IO::FromStorageFolder("history_bad.json");
    const string TABLE        = "Maps";

    // [Setting hidden]
    // bool S_Migrated = false;

    bool locked = false;

    class Lock {
        private SQLite::Database@ _db;

        Lock() {
            if (locked) {
                throw("database locked");
            }

            @_db = SQLite::Database(FILE);
            _db.Execute("CREATE TABLE IF NOT EXISTS " + TABLE + " " + COLUMNS);
            locked = true;
        }

        ~Lock() {
            @_db = null;
            locked = false;
        }

        void Execute(const string&in query) {
            _db.Execute(query + ";");
        }

        SQLite::Statement@ Prepare(const string&in query) {
            return _db.Prepare(query + ";");
        }
    }

    void Add(Map@ map) {
        Add(Lock(), map);
    }

    void Add(Lock@ db, Map@ map) {
        if (false
            or db is null
            or map is null
        ) {
            warn("db or map null");
            return;
        }

        try {
            db.Execute("REPLACE INTO " + TABLE + " " + COLUMN_NAMES + " VALUES " + map.ToQuery());
            trace("added map " + StrWrap(map.uid));

        } catch {
            error("Database::Add(): uid " + StrWrap(map.uid) + " failed: " + getExceptionInfo());
        }
    }

    void Add(Map@[]@ maps) {
        if (false
            or maps is null
            or maps.Length == 0
        ) {
            warn("no maps to add");
            return;
        }

        auto db = Lock();
        for (uint i = 0; i < maps.Length; i++) {
            Add(db, maps[i]);
        }
    }

    void Clear() {
        try {
            Lock().Execute("DELETE FROM " + TABLE);
        } catch {
            error("Database::Clear(): " + getExceptionInfo());
        }
    }

    // void Load() {
    //     auto db = Lock();

    //     maps = {};

    //     SQLite::Statement@ s;
    //     try {
    //         @s = db.Prepare("SELECT * FROM " + TABLE);
    //     } catch {
    //         error("Database::Load(): " + getExceptionInfo());
    //         return;
    //     }

    //     while (s.NextRow()) {
    //         ;
    //     }
    // }

    // bool MigrateFromJson() {
    //     if (false
    //         or S_Migrated
    //         or !IO::FileExists(FILE_OLD)
    //     ) {
    //         S_Migrated = true;
    //         return false;
    //     }

    //     Json::Value@ json;
    //     try {
    //         @json = Json::FromFile(FILE_OLD);
    //     } catch {
    //         error("Database::MigrateFromJson(): " + getExceptionInfo());
    //         S_Migrated = true;
    //         return false;
    //     }

    //     if (false
    //         or json.GetType() != Json::Type::Object
    //         or json.Length == 0
    //     ) {
    //         warn("no maps to migrate");

    //         try {
    //             IO::Move(FILE_OLD, FILE_OLD_BAD);
    //         } catch {
    //             error("Database::MigrateFromJson(): " + getExceptionInfo());
    //         }

    //         S_Migrated = true;
    //         return false;
    //     }

    //     Map@[] toMigrate;
    //     for (uint i = 0; i < json.Length; i++) {
    //         try {
    //             auto map = Map(json[tostring(i)]);
    //             map.ordinal = i;
    //             toMigrate.InsertLast(map);
    //         } catch {
    //             error("Database::MigrateFromJson(): " + getExceptionInfo());
    //         }
    //     }

    //     Add(toMigrate);

    //     S_Migrated = true;
    //     return true;
    // }

    void Remove(const string&in uid) {
        if (false
            or uid.Length == 0
            or uid.Length > 27
        ) {
            warn("invalid uid to remove: " + uid);
            return;
        }

        try {
            Lock().Execute("DELETE FROM " + TABLE + " WHERE mapUid = " + StrWrap(uid));
        } catch {
            error("Database::Remove(" + StrWrap(uid) + "): " + getExceptionInfo());
        }
    }
}
