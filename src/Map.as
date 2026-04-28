const string DOWNLOADED_FOLDER = IO::FromUserGameFolder("Maps/Downloaded").Replace("\\", "/");

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
    string    cachePath;
    bool      downloading = false;
    bool      gettingInfo = false;
    string    id;
    int64     lastPlayed  = 0;
    bool      loading     = false;
    string    nameColored;
    string    nameRaw;
    string    nameStripped;
    int       ordinal     = -1;
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
        CSystemFidFile@ File = GetFidFromNod(map);
        if (File !is null) {
            cachePath = string(File.FullFileName).Replace("\\", "/");
        }

        nameRaw      = map.MapName;
        nameColored  = Text::OpenplanetFormatCodes(nameRaw);
        nameStripped = Text::StripFormatCodes(nameRaw);
        uid          = map.EdChallengeId;
    }

    // void CopyFromCache() {
    //     trace("reading cached map file for '" + uid + "' at " + cachePath);

    //     if (!IO::FileExists(cachePath)) {
    //         warn("cached map file not found!");
    //         Download();
    //         return;
    //     }

    //     string newPath = GetDownloadedFilePath();
    //     trace("saving new map file to " + newPath);
    //     IO::Copy(cachePath, newPath);
    // }

    void Download() {
        startnew(CoroutineFunc(DownloadAsync));
    }

    void DownloadAsync() {
        if (id.Length == 0) {
            GetInfoAsync();

            if (id.Length == 0) {
                warn("can't download '" + uid + "'");
                return;
            }
        }

        if (downloading) {
            return;
        }

        downloading = true;

        trace("downloading map file for '" + uid + "'");

        Net::HttpRequest@ req = Net::HttpGet(downloadUrl);
        while (!req.Finished()) {
            yield();
        }

        const string newPath = GetDownloadedFilePath();

        trace("saving new map file to " + newPath);

        try {
            req.SaveToFile(newPath);
        } catch {
            error("failed saving '" + uid + "': " + getExceptionInfo());
        }

        downloading = false;
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
                warn("can't load '" + uid + "'");
                return;
            }
        }

        if (loading) {
            return;
        }

        loading = true;

        trace("loading map '" + uid + "' for editing");

        ReturnToMenu();

        auto App = cast<CTrackMania>(GetApp());
        App.ManiaTitleControlScriptAPI.EditMap(downloadUrl, "", "");

        sleep(5000);

        loading = false;
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
        if (gettingInfo) {
            return;
        }

        gettingInfo = true;

        trace("getting info for '" + uid + "'");

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
            error("bad response for '" + uid + "' (" + code + "): " + req.String());
            gettingInfo = false;
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

            trace("got info for '" + uid + "'");

        } catch {
            error("bad json for '" + uid + "': " + req.String());
        }

        GetTmxIdAsync();

        gettingInfo = false;
    }

    private void GetTmxIdAsync() {
        trace("getting TMX info for '" + uid + "'");

        const uint64 start = Time::Now;

        Net::HttpRequest@ req = Net::HttpGet(
            "https://trackmania.exchange/api/maps?fields=MapId&uid=" + uid
        );

        while (!req.Finished()) {
            yield();

            if (Time::Now - start > 5000) {
                warn("timed out getting TMX info for '" + uid + "'");
                req.Cancel();
                return;
            }
        }

        const int code = req.ResponseCode();
        if (code != 200) {
            error("bad response (TMX) for '" + uid + "' (" + code + "): " + req.String());
            return;
        }

        try {
            tmxId = int(req.Json()["Results"][0]["MapId"]);
            trace("got TMX info for '" + uid + "'");
        } catch {
            error("bad json (TMX) for '" + uid + "': " + req.String());
        }
    }

    void OpenTmio() {
        trace("opening Trackmania.io page for '" + uid + "'");
        OpenBrowserURL("https://trackmania.io/#/leaderboard/" + uid);
    }

    void OpenTmx() {
        if (tmxId > -1) {
            trace("opening Trackmania.exchange page for '" + uid + "'");
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
                warn("can't load '" + uid + "'");
                return;
            }
        }

        if (loading) {
            return;
        }

        loading = true;

        trace("loading map '" + uid + "' for playing");

        ReturnToMenu();

        auto App = cast<CTrackMania>(GetApp());
        App.ManiaTitleControlScriptAPI.PlayMap(
            downloadUrl,
            "TrackMania/TM_PlayMap_Local",
            ""
        );

        sleep(5000);

        loading = false;
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

    // string ToQuery() {
    //     return "("
    //         + "'" + authorId + "',"
    //         + "'" + cachePath.Replace("'", "''") + "',"
    //         + lastPlayed + ","
    //         + "'" + id + "',"
    //         + "'" + uid + "',"
    //         + "'" + nameRaw.Replace("'", "''") + "',"
    //         + ordinal
    //     + ")";
    // }
}
