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

    [Setting hidden]
    bool S_Migrated = false;

    bool loadingReplays = false;
    bool locked         = false;

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
            trace("added map " + map.uidWrapped);

        } catch {
            error("Database::Add(): uid " + map.uidWrapped + " failed: " + getExceptionInfo());
        }
    }

    void AddMany(Map@[]@ maps) {
        if (false
            or maps is null
            or maps.IsEmpty()
        ) {
            warn("no maps to add");
            return;
        }

        auto db = Lock();
        uint64 lastYield = Time::Now;

        for (uint i = 0; i < maps.Length; i++) {  // TODO optimize
            Add(db, maps[i]);

            if (Time::Now - lastYield > 50) {
                trace("added " + (i + 1) + " maps");
                lastYield = Time::Now;
                yield();
            }
        }

        trace("added " + maps.Length + " maps");
    }

    void Clear() {
        try {
            Lock().Execute("DELETE FROM " + TABLE);
            maps = {};
            mapsByUid.DeleteAll();
        } catch {
            error("Database::Clear(): " + getExceptionInfo());
        }
    }

    void Load() {
        trace("loading maps");

        maps = {};
        mapsByUid.DeleteAll();

        SQLite::Statement@ s;
        try {
            @s = Lock().Prepare("SELECT * FROM " + TABLE);
        } catch {
            error("Database::Load(): " + getExceptionInfo());
            return;
        }

        while (s.NextRow()) {
            auto map = Map(s);
            maps.InsertLast(@map);
            mapsByUid.Set(map.uid, @map);
        }

        if (!maps.IsEmpty()) {
            trace("loaded " + maps.Length + " maps");
        } else {
            warn("no maps to load");
        }
    }

    void LoadFromReplaysAsync() {
        if (loadingReplays) {
            return;
        }

        loadingReplays = true;

        trace("loading maps from replays");

        auto App = cast<CTrackMania>(GetApp());

        int64 tzOffset = 0;
        string[]@ offsetParts = App.SystemPlatform.CurrentTimezoneTimeOffset.Split(":");
        if (offsetParts.Length == 2) {
            int64 hours = 0;
            if (!Text::TryParseInt64(offsetParts[0], hours)) {
                error("failed parsing timezone offset hours: " + offsetParts[0]);
                loadingReplays = false;
                return;
            }

            int64 minutes = 0;
            if (!Text::TryParseInt64(offsetParts[1], minutes)) {
                error("failed parsing timezone offset minutes: " + offsetParts[0]);
                loadingReplays = false;
                return;
            }

            tzOffset = Math::Abs(hours) * 3600 + minutes * 60;
            if (hours < 0) {
                tzOffset *= -1;
            }
        }

        uint         found = 0;
        const string login = App.LocalPlayerInfo.Login;
        Map@[]       needsInfo;
        dictionary   needsInfoByUid;

        for (uint i = 0; i < App.ReplayRecordInfos.Length; i++) {
            CGameCtnReplayRecordInfo@ Replay = App.ReplayRecordInfos[i];
            if (false
                or Replay is null
                or Replay.Fid is null
                or Replay.MapUid.Length == 0
                or Replay.PlayerLogin != login
            ) {
                continue;
            }

            found++;

            Map@ map;
            mapsByUid.Get(Replay.MapUid, @map);
            if (map is null) {
                @map = Map(Replay.MapUid);
                map.source = MapSource::Replay;
            }

            const int64 timeWrite = Time::ParseFormatString("%d/%m/%Y %H:%M", Replay.Fid.TimeWrite) - tzOffset;
            if (timeWrite > map.lastPlayed) {
                map.lastPlayed = timeWrite;
                map.ordinal = -1;
            }

            needsInfo.InsertLast(@map);
            needsInfoByUid.Set(map.uid, @map);
        }

        trace("found " + found + " valid replays");

        GetInfosAsync(needsInfoByUid);
        AddMany(needsInfo);
        Load();

        loadingReplays = false;
    }

    void MigrateFromJsonAsync() {
        if (false
            or S_Migrated
            or !IO::FileExists(FILE_OLD)
        ) {
            S_Migrated = true;
            return;
        }

        Json::Value@ json;
        try {
            @json = Json::FromFile(FILE_OLD);
        } catch {
            error("Database::MigrateFromJson(): " + getExceptionInfo());
            S_Migrated = true;
            return;
        }

        if (false
            or json.GetType() != Json::Type::Object
            or json.Length == 0
        ) {
            warn("no maps to migrate");

            try {
                IO::Move(FILE_OLD, FILE_OLD_BAD);
            } catch {
                error("Database::MigrateFromJson(): " + getExceptionInfo());
            }

            S_Migrated = true;
            return;
        }

        Map@[] toMigrate;
        dictionary toMigrateByUid;

        for (uint i = 0; i < json.Length; i++) {
            try {
                auto map = Map(json[tostring(i)]);
                map.ordinal = i;
                map.source = MapSource::Plugin;
                toMigrate.InsertLast(@map);
                toMigrateByUid.Set(map.uid, @map);
            } catch {
                error("Database::MigrateFromJson(): " + getExceptionInfo());
            }
        }

        GetInfosAsync(toMigrateByUid);
        AddMany(toMigrate);

        S_Migrated = true;
    }

    void Remove(const string&in uid) {
        trace("removing " + StrWrap(uid));

        try {
            Lock().Execute("DELETE FROM " + TABLE + " WHERE mapUid = " + StrWrap(uid));
            Map@ map;
            mapsByUid.Get(uid, @map);
            if (map !is null) {
                mapsByUid.Delete(uid);
                const int index = maps.FindByRef(map);
                if (index > -1) {
                    maps.RemoveAt(index);
                }
            }

        } catch {
            error("Database::Remove(" + StrWrap(uid) + "): " + getExceptionInfo());
        }
    }
}
