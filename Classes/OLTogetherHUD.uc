class OLTogetherHUD extends OLHUD;

var OLTogetherController TogetherController;

var float ConnectedFlashDuration;
var float ConnectedFlashEndTime;
var bool  bJustConnected;

event PostBeginPlay()
{
    super.PostBeginPlay();
    ConnectedFlashDuration = 3.0;
}

function int CountRemotePlayers()
{
    local int i, Count;
    Count = 0;
    for (i = 0; i < 8; i++)
        if (TogetherController.RemoteID[i] != 0)
            Count++;
    return Count;
}

event DrawHUD()
{
    local OLTogetherLink Link;
    local string         StatusText;
    local float          X, Y;
    local byte           R, G, B;

    super.DrawHUD();

    if (TogetherController == None)
        TogetherController = OLTogetherController(PlayerOwner);
    if (TogetherController == None)
        return;

    Link = TogetherController.NetworkLink;

    // ── Determine status string ───────────────
    if (Link == None)
    {
        StatusText = "OLTogether: Initializing...";
        R = 180; G = 180; B = 180;
        bJustConnected = false;
    }
    else if (Link.bIsResolving)
    {
        StatusText = "OLTogether: Connecting to " $ Link.ServerHost $ ":" $ string(Link.ServerPort) $ "...";
        R = 255; G = 200; B = 0;
        bJustConnected = false;
    }
    else if (!Link.bIsConnected)
    {
        StatusText = "OLTogether: Disconnected";
        R = 255; G = 60; B = 60;
        bJustConnected = false;
        ConnectedFlashEndTime = 0;
    }
    else
    {
        // First frame we notice a connection
        if (!bJustConnected)
        {
            bJustConnected        = true;
            ConnectedFlashEndTime = WorldInfo.TimeSeconds + ConnectedFlashDuration;
        }

        if (WorldInfo.TimeSeconds < ConnectedFlashEndTime)
        {
            StatusText = "OLTogether: Connected!";
            R = 80; G = 255; B = 80;
        }
        else
        {
            StatusText = "OLTogether  [" $ string(CountRemotePlayers()) $ " player(s) online]";
            R = 80; G = 200; B = 80;
        }
    }

    X = 20;
    Y = 20;

    // Drop shadow
    Canvas.SetPos(X + 1, Y + 1);
    Canvas.SetDrawColor(0, 0, 0, 140);
    Canvas.DrawText(StatusText,, 1.0, 1.0);

    // Main text
    Canvas.SetPos(X, Y);
    Canvas.SetDrawColor(R, G, B, 220);
    Canvas.DrawText(StatusText,, 1.0, 1.0);
}

DefaultProperties
{
    ConnectedFlashDuration = 3.0
    bJustConnected         = false
    ConnectedFlashEndTime  = 0.0
}
