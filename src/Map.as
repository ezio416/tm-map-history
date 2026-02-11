bool downloadingMap = false;
bool gettingMapInfo = false;
bool loadingMap     = false;

class Map {
    string cachePath;
    string downloadUrl;
    string nameColored;
    string nameQuoted;
    string nameRaw;
    string nameStripped;
    string uid;

    Map() { }

    Map(Json::Value@ map) {
        cachePath    = map["cachePath"];
        downloadUrl  = map["downloadUrl"];
        nameRaw      = map["nameRaw"];
        nameColored  = Text::OpenplanetFormatCodes(nameRaw);
        nameStripped = Text::StripFormatCodes(nameRaw);
        nameQuoted   = '"' + nameStripped + '"';
        uid          = map["uid"];
    }

    Map(CGameCtnChallenge@ challenge) {
        CSystemFidFile@ File = GetFidFromNod(challenge);
        if (File !is null) {
            cachePath = string(File.FullFileName).Replace("\\", "/");
        }

        nameRaw      = challenge.MapName;
        nameColored  = Text::OpenplanetFormatCodes(nameRaw);
        nameStripped = Text::StripFormatCodes(nameRaw);
        nameQuoted   = '"' + nameStripped + '"';
        uid          = challenge.EdChallengeId;
    }

    void CopyFromCache() {
        trace("reading cached map file for " + nameQuoted + " at " + cachePath);

        if (!IO::FileExists(cachePath)) {
            warn("cached map file not found!");
            startnew(CoroutineFunc(DownloadAsync));
            return;
        }

        string newPath = GetDownloadedFilePath();
        trace("saving new map file to " + newPath);
        IO::Copy(cachePath, newPath);
    }

    void DownloadAsync() {
        if (downloadingMap) {
            return;
        }

        downloadingMap = true;

        if (downloadUrl.Length == 0) {
            GetMapInfoAsync();

            gettingMapInfo = false;

            if (downloadUrl.Length == 0) {
                warn("can't download: blank url for " + nameQuoted);
                downloadingMap = false;
                return;
            }
        }

        trace("downloading map file for " + nameQuoted);

        Net::HttpRequest@ req = Net::HttpGet(downloadUrl);
        while (!req.Finished()) {
            yield();
        }

        string newPath = GetDownloadedFilePath();

        trace("saving new map file to " + newPath);

        req.SaveToFile(newPath);

        downloadingMap = false;
    }

    // courtesy of "Play Map" plugin - https://github.com/XertroV/tm-play-map
    void EditAsync() {
        if (!hasEditPermission) {
            warn("user doesn't have permission to use the advanced editor");
            return;
        }

        if (downloadUrl.Length == 0) {
            GetMapInfoAsync();

            gettingMapInfo = false;

            if (downloadUrl.Length == 0) {
                warn("can't edit: blank url for " + nameQuoted);
                return;
            }
        }

        if (loadingMap) {
            return;
        }

        loadingMap = true;

        trace("loading map " + nameQuoted + " for editing");

        ReturnToMenu();

        auto App = cast<CTrackMania>(GetApp());
        App.ManiaTitleControlScriptAPI.EditMap(downloadUrl, "", "");

        sleep(5000);

        loadingMap = false;
    }

    string GetDownloadedFilePath() {
        string newName = downloadedFolder + "/" + nameStripped;
        string newPath;

        uint i = 1;
        while (true) {
            newPath = newName + ".Map.Gbx";

            if (!IO::FileExists(newPath)) {
                break;
            }

            trace("file exists: " + newPath);
            newName = newName.Replace(" (" + (i - 1) + ")", "") + " (" + i++ + ")";
        }

        return newPath;
    }

    void GetMapInfoAsync() {
        if (gettingMapInfo) {
            return;
        }

        gettingMapInfo = true;

        trace("getting map info for " + nameQuoted);

        if (false
            or uid.Length < 24
            or uid.Length > 27
        ) {
            warn("bad uid: " + uid);
            return;
        }

        const string audience = "NadeoServices";
        NadeoServices::AddAudience(audience);
        while (!NadeoServices::IsAuthenticated(audience)) {
            yield();
        }

        Net::HttpRequest@ req = NadeoServices::Get(
            audience,
            NadeoServices::BaseURLCore() + "/maps/by-uid/?mapUidList=" + uid
        );
        req.Start();
        while (!req.Finished()) {
            yield();
        }

        try {
            downloadUrl = req.Json()[0]["fileUrl"];
        } catch {
            error("failed to get map info: " + getExceptionInfo());
            return;
        }

        SaveHistoryFile();
    }

    void OpenTmio() {
        trace("opening Trackmania.io page for " + nameQuoted);
        OpenBrowserURL("https://trackmania.io/#/leaderboard/" + uid);
    }

    // courtesy of "Play Map" plugin - https://github.com/XertroV/tm-play-map
    void PlayAsync() {
        if (!hasPlayPermission) {
            warn("user doesn't have permission to play local maps");
            return;
        }

        if (downloadUrl.Length == 0) {
            GetMapInfoAsync();

            gettingMapInfo = false;

            if (downloadUrl.Length == 0) {
                warn("can't play: blank url for " + nameQuoted);
                return;
            }
        }

        if (loadingMap) {
            return;
        }

        loadingMap = true;

        trace("loading map " + nameQuoted + " for playing");

        if (!Permissions::PlayLocalMap()) {
            warn("Club access required - can't load map " + nameQuoted);
            loadingMap = false;
            return;
        }

        ReturnToMenu();

        auto App = cast<CTrackMania>(GetApp());
        App.ManiaTitleControlScriptAPI.PlayMap(downloadUrl, "TrackMania/TM_PlayMap_Local", "");

        sleep(5000);

        loadingMap = false;
    }

    Json::Value@ ToJson() {
        Json::Value@ map = Json::Object();

        map["cachePath"]   = cachePath;
        map["downloadUrl"] = downloadUrl;
        map["nameRaw"]     = nameRaw;
        map["uid"]         = uid;

        return map;
    }
}
