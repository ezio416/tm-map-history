const string  pluginColor   = "\\$0AF";
const string  pluginIcon    = Icons::ClockO;
Meta::Plugin@ pluginMeta    = Meta::ExecutingPlugin();
const string  pluginTitle   = pluginColor + pluginIcon + "\\$G " + pluginMeta.Name;
const vec4    rowBgAltColor = vec4(vec3(), 0.5f);

void Main() {
    Database::MigrateFromJsonAsync();
    Database::Load();
    GetFavoritesAsync();

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
                    maps.InsertLast(@map);
                    mapsByUid.Set(map.uid, @map);
                } else if (map.lastPlayed > 0) {  // TODO make setting
                    UI::ShowNotification(
                        pluginTitle,
                        Time::FormatString("You last played this map on %F at %T", map.lastPlayed)
                    );
                }

                map.GetInfoAsync();
                map.lastPlayed = Time::Stamp;
                map.ordinal = -1;
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
    ;
}
