const string downloadedFolder  = IO::FromUserGameFolder("Maps/Downloaded").Replace("\\", "/");
bool         hasEditPermission = false;
bool         hasPlayPermission = false;
const string historyFile       = IO::FromStorageFolder("history.json");
Map@[]       maps;
const string title             = Icons::ClockO + " Map History";

void Main() {
    hasEditPermission = Permissions::OpenAdvancedMapEditor();
    hasPlayPermission = Permissions::PlayLocalMap();

    if (true
        and !hasPlayPermission
        and S_NotifyStarter
    ) {
        UI::ShowNotification(
            title,
            "Paid access is required to play maps, but you can still see your history and edit maps.",
            vec4(1.0f, 0.1f, 0.1f, 0.8f)
        );
    }

    auto App = cast<CTrackMania>(GetApp());

    LoadHistoryFile();

    while (true) {
        yield();

        if (App.Editor is null) {
            AddMap(App.RootMap);
        }
    }
}

void RenderMenu() {
    if (UI::BeginMenu(
        title,
        (false
            or S_DownloadedFolder
            or maps.Length > 0
        )
    )) {
        if (S_DownloadedFolder) {
            if (UI::MenuItem(Icons::ExternalLink + " Open \"Downloaded\" Folder")) {
                OpenExplorerPath(downloadedFolder);
            }

            UI::Separator();
        }

        for (int i = maps.Length - 1; i >= 0; i--) {
            Map@ map = maps[i];

            if (S_Simple) {
                if (UI::MenuItem((S_MapNameColor ? map.nameColored : map.nameStripped) + "##" + map.uid)) {
                    map.Play();
                }

                if (true
                    and UI::IsItemHovered()
                    and UI::IsMouseReleased(UI::MouseButton::Right)
                ) {
                    map.Edit();
                }
            } else {
                if (UI::BeginMenu((S_MapNameColor ? map.nameColored : map.nameStripped) + "##" + map.uid)) {
                    if (UI::MenuItem(Icons::Play + " Play")) {
                        UI::BeginDisabled(!hasPlayPermission);
                        map.Play();
                        UI::EndDisabled();
                    }

                    if (UI::MenuItem(Icons::Pencil + " Edit")) {
                        UI::BeginDisabled(!hasEditPermission);
                        map.Edit();
                        UI::EndDisabled();
                    }

                    if (UI::MenuItem(Icons::Download + " Download")) {
                        map.CopyFromCache();
                    }

                    if (UI::MenuItem(Icons::Heartbeat + " Trackmania.io")) {
                        map.OpenTmio();
                    }

                    UI::EndMenu();
                }
            }
        }

        UI::EndMenu();
    }
}

void AddMap(CGameCtnChallenge@ challenge) {
    if (challenge is null) {
        return;
    }

    Map@ map;

    if (maps.Length == 0) {
        @map = Map(challenge);

        maps.InsertLast(map);

        SaveHistoryFile();
        return;
    }

    if (maps[maps.Length - 1].uid == challenge.EdChallengeId) {
        return;
    }

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
            // trace("moving " + movingMap.nameQuoted + " from index " + i + " to " + tostring(i - 1));
            maps[i - 1] = movingMap;
        }

        // trace("moving " + map.nameQuoted + " to end");
        maps[maps.Length - 1] = map;
    } else {
        // trace("adding " + map.nameQuoted);
        maps.InsertLast(map);
    }

    if (maps.Length > S_HistoryMax) {
        // trace("over limit, removing earliest map");
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

// courtesy of "BetterTOTD" plugin - https://github.com/XertroV/tm-better-totd
void ReturnToMenu() {
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

void SaveHistoryFile() {
    trace("saving history.json");

    Json::Value@ jsonMaps = Json::Object();

    for (uint i = 0; i < maps.Length; i++) {
        jsonMaps[tostring(i)] = maps[i].ToJson();
    }

    Json::ToFile(historyFile, jsonMaps, true);
}
