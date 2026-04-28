const string  pluginColor = "\\$0AF";
const string  pluginIcon  = Icons::ClockO;
Meta::Plugin@ pluginMeta  = Meta::ExecutingPlugin();
const string  pluginTitle = pluginColor + pluginIcon + "\\$G " + pluginMeta.Name;

void Main() {
    auto App = cast<CTrackMania>(GetApp());

    bool inMap = false;
    bool wasInMap = false;

    while (true) {
        yield();

        inMap = InMap();

        if (wasInMap != inMap) {
            wasInMap = inMap;

            if (inMap) {
                Map@ map;

                mapsByUid.Get(App.RootMap.EdChallengeId, @map);

                if (map is null) {
                    @map = Map(App.RootMap);
                    map.GetInfoAsync();
                    mapsByUid.Set(map.uid, @map);
                    maps.InsertLast(map);
                }

                map.lastPlayed = Time::Stamp;
                map.source = MapSource::Plugin;
                Database::Add(map);
            }
        }
    }
}

void Render() {
    if (false
        or !S_Enabled
        or (true
            and S_HideWithGame
            and !UI::IsGameUIVisible()
        )
        or (true
            and S_HideWithOP
            and !UI::IsOverlayShown()
        )
    ) {
        return;
    }

    if (UI::Begin(pluginTitle + "###main-" + pluginMeta.ID, S_Enabled)) {
        RenderWindow();
    }
    UI::End();
}

void RenderMenu() {
    if (UI::MenuItem(pluginTitle, "", S_Enabled)) {
        S_Enabled = !S_Enabled;
    }
}

void RenderWindow() {
    for (uint i = 0; i < maps.Length; i++) {
        Map@ map = maps[i];
        UI::PushID(map.uid);

        UI::Text(map.uid + (map.id.Length > 0 ? " (" + map.id + ")" : ""));
        UI::SameLine();
        if (UI::Button(Icons::Play)) {
            map.Play();
        }
        UI::SameLine();
        if (UI::Button(Icons::Pencil)) {
            map.Edit();
        }
        UI::SameLine();
        if (UI::Button(Icons::Heartbeat)) {
            map.OpenTmio();
        }
        UI::SameLine();
        if (UI::Button(Icons::Exchange)) {
            map.OpenTmx();
        }
        UI::SameLine();
        if (UI::Button(Icons::Download)) {
            map.Download();
        }

        UI::Text(Time::FormatString("    %F %T", map.lastPlayed));

        UI::PopID();
    }
}
