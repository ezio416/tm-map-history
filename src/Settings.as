[Setting category="General" name="Enabled"]
bool S_Enabled = true;

[Setting category="General" name="Show/hide with game UI"]
bool S_HideWithGame = true;

[Setting category="General" name="Show/hide with Openplanet UI"]
bool S_HideWithOP = false;

[SettingsTab name="Debug" icon="Bug"]
void SettingsTab_Debug() {
    const float scale = UI::GetScale();

    UI::Text(ColoredBool("downloadingMap",           downloadingMap));
    UI::SameLine();
    UI::Text(ColoredBool("gettingMapInfo",           gettingMapInfo));
    UI::SameLine();
    UI::Text(ColoredBool("gettingThumbnail",         gettingThumbnail));
    UI::SameLine();
    UI::Text(ColoredBool("loadingMap",               loadingMap));
    UI::SameLine();
    UI::Text(ColoredBool("Database::loadingReplays", Database::loadingReplays));
    UI::SameLine();
    UI::Text(ColoredBool("Database::locked",         Database::locked));

    UI::Separator();

    UI::BeginDisabled(Database::loadingReplays);
    if (UI::Button(Icons::Download + " load from replays")) {
        startnew(Database::LoadFromReplaysAsync);
    }
    UI::EndDisabled();

    UI::Separator();

    UI::Text("maps: " + maps.Length);

    UI::Separator();

    if (UI::BeginChild("##child-debug")) {
        if (UI::BeginTable("##table-debug", 10, UI::TableFlags::RowBg | UI::TableFlags::ScrollY)) {
            UI::PushStyleColor(UI::Col::TableRowBgAlt, rowBgAltColor);

            UI::TableSetupScrollFreeze(0, 1);
            UI::TableSetupColumn("#",                UI::TableColumnFlags::WidthFixed, scale * 50.0f);
            UI::TableSetupColumn("uid",              UI::TableColumnFlags::WidthFixed, scale * 250.0f);
            UI::TableSetupColumn("type",             UI::TableColumnFlags::WidthFixed, scale * 80.0f);
            UI::TableSetupColumn("lastPlayed",       UI::TableColumnFlags::WidthFixed, scale * 85.0f);
            UI::TableSetupColumn("lastPlayed (fmt)", UI::TableColumnFlags::WidthFixed, scale * 135.0f);
            UI::TableSetupColumn("actions",          UI::TableColumnFlags::WidthFixed, scale * 350.0f);
            UI::TableHeadersRow();

            UI::ListClipper clipper(maps.Length);
            while (clipper.Step()) {
                for (int i = clipper.DisplayStart; i < clipper.DisplayEnd; i++) {
                    if (i >= int(maps.Length)) {  // in case of deletion
                        break;
                    }

                    Map@ map = maps[i];
                    UI::PushID(map.uid);

                    UI::TableNextRow();

                    UI::TableNextColumn();
                    UI::AlignTextToFramePadding();
                    UI::Text(Text::Format("%06d", i));

                    UI::TableNextColumn();
                    UI::AlignTextToFramePadding();
                    UI::Text(map.uid);

                    UI::TableNextColumn();
                    UI::AlignTextToFramePadding();
                    UI::Text(tostring(map.type));

                    UI::TableNextColumn();
                    UI::AlignTextToFramePadding();
                    UI::Text(map.lastPlayed > 0 ? tostring(map.lastPlayed) : "");

                    UI::TableNextColumn();
                    UI::AlignTextToFramePadding();
                    UI::Text(map.lastPlayed > 0 ? Time::FormatString("%F %T", map.lastPlayed) : "");

                    UI::TableNextColumn();

                    UI::BeginDisabled(gettingMapInfo);
                    if (UI::Button(Icons::Refresh)) {
                        map.GetInfo();
                    }
                    UI::SetItemTooltip("get info");
                    UI::EndDisabled();

                    UI::SameLine();
                    UI::BeginDisabled(!Permissions::PlayLocalMap());
                    if (UI::Button(Icons::Play)) {
                        map.Play();
                    }
                    UI::SetItemTooltip("play");
                    UI::EndDisabled();

                    UI::SameLine();
                    UI::BeginDisabled(!Permissions::OpenAdvancedMapEditor());
                    if (UI::Button(Icons::Pencil)) {
                        map.Edit();
                    }
                    UI::SetItemTooltip("edit");
                    UI::EndDisabled();

                    UI::SameLine();
                    if (UI::Button(Icons::Download)) {
                        map.Download();
                    }
                    UI::SetItemTooltip("download");

                    UI::SameLine();
                    if (UI::Button(Icons::Heartbeat)) {
                        map.OpenTmio();
                    }
                    UI::SetItemTooltip("trackmania.io");

                    UI::SameLine();
                    UI::BeginDisabled(map.tmxId == -1);
                    if (UI::Button(Icons::Exchange)) {
                        map.OpenTmx();
                    }
                    UI::SetItemTooltip("trackmania.exchange");
                    UI::EndDisabled();

                    UI::SameLine();
                    if (map.favorite) {
                        if (UI::Button(Icons::Heart)) {
                            map.RemoveFromFavorites();
                        }
                        UI::SetItemTooltip("remove from favorites");
                    } else {
                        if (UI::Button(Icons::HeartO)) {
                            map.AddToFavorites();
                        }
                        UI::SetItemTooltip("add to favorites");
                    }

                    UI::SameLine();
                    if (UI::Button(Icons::TrashO)) {
                        Database::Remove(map.uid);
                    }

                    UI::PopID();
                }
            }

            UI::PopStyleColor();
            UI::EndTable();
        }
    }

    UI::EndChild();
}
