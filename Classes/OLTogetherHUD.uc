class OLTogetherHUD extends OLHUD;

// ─────────────────────────────────────────────
//  Notification system
// ─────────────────────────────────────────────
const MAX_NOTIFICATIONS = 5;

var string NotifText   [5];
var float  NotifExpire [5];   // WorldInfo.TimeSeconds when it should disappear
var int    NotifCount;

var float NotifDuration;      // how long each notification stays on screen

// ─────────────────────────────────────────────
//  Status
// ─────────────────────────────────────────────
var OLTogetherController TogetherController;
var float ConnectedFlashDuration;
var float ConnectedFlashEndTime;
var bool  bJustConnected;

// ─────────────────────────────────────────────
event PostBeginPlay()
{
    super.PostBeginPlay();
    ConnectedFlashDuration = 3.0;
    NotifDuration          = 5.0;
    NotifCount             = 0;
}

// ─────────────────────────────────────────────
//  Called from controller to push a notification
// ─────────────────────────────────────────────
function AddNotification(string Msg)
{
    local int i;

    // If full, shift everything up to drop oldest
    if (NotifCount >= MAX_NOTIFICATIONS)
    {
        for (i = 0; i < MAX_NOTIFICATIONS - 1; i++)
        {
            NotifText[i]   = NotifText[i + 1];
            NotifExpire[i] = NotifExpire[i + 1];
        }
        NotifCount = MAX_NOTIFICATIONS - 1;
    }

    NotifText[NotifCount]   = Msg;
    NotifExpire[NotifCount] = WorldInfo.TimeSeconds + NotifDuration;
    NotifCount++;
}

// ─────────────────────────────────────────────
//  Count connected remote players
// ─────────────────────────────────────────────
function int CountRemotePlayers()
{
    local int i, Count;
    Count = 0;
    for (i = 0; i < 8; i++)
        if (TogetherController.RemoteID[i] != 0)
            Count++;
    return Count;
}

// ─────────────────────────────────────────────
//  Draw
// ─────────────────────────────────────────────
event DrawHUD()
{
    local OLTogetherLink Link;
    local string         StatusText;
    local float          X, Y;
    local byte           R, G, B;
    local int            i, AliveCount;
    local float          NotifAlpha;

    super.DrawHUD();

    if (TogetherController == None)
        TogetherController = OLTogetherController(PlayerOwner);
    if (TogetherController == None)
        return;

    Link = TogetherController.NetworkLink;

    // ── Status line ───────────────────────────
    if (Link == None)
    {
        StatusText     = "OLTogether: Initializing...";
        R = 180; G = 180; B = 180;
        bJustConnected = false;
    }
    else if (Link.bIsResolving)
    {
        StatusText     = "OLTogether: Connecting to " $ Link.ServerHost $ ":" $ string(Link.ServerPort) $ "...";
        R = 255; G = 200; B = 0;
        bJustConnected = false;
    }
    else if (!Link.bIsConnected)
    {
        StatusText     = "OLTogether: Disconnected";
        R = 255; G = 60; B = 60;
        bJustConnected = false;
        ConnectedFlashEndTime = 0;
    }
    else
    {
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
            // Show yourself + remote players
            // +1 for yourself (the local player)
            StatusText = "OLTogether  [You + " $ string(CountRemotePlayers()) $ " online]";
            R = 80; G = 200; B = 80;
        }
    }

    X = 20;
    Y = 20;

    Canvas.SetPos(X + 1, Y + 1);
    Canvas.SetDrawColor(0, 0, 0, 140);
    Canvas.DrawText(StatusText,, 1.0, 1.0);

    Canvas.SetPos(X, Y);
    Canvas.SetDrawColor(R, G, B, 220);
    Canvas.DrawText(StatusText,, 1.0, 1.0);

    // ── Player list (yourself always shown) ───
    Y += 20;

    // Draw local player (yourself)
    if (TogetherController.MyPlayerID > 0)
    {
        Canvas.SetPos(X + 1, Y + 1);
        Canvas.SetDrawColor(0, 0, 0, 120);
        Canvas.DrawText("  Player " $ TogetherController.MyPlayerID $ " (You)",, 1.0, 1.0);

        Canvas.SetPos(X, Y);
        Canvas.SetDrawColor(120, 220, 120, 200);
        Canvas.DrawText("  Player " $ TogetherController.MyPlayerID $ " (You)",, 1.0, 1.0);
        Y += 16;
    }

    // Draw remote players
    for (i = 0; i < 8; i++)
    {
        if (TogetherController.RemoteID[i] == 0)
            continue;

        Canvas.SetPos(X + 1, Y + 1);
        Canvas.SetDrawColor(0, 0, 0, 120);
        Canvas.DrawText("  Player " $ TogetherController.RemoteID[i],, 1.0, 1.0);

        Canvas.SetPos(X, Y);
        Canvas.SetDrawColor(180, 180, 255, 200);
        Canvas.DrawText("  Player " $ TogetherController.RemoteID[i],, 1.0, 1.0);
        Y += 16;
    }

    // ── Notifications ─────────────────────────
    // Expire old ones first
    AliveCount = 0;
    for (i = 0; i < NotifCount; i++)
    {
        if (WorldInfo.TimeSeconds < NotifExpire[i])
        {
            if (AliveCount != i)
            {
                NotifText[AliveCount]   = NotifText[i];
                NotifExpire[AliveCount] = NotifExpire[i];
            }
            AliveCount++;
        }
    }
    NotifCount = AliveCount;

    // Draw from bottom of player list, offset a bit
    Y = Canvas.ClipY - 80;

    for (i = 0; i < NotifCount; i++)
    {
        // Fade out in last second
        if (WorldInfo.TimeSeconds > NotifExpire[i] - 1.0)
            NotifAlpha = (NotifExpire[i] - WorldInfo.TimeSeconds) * 220;
        else
            NotifAlpha = 220;

        if (NotifAlpha < 0)
            NotifAlpha = 0;

        Canvas.SetPos(X + 1, Y + 1);
        Canvas.SetDrawColor(0, 0, 0, byte(NotifAlpha * 0.6));
        Canvas.DrawText(NotifText[i],, 1.0, 1.0);

        Canvas.SetPos(X, Y);
        Canvas.SetDrawColor(255, 220, 80, byte(NotifAlpha));
        Canvas.DrawText(NotifText[i],, 1.0, 1.0);

        Y += 18;
    }
}

DefaultProperties
{
    ConnectedFlashDuration = 3.0
    bJustConnected         = false
    ConnectedFlashEndTime  = 0.0
    NotifDuration          = 5.0
    NotifCount             = 0
}
