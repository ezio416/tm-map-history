const string DOWNLOADED_FOLDER = IO::FromUserGameFolder("Maps/Downloaded").Replace("\\", "/");

bool       downloadingMap = false;
bool       gettingMapInfo = false;
bool       loadingMap     = false;
Map@[]     maps;
dictionary mapsByUid;

enum MapSource {
    Unknown = -1,
    Plugin,
    Cache,
    Autosave
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
    string    authorId;
    string    id;
    int64     lastPlayed  = 0;
    string    nameColored;
    string    nameRaw;
    string    nameStripped;
    int       ordinal     = -1;  // legacy from json
    MapSource source      = MapSource::Unknown;
    int       tmxId       = -1;
    MapType   type        = MapType::Unknown;
    string    uid;

    string get_downloadUrl() {
        return "https://core.trackmania.nadeo.live/maps/" + id + "/file";
    }

    string get_thumbnailUrl() {
        return "https://core.trackmania.nadeo.live/maps/" + id + "/thumbnail.jpg";
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

    void Download() {
        startnew(CoroutineFunc(DownloadAsync));
    }

    void DownloadAsync() {
        if (id.Length == 0) {
            GetInfoAsync();

            if (id.Length == 0) {
                warn("can't download " + StrWrap(uid));
                return;
            }
        }

        if (downloadingMap) {
            return;
        }

        downloadingMap = true;

        trace("downloading map file for " + StrWrap(uid));

        Net::HttpRequest@ req = Net::HttpGet(downloadUrl);
        while (!req.Finished()) {
            yield();
        }

        const string newPath = GetDownloadedFilePath();

        trace("saving new map file to " + newPath);

        try {
            req.SaveToFile(newPath);
        } catch {
            error("failed saving " + StrWrap(uid) + ": " + getExceptionInfo());
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
                warn("can't load " + StrWrap(uid));
                return;
            }
        }

        if (loadingMap) {
            return;
        }

        loadingMap = true;

        trace("loading map " + StrWrap(uid) + " for editing");

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

        trace("getting info for " + StrWrap(uid));

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
            error("bad response for " + StrWrap(uid) + " (" + code + "): " + req.String());
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

            trace("got info for " + StrWrap(uid));

        } catch {
            error("bad json for " + StrWrap(uid) + ": " + req.String());
        }

        GetTmxIdAsync();

        gettingMapInfo = false;
    }

    private void GetTmxIdAsync() {
        trace("getting TMX info for " + StrWrap(uid));

        const uint64 start = Time::Now;

        Net::HttpRequest@ req = Net::HttpGet(
            "https://trackmania.exchange/api/maps?fields=MapId&uid=" + uid
        );

        while (!req.Finished()) {
            yield();

            if (Time::Now - start > 5000) {
                warn("timed out getting TMX info for " + StrWrap(uid));
                req.Cancel();
                return;
            }
        }

        const int code = req.ResponseCode();
        if (code != 200) {
            error("bad response (TMX) for " + StrWrap(uid) + " (" + code + "): " + req.String());
            return;
        }

        try {
            tmxId = int(req.Json()["Results"][0]["MapId"]);
            trace("got TMX info for " + StrWrap(uid));
        } catch {
            error("bad json (TMX) for " + StrWrap(uid) + ": " + req.String());
        }
    }

    void OpenTmio() {
        trace("opening Trackmania.io page for " + StrWrap(uid));
        OpenBrowserURL("https://trackmania.io/#/leaderboard/" + uid);
    }

    void OpenTmx() {
        if (tmxId > -1) {
            trace("opening Trackmania.exchange page for " + StrWrap(uid));
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
                warn("can't load " + StrWrap(uid));
                return;
            }
        }

        if (loadingMap) {
            return;
        }

        loadingMap = true;

        trace("loading map " + StrWrap(uid) + " for playing");

        ReturnToMenu();

        auto App = cast<CTrackMania>(GetApp());
        App.ManiaTitleControlScriptAPI.PlayMap(
            downloadUrl,
            "TrackMania/TM_PlayMap_Local",
            ""
        );

        sleep(5000);

        loadingMap = false;
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
            + StrWrap(uid) + ","
            + StrWrap(nameRaw.Replace("'", "''")) + ","
            + ordinal + ","
            + int(source) + ","
            + tmxId + ","
            + int(type)
        + ")";
    }
}
