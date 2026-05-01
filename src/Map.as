const string DOWNLOADED_FOLDER = IO::FromUserGameFolder("Maps/Downloaded").Replace("\\", "/");

bool       downloadingMap   = false;
bool       gettingMapInfo   = false;
bool       gettingThumbnail = false;
bool       loadingMap       = false;
Map@[]     maps;
dictionary mapsByUid;

enum MapSource {
    Unknown = -1,
    Plugin,
    Cache,
    Replay
}

enum MapType {
    Unknown = -1,
    Race,
    RaceClones,
    Stunt,
    Platform,
    Royal
}

class Map {
    string       authorId;
    bool         favorite    = false;
    string       id;
    int64        lastPlayed  = 0;
    string       nameColored;
    string       nameRaw;
    string       nameStripped;
    int          ordinal     = -1;  // legacy from json
    MapSource    source      = MapSource::Unknown;
    int          tmxId       = -1;
    MapType      type        = MapType::Unknown;
    string       uid;

    string get_downloadUrl() {
        return "https://core.trackmania.nadeo.live/maps/" + id + "/file";
    }

    string get_thumbnailPath() {
        return IO::FromStorageFolder(uid + ".jpg");
    }

    string get_thumbnailUrl() {
        return "https://core.trackmania.nadeo.live/maps/" + id + "/thumbnail.jpg";
    }

    private UI::Texture@ _thumbnail;
    UI::Texture@ get_thumbnail() {
        if (_thumbnail !is null) {
            return _thumbnail;
        }

        LoadThumbnail();
        return null;
    }

    string get_uidWrapped() {
        return StrWrap(uid);
    }

    Map(const string&in uid) {
        this.uid = uid;
    }

    Map(CGameCtnChallenge@ map) {
        nameRaw      = map.MapName;
        nameColored  = Text::OpenplanetFormatCodes(nameRaw);
        nameStripped = Text::StripFormatCodes(nameRaw);
        uid          = map.EdChallengeId;
    }

    Map(SQLite::Statement@ s) {
        authorId     = s.GetColumnString("authorId");
        lastPlayed   = s.GetColumnInt64("lastPlayed");
        id           = s.GetColumnString("mapId");
        uid          = s.GetColumnString("mapUid");
        nameRaw      = s.GetColumnString("nameRaw");
        nameColored  = Text::OpenplanetFormatCodes(nameRaw);
        nameStripped = Text::StripFormatCodes(nameRaw);
        ordinal      = s.GetColumnInt("ordinal");
        source       = MapSource(s.GetColumnInt("source"));
        tmxId        = s.GetColumnInt("tmxId");
        type         = MapType(s.GetColumnInt("type"));
    }

    Map(Json::Value@ json) {  // only for migration
        const auto url = string(json["downloadUrl"]);
        if (url.Length > 0) {
            id = url.Split("/maps/")[1].Split("/")[0];
        }
        nameRaw = string(json["nameRaw"]);
        uid = string(json["uid"]);
    }

    void AddToFavorites() {
        startnew(CoroutineFunc(AddToFavoritesAsync));
    }

    void AddToFavoritesAsync() {
        trace("adding favorite " + uidWrapped);

        const string audience = "NadeoLiveServices";
        NadeoServices::AddAudience(audience);
        while (!NadeoServices::IsAuthenticated(audience)) {
            yield();
        }

        sleep(500);
        Net::HttpRequest@ req = NadeoServices::Post(
            audience,
            NadeoServices::BaseURLLive() + "/api/token/map/favorite/" + uid + "/add"
        );
        req.Start();
        while (!req.Finished()) {
            yield();
        }

        const int code = req.ResponseCode();
        if (code != 204) {
            error("bad response adding favorite " + uidWrapped + " (" + code + "): " + req.String());
            return;
        }

        trace("added favorite " + uidWrapped);
        favorite = true;
    }

    void Download() {
        startnew(CoroutineFunc(DownloadAsync));
    }

    void DownloadAsync() {
        if (id.Length == 0) {
            GetInfoAsync();

            if (id.Length == 0) {
                warn("can't download " + uidWrapped);
                return;
            }
        }

        if (downloadingMap) {
            return;
        }

        downloadingMap = true;

        trace("downloading map file for " + uidWrapped);

        Net::HttpRequest@ req = Net::HttpGet(downloadUrl);
        while (!req.Finished()) {
            yield();
        }

        const string newPath = GetDownloadedFilePath();

        trace("saving new map file to " + newPath);

        try {
            req.SaveToFile(newPath);
        } catch {
            error("failed saving " + uidWrapped + ": " + getExceptionInfo());
        }

        downloadingMap = false;
    }

    void Edit() {
        startnew(CoroutineFunc(EditAsync));
    }

    void EditAsync() {
        if (!Permissions::OpenAdvancedMapEditor()) {
            warn("user doesn't have permission to use the advanced editor");
            return;
        }

        if (id.Length == 0) {
            GetInfoAsync();

            if (id.Length == 0) {
                warn("can't load " + uidWrapped);
                return;
            }
        }

        if (loadingMap) {
            return;
        }

        loadingMap = true;

        trace("loading map " + uidWrapped + " for editing");

        ReturnToMenu();

        auto App = cast<CTrackMania>(GetApp());
        App.ManiaTitleControlScriptAPI.EditMap(downloadUrl, "", "");

        sleep(5000);

        loadingMap = false;
    }

    private string GetDownloadedFilePath() {
        string newName = Path::Join(DOWNLOADED_FOLDER, nameStripped);
        string newPath;

        for (uint i = 1;; i++) {
            newPath = newName + ".Map.Gbx";

            if (!IO::FileExists(newPath)) {
                break;
            }

            trace("file exists: " + newPath);
            newName = newName.Replace(" (" + (i - 1) + ")", "") + " (" + i + ")";
        }

        return newPath;
    }

    void GetInfo() {
        startnew(CoroutineFunc(GetInfoAsync));
    }

    void GetInfoAsync() {
        if (gettingMapInfo) {
            return;
        }

        gettingMapInfo = true;

        trace("getting info for " + uidWrapped);

        const string audience = "NadeoServices";
        NadeoServices::AddAudience(audience);
        while (!NadeoServices::IsAuthenticated(audience)) {
            yield();
        }

        sleep(500);
        Net::HttpRequest@ req = NadeoServices::Get(
            audience,
            NadeoServices::BaseURLCore() + "/maps/by-uid/?mapUidList=" + uid
        );
        req.Start();
        while (!req.Finished()) {
            yield();
        }

        const int code = req.ResponseCode();
        if (code != 200) {
            error("bad response for " + uidWrapped + " (" + code + "): " + req.String());
            gettingMapInfo = false;
            return;
        }

        try {
            Json::Value@ json = req.Json();

            authorId = string(json[0]["author"]);
            id = string(json[0]["mapId"]);
            nameRaw = string(json[0]["name"]);
            nameColored = Text::OpenplanetFormatCodes(nameRaw);
            nameStripped = Text::StripFormatCodes(nameRaw);

            const string mapType = string(json[0]["mapType"]);
            if (mapType.EndsWith("TM_Race")) {
                type = bool(json[0]["hasClones"])
                    ? MapType::RaceClones
                    : MapType::Race
                ;
            } else if (mapType.EndsWith("TM_Platform")) {
                type = MapType::Platform;
            } else if (mapType.EndsWith("TM_Royal")) {
                type = MapType::Royal;
            } else if (mapType.EndsWith("TM_Stunt")) {
                type = MapType::Stunt;
            }

            trace("got info for " + uidWrapped);

        } catch {
            error("bad json for " + uidWrapped + ": " + req.String());
        }

        GetTmxIdAsync();

        gettingMapInfo = false;
    }

    void GetThumbnailAsync() {
        if (gettingThumbnail) {
            return;
        }

        gettingThumbnail = true;

        trace("getting thumbnail for " + uidWrapped);

        Net::HttpRequest@ req = Net::HttpGet(thumbnailUrl);
        while (!req.Finished()) {
            yield();
        }

        if (req.ResponseCode() == 200) {
            req.SaveToFile(thumbnailPath);
        } else {
            error("getting thumbnail failed: " + uidWrapped);
            sleep(60000);
        }

        yield();

        gettingThumbnail = false;
    }

    private void GetTmxIdAsync() {
        trace("getting TMX info for " + uidWrapped);

        const uint64 start = Time::Now;

        Net::HttpRequest@ req = Net::HttpGet(
            "https://trackmania.exchange/api/maps?fields=MapId&uid=" + uid
        );

        while (!req.Finished()) {
            yield();

            if (Time::Now - start > 5000) {
                warn("timed out getting TMX info for " + uidWrapped);
                req.Cancel();
                return;
            }
        }

        const int code = req.ResponseCode();
        if (code != 200) {
            error("bad response (TMX) for " + uidWrapped + " (" + code + "): " + req.String());
            return;
        }

        try {
            tmxId = int(req.Json()["Results"][0]["MapId"]);
            trace("got TMX info for " + uidWrapped);
        } catch {
            error("bad json (TMX) for " + uidWrapped + ": " + req.String());
        }
    }

    void LoadThumbnail() {
        if (_thumbnail !is null) {
            return;
        }

        if (IO::FileExists(thumbnailPath)) {
            try {
                IO::File file(thumbnailPath, IO::FileMode::Read);
                @_thumbnail = UI::LoadTexture(file.Read(file.Size()));
            } catch {
                error("loading thumbnail for " + uidWrapped + " failed: " + getExceptionInfo());
                try {
                    IO::Delete(thumbnailPath);
                } catch {
                    error("deleting thumbnail for " + uidWrapped + " failed:" + getExceptionInfo());
                }
            }
        } else {
            startnew(CoroutineFunc(GetThumbnailAsync));
        }
    }

    void OpenTmio() {
        trace("opening Trackmania.io page for " + uidWrapped);
        OpenBrowserURL("https://trackmania.io/#/leaderboard/" + uid);
    }

    void OpenTmx() {
        if (tmxId > -1) {
            trace("opening Trackmania.exchange page for " + uidWrapped);
            OpenBrowserURL("https://trackmania.exchange/mapshow/" + tmxId);
        }
    }

    void Play() {
        startnew(CoroutineFunc(PlayAsync));
    }

    void PlayAsync() {
        if (!Permissions::PlayLocalMap()) {
            warn("user doesn't have permission to play local maps");
            return;
        }

        if (id.Length == 0) {
            GetInfoAsync();

            if (id.Length == 0) {
                warn("can't load " + uidWrapped);
                return;
            }
        }

        if (loadingMap) {
            return;
        }

        loadingMap = true;

        trace("loading map " + uidWrapped + " for playing");

        ReturnToMenu();

        string mode = "TrackMania/TM_PlayMap_Local";
        switch (type) {
            case MapType::Stunt:
                mode = "TrackMania/TM_StuntSolo_Local";
                break;
            case MapType::Platform:
                mode = "TrackMania/TM_Platform_Local";
                break;
            case MapType::Royal:
                mode = "TrackMania/TM_RoyalTimeAttack_Local";
        }

        auto App = cast<CTrackMania>(GetApp());
        App.ManiaTitleControlScriptAPI.PlayMap(downloadUrl, mode, "");

        sleep(5000);

        loadingMap = false;
    }

    void RemoveFromFavorites() {
        startnew(CoroutineFunc(RemoveFromFavoritesAsync));
    }

    void RemoveFromFavoritesAsync() {
        trace("removing favorite " + uidWrapped);

        const string audience = "NadeoLiveServices";
        NadeoServices::AddAudience(audience);
        while (!NadeoServices::IsAuthenticated(audience)) {
            yield();
        }

        sleep(500);
        Net::HttpRequest@ req = NadeoServices::Post(
            audience,
            NadeoServices::BaseURLLive() + "/api/token/map/favorite/" + uid + "/remove"
        );
        req.Start();
        while (!req.Finished()) {
            yield();
        }

        const int code = req.ResponseCode();
        if (code != 204) {
            error("bad response removing favorite " + uidWrapped + " (" + code + "): " + req.String());
            return;
        }

        trace("removed favorite " + uidWrapped);
        favorite = false;
    }

    private void ReturnToMenu() {
        auto App = cast<CTrackMania>(GetApp());

        if (App.Network.PlaygroundClientScriptAPI.IsInGameMenuDisplayed) {
            App.Network.PlaygroundInterfaceScriptHandler.CloseInGameMenu(
                CGameScriptHandlerPlaygroundInterface::EInGameMenuResult::Quit
            );
        }

        App.BackToMainMenu();

        while (!App.ManiaTitleControlScriptAPI.IsReady) {
            yield();
        }
    }

    string ToQuery() {
        return "("
            + StrWrap(authorId) + ","
            + lastPlayed + ","
            + StrWrap(id) + ","
            + uidWrapped + ","
            + StrWrap(nameRaw.Replace("'", "''")) + ","
            + ordinal + ","
            + int(source) + ","
            + tmxId + ","
            + int(type)
        + ")";
    }
}

void GetFavoritesAsync() {
    if (maps.IsEmpty()) {
        warn("can't get favorites, no maps in history");
        return;
    }

    const string audience = "NadeoLiveServices";
    NadeoServices::AddAudience(audience);
    while (!NadeoServices::IsAuthenticated(audience)) {
        yield();
    }

    uint count = 0;
    uint found = 0;
    uint offset = 0;

    do {
        trace("getting favorites with offset " + offset);

        sleep(500);
        Net::HttpRequest@ req = NadeoServices::Get(
            audience,
            NadeoServices::BaseURLLive() + "/api/token/map/favorite?length=1000&offset=" + offset
        );
        req.Start();
        while (!req.Finished()) {
            yield();
        }

        const int code = req.ResponseCode();
        if (code != 200) {
            error("bad response getting favorites (" + code + "): " + req.String());
            return;
        }

        try {
            Json::Value@ json = req.Json();

            count = uint(json["itemCount"]);

            Json::Value@ list = json["mapList"];
            for (uint i = 0; i < list.Length; i++) {
                Map@ map;
                mapsByUid.Get(list[i]["uid"], @map);
                if (map !is null) {
                    map.favorite = true;
                    found++;
                }
            }

        } catch {
            error("bad json for favorites: " + req.String());
        }

        offset += 1000;

    } while (offset < count);

    trace("got " + count + " favorites, " + found + " of which are in the history");
}

void GetInfosAsync(dictionary@ needsInfo) {
    if (false
        or needsInfo is null
        or needsInfo.IsEmpty()
    ) {
        warn("no maps to get info for");
        return;
    }

    trace("getting info for " + needsInfo.GetSize() + " maps");

    const string audience = "NadeoServices";
    NadeoServices::AddAudience(audience);
    while (!NadeoServices::IsAuthenticated(audience)) {
        yield();
    }

    string[] uids = needsInfo.GetKeys();
    const uint max_uids = 290;
    uint successful = 0;

    while (!uids.IsEmpty()) {
        string[] group;
        const uint group_size = Math::Min(uids.Length, max_uids);
        for (uint i = 0; i < group_size; i++) {
            group.InsertLast(uids[0]);
            uids.RemoveAt(0);
        }
        trace("maps this group: " + group.Length);

        sleep(500);
        Net::HttpRequest@ req = NadeoServices::Get(
            audience,
            NadeoServices::BaseURLCore() + "/maps/by-uid/?mapUidList=" + Text::Join(group, ",")
        );
        req.Start();
        while (!req.Finished()) {
            yield();
        }

        const int code = req.ResponseCode();
        if (code != 200) {
            error("bad response for group (" + code + "): " + req.String());
            continue;
        }

        try {
            Json::Value@ json = req.Json();
            if (json.GetType() != Json::Type::Array) {
                warn("bad json for group: " + req.String());
                continue;
            }

            trace("request returned info for " + json.Length + " maps");

            for (uint i = 0; i < json.Length; i++) {
                const string uid = string(json[i]["mapUid"]);
                Map@ map;
                needsInfo.Get(uid, @map);
                if (map is null) {
                    warn("map doesn't exist: " + StrWrap(uid));
                    continue;
                }

                map.authorId = string(json[i]["author"]);
                map.id = string(json[i]["mapId"]);
                map.nameRaw = string(json[i]["name"]);

                const string type = string(json[i]["mapType"]);
                if (type.EndsWith("TM_Race")) {
                    map.type = bool(json[i]["hasClones"])
                        ? MapType::RaceClones
                        : MapType::Race
                    ;
                } else if (type.EndsWith("TM_Platform")) {
                    map.type = MapType::Platform;
                } else if (type.EndsWith("TM_Royal")) {
                    map.type = MapType::Royal;
                } else if (type.EndsWith("TM_Stunt")) {
                    map.type = MapType::Stunt;
                }

                successful++;
            }

        } catch {
            error("bad json for group: " + req.String());
        }
    }

    trace("got info for " + successful + "/" + needsInfo.GetSize() + " maps");
}
