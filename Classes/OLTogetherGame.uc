class OLTogetherGame extends OLGame;

static event class<GameInfo> SetGameType(string MapName, string Options, string Portal)
{
    return Default.class;
}

DefaultProperties
{
    PlayerControllerClass = class'Multiplayer.OLTogetherController'
    DefaultPawnClass      = class'Multiplayer.OLTogetherHero'
    HUDType               = class'Multiplayer.OLTogetherHUD'
}