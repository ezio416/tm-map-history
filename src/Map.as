// c 2023-12-27
// m 2024-05-24

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
        nameQuoted   = "\"" + nameStripped + "\"";
        uid          = map["uid"];
    }

    Map(CGameCtnChallenge@ challenge) {
        CSystemFidFile@ File = GetFidFromNod(challenge);
        if (File !is null)
            cachePath = string(File.FullFileName).Replace("\\", "/");

        nameRaw      = challenge.MapName;
        nameColored  = Text::OpenplanetFormatCodes(nameRaw);
        nameStripped = Text::StripFormatCodes(nameRaw);
        nameQuoted   = "\"" + nameStripped + "\"";
        uid          = challenge.EdChallengeId;
    }

    // courtesy of "Download Map" plugin - https://github.com/ezio416/tm-download-map
    void CopyFromCache() {
        trace("reading cached map file for " + nameQuoted + " at " + cachePath);

        if (!IO::FileExists(cachePath)) {
            warn("cached map file not found!");
            startnew(CoroutineFunc(DownloadCoro));
            return;
        }

        IO::File oldFile(cachePath);
        oldFile.Open(IO::FileMode::Read);
        MemoryBuffer@ buf = oldFile.Read(oldFile.Size());
        oldFile.Close();

        string newPath = GetDownloadedFilePath();

        trace("saving new map file to " + newPath);

        IO::File newFile(newPath);
        newFile.Open(IO::FileMode::Write);
        newFile.Write(buf);
        newFile.Close();
    }

    void DownloadCoro() {
        if (downloadingMap)
            return;

        downloadingMap = true;

        if (downloadUrl == "") {
            Meta::PluginCoroutine@ urlCoro = startnew(CoroutineFunc(GetMapInfoCoro));
            while (urlCoro.IsRunning())
                yield();

            gettingMapInfo = false;

            if (downloadUrl == "") {
                warn("can't download: blank url for " + nameQuoted);
                downloadingMap = false;
                return;
            }
        }

        trace("downloading map file for " + nameQuoted);

        Net::HttpRequest@ req = Net::HttpGet(downloadUrl);
        while (!req.Finished())
            yield();

        string newPath = GetDownloadedFilePath();

        trace("saving new map file to " + newPath);

        req.SaveToFile(newPath);

        downloadingMap = false;
    }

    // courtesy of "Play Map" plugin - https://github.com/XertroV/tm-play-map
    void EditCoro() {
        if (!hasEditPermission) {
            warn("user doesn't have permission to use the advanced editor");
            return;
        }

        if (downloadUrl == "") {
            Meta::PluginCoroutine@ urlCoro = startnew(CoroutineFunc(GetMapInfoCoro));
            while (urlCoro.IsRunning())
                yield();

            gettingMapInfo = false;

            if (downloadUrl == "") {
                warn("can't edit: blank url for " + nameQuoted);
                return;
            }
        }

        if (loadingMap)
            return;

        loadingMap = true;

        trace("loading map " + nameQuoted + " for editing");

        ReturnToMenu();

        CTrackMania@ App = cast<CTrackMania@>(GetApp());
        App.ManiaTitleControlScriptAPI.EditMap(downloadUrl, "", "");

        const uint64 waitToEditAgain = 5000;
        const uint64 now = Time::Now;
        while (Time::Now - now < waitToEditAgain)
            yield();

        loadingMap = false;
    }

    string GetDownloadedFilePath() {
        string newName = downloadedFolder + "/" + nameStripped;
        string newPath;

        uint i = 1;
        while (true) {
            newPath = newName + ".Map.Gbx";

            if (!IO::FileExists(newPath))
                break;

            trace("file exists: " + newPath);
            newName = newName.Replace(" (" + (i - 1) + ")", "") + " (" + i++ + ")";
        }

        return newPath;
    }

    // courtesy of "BetterTOTD" plugin - https://github.com/XertroV/tm-better-totd
    void GetMapInfoCoro() {
        if (gettingMapInfo)
            return;

        gettingMapInfo = true;

        trace("getting map info for " + nameQuoted);

        if (uid.Length != 26 && uid.Length != 27) {
            warn("bad uid: " + uid);
            return;
        }

        CTrackMania@ App = cast<CTrackMania@>(GetApp());

        CTrackManiaMenus@ Manager = cast<CTrackManiaMenus@>(App.MenuManager);
        if (Manager is null)
            return;

        CGameManiaAppTitle@ Title = Manager.MenuCustom_CurrentManiaApp;
        if (Title is null)
            return;

        CGameUserManagerScript@ UserMgr = Title.UserMgr;
        if (UserMgr is null || UserMgr.Users.Length == 0)
            return;

        CGameUserScript@ User = UserMgr.Users[0];
        if (User is null)
            return;

        CGameDataFileManagerScript@ FileMgr = Title.DataFileMgr;
        if (FileMgr is null)
            return;

        CWebServicesTaskResult_NadeoServicesMapScript@ task = FileMgr.Map_NadeoServices_GetFromUid(User.Id, uid);

        while (task.IsProcessing)
            yield();

        if (task.HasSucceeded) {
            CNadeoServicesMap@ Map = task.Map;
            downloadUrl = Map.FileUrl;

            FileMgr.TaskResult_Release(task.Id);

            SaveHistoryFile();
        }
    }

    void OpenTmio() {
        trace("opening Trackmania.io page for " + nameQuoted);
        OpenBrowserURL("https://trackmania.io/#/leaderboard/" + uid);
    }

    // courtesy of "Play Map" plugin - https://github.com/XertroV/tm-play-map
    void PlayCoro() {
        if (!hasPlayPermission) {
            warn("user doesn't have permission to play local maps");
            return;
        }

        if (downloadUrl == "") {
            Meta::PluginCoroutine@ urlCoro = startnew(CoroutineFunc(GetMapInfoCoro));
            while (urlCoro.IsRunning())
                yield();

            gettingMapInfo = false;

            if (downloadUrl == "") {
                warn("can't play: blank url for " + nameQuoted);
                return;
            }
        }

        if (loadingMap)
            return;

        loadingMap = true;

        trace("loading map " + nameQuoted + " for playing");

        if (!Permissions::PlayLocalMap()) {
            warn("Club access required - can't load map " + nameQuoted);
            loadingMap = false;
            return;
        }

        ReturnToMenu();

        CTrackMania@ App = cast<CTrackMania@>(GetApp());
        App.ManiaTitleControlScriptAPI.PlayMap(downloadUrl, "TrackMania/TM_PlayMap_Local", "");

        const uint64 waitToPlayAgain = 5000;
        const uint64 now = Time::Now;
        while (Time::Now - now < waitToPlayAgain)
            yield();

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
