// c 2023-12-27
// m 2023-12-30

string downloadedFolder = IO::FromUserGameFolder("Maps/Downloaded").Replace("\\", "/");
string historyFile = IO::FromStorageFolder("history.json");
Map@[] maps;
string title = "\\$" + Icons::ClockO + " Map History";

void RenderMenu() {
    if (UI::BeginMenu(title, S_DownloadedFolder || maps.Length > 0)) {
        if (S_DownloadedFolder && UI::MenuItem(Icons::ExternalLink + " Open \"Downloaded\" Folder"))
            OpenExplorerPath(downloadedFolder);

        for (int i = maps.Length - 1; i >= 0; i--) {
            Map@ map = maps[i];

            if (UI::BeginMenu((S_MapNameColor ? map.nameColored : map.nameStripped) + "##" + map.uid)) {
                if (UI::MenuItem(Icons::Play + " Play"))
                    startnew(CoroutineFunc(map.PlayCoro));

                if (UI::MenuItem(Icons::Pencil + " Edit"))
                    startnew(CoroutineFunc(map.EditCoro));

                if (UI::MenuItem(Icons::Download + " Download"))
                    startnew(CoroutineFunc(map.CopyFromCache));

                if (UI::MenuItem(Icons::Heartbeat + " Trackmania.io"))
                    map.OpenTmio();

                UI::EndMenu();
            }
        }

        UI::EndMenu();
    }
}

void Main() {
    CTrackMania@ App = cast<CTrackMania@>(GetApp());

    LoadHistoryFile();

    while (true) {
        if (App.Editor is null)
            AddMap(App.RootMap);

        yield();
    }
}

void AddMap(CGameCtnChallenge@ challenge) {
    if (challenge is null)
        return;

    Map@ map;

    if (maps.Length == 0) {
        @map = Map(challenge);

        maps.InsertLast(map);

        SaveHistoryFile();
        return;
    }

    if (maps[maps.Length - 1].uid == challenge.EdChallengeId)
        return;

    @map = Map(challenge);
    int foundIndex = -1;

    for (uint i = 0; i < maps.Length - 1; i++) {
        if (maps[i].uid == map.uid) {
            foundIndex = i;
            break;
        }
    }

    if (foundIndex > -1) {
        for (uint i = foundIndex + 1; i < maps.Length; i++) {
            Map@ movingMap = maps[i];
            trace("moving " + movingMap.nameQuoted + " from index " + i + " to " + tostring(i - 1));
            maps[i - 1] = movingMap;
        }

        trace("moving " + map.nameQuoted + " to end");
        maps[maps.Length - 1] = map;
    } else {
        trace("adding " + map.nameQuoted);
        maps.InsertLast(map);
    }

    if (maps.Length > historyMax) {
        trace("over limit, removing earliest map");
        maps.RemoveAt(0);
    }

    SaveHistoryFile();
}

void LoadHistoryFile() {
    trace("loading history.json");

    if (!IO::FileExists(historyFile)) {
        warn("history.json not found! you should play some maps");
        return;
    }

    Json::Value@ file = Json::FromFile(historyFile);
    for (uint i = 0; i < file.Length; i++) {
        Json::Value@ jsonMap = file[tostring(i)];
        maps.InsertLast(Map(jsonMap));
    }
}

void SaveHistoryFile() {
    trace("saving history.json");

    Json::Value@ jsonMaps = Json::Object();

    for (uint i = 0; i < maps.Length; i++)
        jsonMaps[tostring(i)] = maps[i].ToJson();

    Json::ToFile(historyFile, jsonMaps);
}

// courtesy of "BetterTOTD" plugin - https://github.com/XertroV/tm-better-totd
void ReturnToMenu() {
    CTrackMania@ App = cast<CTrackMania@>(GetApp());

    if (App.Network.PlaygroundClientScriptAPI.IsInGameMenuDisplayed)
        App.Network.PlaygroundInterfaceScriptHandler.CloseInGameMenu(CGameScriptHandlerPlaygroundInterface::EInGameMenuResult::Quit);

    App.BackToMainMenu();

    while (!App.ManiaTitleControlScriptAPI.IsReady)
        yield();
}
