string ColoredBool(const string&in text, const bool value) {
    return (value ? "\\$0F0" : "\\$F00") + text;
}

bool InMap() {
    auto App = cast<CTrackMania>(GetApp());

    return true
        and App.RootMap !is null
        and App.CurrentPlayground !is null
        and App.Editor is null
    ;
}

string StrWrap(const string&in str, const string&in wrapper = "'") {
    return wrapper + str + wrapper;
}
