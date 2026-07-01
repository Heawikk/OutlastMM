class OLTogetherHUD extends OLHUD;

const MAX_NOTIFICATIONS = 5;

var string NotifText   [5];
var float  NotifExpire [5];
var int    NotifCount;
var float  NotifDuration;

var OLTogetherController TogetherController;
var float ConnectedFlashDuration;
var float ConnectedFlashEndTime;
var bool  bJustConnected;

event PostBeginPlay()
{
    super.PostBeginPlay();
    ConnectedFlashDuration = 3.0;
    NotifDuration          = 5.0;
    NotifCount             = 0;
}

Event OnLostFocusPause(Bool bEnable) {
    //bLostFocus = bEnable;
    //if(bEnable && false) {
        return;
    //}
    //Super.OnLostFocusPause(bEnable);
}

function AddNotification(string Msg)
{
    local int i;

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

function int CountRemotePlayers()
{
    if (TogetherController == None) return 0;
    return TogetherController.RemotePlayers.Length;
}

function byte SafeByte(float Value)
{
    if (Value < 0)   return 0;
    if (Value > 255) return 255;
    return byte(Value);
}

event DrawHUD()
{
    local OLTogetherLink Link;
    local string         StatusText;
    local string         MyName, RemName;
    local float          X, Y;
    local byte           R, G, B;
    local int            i, AliveCount;
    local float          NotifAlpha;

    super.DrawHUD();

    if (Canvas == None)               return;
    if (WorldInfo == None)            return;
    if (PlayerOwner == None)          return;
    if (PlayerOwner.Pawn == None)     return;
    if (PlayerOwner.Pawn.bDeleteMe)   return;
    if (WorldInfo.bRequestedBlockOnAsyncLoading) return;

    if (TogetherController == None)
        TogetherController = OLTogetherController(PlayerOwner);
    if (TogetherController == None)
        return;

    Link = TogetherController.NetworkLink;

    if (Link == None)
    {
        StatusText     = "OutlastMM: Initializing...";
        R = 180; G = 180; B = 180;
        bJustConnected = false;
    }
    else if (Link.bIsResolving)
    {
        StatusText     = "OutlastMM: Connecting to " $ Link.ServerHost $ ":" $ string(Link.ServerPort) $ "...";
        R = 255; G = 200; B = 0;
        bJustConnected = false;
    }
    else if (!Link.bIsConnected)
    {
        StatusText     = "OutlastMM: Disconnected";
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
            StatusText = "OutlastMM: Connected!";
            R = 80; G = 255; B = 80;
        }
        else
        {
            StatusText = "OutlastMM  [You + " $ string(CountRemotePlayers()) $ " online]"
                $ (TogetherController.PingMs > 0
                    ? "  " $ string(TogetherController.PingMs) $ " ms"
                    : "");
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

    Y += 20;

    if (TogetherController.MyPlayerID > 0)
    {
        MyName = TogetherController.MyNickname != "" ? TogetherController.MyNickname : ("Player " $ TogetherController.MyPlayerID);

        Canvas.SetPos(X + 1, Y + 1);
        Canvas.SetDrawColor(0, 0, 0, 120);
        Canvas.DrawText("  " $ MyName $ " (You)",, 1.0, 1.0);

        Canvas.SetPos(X, Y);
        Canvas.SetDrawColor(120, 220, 120, 200);
        Canvas.DrawText("  " $ MyName $ " (You)",, 1.0, 1.0);
        Y += 16;
    }

    for (i = 0; i < TogetherController.RemotePlayers.Length; i++)
    {
        RemName = TogetherController.RemotePlayers[i].Nickname != "" ? TogetherController.RemotePlayers[i].Nickname : ("Player " $ TogetherController.RemotePlayers[i].PlayerID);

        Canvas.SetPos(X + 1, Y + 1);
        Canvas.SetDrawColor(0, 0, 0, 120);
        Canvas.DrawText("  " $ RemName,, 1.0, 1.0);

        Canvas.SetPos(X, Y);
        Canvas.SetDrawColor(180, 180, 255, 200);
        Canvas.DrawText("  " $ RemName,, 1.0, 1.0);
        Y += 16;
    }

    DrawPlayerLabels();

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

    Y = Canvas.ClipY - 80;

    for (i = 0; i < NotifCount; i++)
    {
        if (WorldInfo.TimeSeconds > NotifExpire[i] - 1.0)
            NotifAlpha = (NotifExpire[i] - WorldInfo.TimeSeconds) * 220;
        else
            NotifAlpha = 220;

        Canvas.SetPos(X + 1, Y + 1);
        Canvas.SetDrawColor(0, 0, 0, SafeByte(NotifAlpha * 0.6));
        Canvas.DrawText(NotifText[i],, 1.0, 1.0);

        Canvas.SetPos(X, Y);
        Canvas.SetDrawColor(255, 220, 80, SafeByte(NotifAlpha));
        Canvas.DrawText(NotifText[i],, 1.0, 1.0);

        Y += 18;
    }
}

function DrawPlayerLabels()
{
    local int     i;
    local vector  WorldPos, ScreenPos;
    local string  LabelText;
    local float   XL, YL, Dist, Alpha;

    if (TogetherController == None || PlayerOwner == None || PlayerOwner.Pawn == None)
        return;

    for (i = 0; i < TogetherController.RemotePlayers.Length; i++)
    {
        if (TogetherController.RemotePlayers[i].DummyPlayer == None) continue;

        WorldPos    = TogetherController.RemotePlayers[i].DummyPlayer.Location;
        WorldPos.Z += 190.0;

        ScreenPos = Canvas.Project(WorldPos);
        if (ScreenPos.Z <= 0.0) continue;

        Dist = VSize(WorldPos - PlayerOwner.Pawn.Location);
        if (Dist > 4000.0) continue;

        // Fade out between 2000 and 4000 units
        if (Dist > 2000.0)
            Alpha = (1.0 - (Dist - 2000.0) / 2000.0) * 220.0;
        else
            Alpha = 220.0;

        LabelText = TogetherController.RemotePlayers[i].Nickname != ""
            ? TogetherController.RemotePlayers[i].Nickname
            : ("Player " $ TogetherController.RemotePlayers[i].PlayerID);
        Canvas.TextSize(LabelText, XL, YL);

        Canvas.SetPos(ScreenPos.X - XL * 0.5 + 1, ScreenPos.Y + 1);
        Canvas.SetDrawColor(0, 0, 0, SafeByte(Alpha * 0.7));
        Canvas.DrawText(LabelText,, 1.0, 1.0);

        Canvas.SetPos(ScreenPos.X - XL * 0.5, ScreenPos.Y);
        Canvas.SetDrawColor(200, 220, 255, SafeByte(Alpha));
        Canvas.DrawText(LabelText,, 1.0, 1.0);
    }
}

DefaultProperties
{
    ConnectedFlashDuration = 3.0
    bJustConnected         = false
    ConnectedFlashEndTime  = 0.0
    NotifDuration          = 8.0
    NotifCount             = 0
}
