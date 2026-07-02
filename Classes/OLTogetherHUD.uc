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

var Texture2D WhiteTex;

event PostBeginPlay()
{
    super.PostBeginPlay();
    ConnectedFlashDuration = 3.0;
    NotifDuration          = 8.0;
    NotifCount             = 0;
}

Event OnLostFocusPause(Bool bEnable) { return; }

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

// Draw a filled rectangle using the engine's 1x1 white texture
function DrawRect(float X, float Y, float W, float H, byte R, byte G, byte B, byte A)
{
    if (WhiteTex == None) return;
    Canvas.SetPos(X, Y);
    Canvas.SetDrawColor(R, G, B, A);
    Canvas.DrawTile(WhiteTex, W, H, 0, 0, 1, 1);
}

event DrawHUD()
{
    super.DrawHUD();

    if (Canvas == None || WorldInfo == None || PlayerOwner == None) return;
    if (PlayerOwner.Pawn == None || PlayerOwner.Pawn.bDeleteMe)    return;
    if (WorldInfo.bRequestedBlockOnAsyncLoading)                    return;

    if (TogetherController == None)
        TogetherController = OLTogetherController(PlayerOwner);
    if (TogetherController == None) return;

    DrawStatusPanel();
    DrawPlayerLabels();
    DrawNotifications();
}

// ─── Top-left status panel ────────────────────────────────────────────────────
function DrawStatusPanel()
{
    local OLTogetherLink Link;
    local string   NameText, RightText;
    local float    PH, TY, XL, YL, Pulse;
    local byte     AR, AG, AB, SR, SG, SB, PR, PG, PB;
    local int      i, Rows;
    local bool     bConnected;

    // panel constants (all in screen pixels)
    local float PX, PY, PW;
    PX = 14.0;  PY = 14.0;  PW = 224.0;

    Link = TogetherController.NetworkLink;

    // Count content rows so we can compute panel height
    Rows = 0;
    if (TogetherController.MyPlayerID > 0) Rows++;
    Rows += TogetherController.RemotePlayers.Length;
    if (Link != None && Link.bFadeNearbyPlayers) Rows++;

    // header + 1px sep + player rows + bottom pad
    PH = 22.0 + 1.0 + 5.0 + Rows * 17.0 + 6.0;

    // ── pick accent / status-dot colour based on connection ──
    bConnected = false;
    RightText  = "";
    if (Link == None)
    {
        AR = 130; AG = 130; AB = 130;
        SR = 130; SG = 130; SB = 130;
        RightText = "INIT";
    }
    else if (Link.bIsReconnecting)
    {
        AR = 210; AG = 148; AB = 28;
        SR = 210; SG = 148; SB = 28;
        RightText = "RECONNECTING";
    }
    else if (Link.bIsResolving)
    {
        AR = 210; AG = 148; AB = 28;
        SR = 210; SG = 148; SB = 28;
        RightText = "CONNECTING";
    }
    else if (!Link.bIsConnected)
    {
        AR = 200; AG = 38; AB = 38;
        SR = 200; SG = 38; SB = 38;
        RightText = "OFFLINE";
        ConnectedFlashEndTime = 0;
        bJustConnected = false;
    }
    else
    {
        if (!bJustConnected)
        {
            bJustConnected        = true;
            ConnectedFlashEndTime = WorldInfo.TimeSeconds + ConnectedFlashDuration;
        }
        AR = 155; AG = 18; AB = 18;   // Outlast dark-red accent
        SR = 80;  SG = 210; SB = 80;
        if (WorldInfo.TimeSeconds < ConnectedFlashEndTime)
            RightText = "CONNECTED";
        bConnected = true;
    }

    // ── panel background + left accent bar ──
    DrawRect(PX,       PY, PW,    PH, 7, 3, 3, 172);
    DrawRect(PX,       PY, 3.0,   PH, AR, AG, AB, 235);

    TY = PY + 4.0;

    // ── header row ──

    // status dot (5×5) — vertically centred in the 22px header
    DrawRect(PX + 8.0, TY + 8.0, 5.0, 5.0, SR, SG, SB, 235);

    // title
    Canvas.SetPos(PX + 18.0, TY + 3.0);
    Canvas.SetDrawColor(218, 196, 174, 248);
    Canvas.DrawText("OUTLASTMM",, 1.0, 1.0);

    // right side: pulsing status OR count + ping
    if (RightText != "")
    {
        Pulse = Sin(WorldInfo.TimeSeconds * 3.6) * 0.38 + 0.62;
        Canvas.TextSize(RightText, XL, YL);
        Canvas.SetPos(PX + PW - XL - 6.0, TY + 3.0);
        Canvas.SetDrawColor(SR, SG, SB, SafeByte(205.0 * Pulse));
        Canvas.DrawText(RightText,, 1.0, 1.0);
    }
    else if (bConnected)
    {
        if      (TogetherController.PingMs <= 0 || TogetherController.PingMs < 60)  { PR=95;  PG=210; PB=95;  }
        else if (TogetherController.PingMs < 120)                                    { PR=220; PG=188; PB=55;  }
        else                                                                          { PR=220; PG=75;  PB=55;  }

        if (TogetherController.PingMs > 0)
            NameText = string(CountRemotePlayers()) $ " online  " $ string(TogetherController.PingMs) $ "ms";
        else
            NameText = string(CountRemotePlayers()) $ " online";

        Canvas.TextSize(NameText, XL, YL);
        Canvas.SetPos(PX + PW - XL - 6.0, TY + 3.0);
        Canvas.SetDrawColor(PR, PG, PB, 205);
        Canvas.DrawText(NameText,, 1.0, 1.0);
    }

    // ── separator ──
    TY += 22.0;
    DrawRect(PX + 3.0, TY, PW - 3.0, 1.0, 255, 255, 255, 20);
    TY += 1.0 + 5.0;

    // ── my name ──
    if (TogetherController.MyPlayerID > 0)
    {
        NameText = TogetherController.MyNickname != ""
            ? TogetherController.MyNickname
            : ("Player " $ string(TogetherController.MyPlayerID));

        DrawRect(PX + 10.0, TY + 6.0, 5.0, 5.0, 100, 215, 100, 220);
        Canvas.SetPos(PX + 20.0, TY);
        Canvas.SetDrawColor(212, 186, 144, 232);
        Canvas.DrawText(NameText $ "  (You)",, 1.0, 1.0);
        TY += 17.0;
    }

    // ── remote players ──
    for (i = 0; i < TogetherController.RemotePlayers.Length; i++)
    {
        NameText = TogetherController.RemotePlayers[i].Nickname != ""
            ? TogetherController.RemotePlayers[i].Nickname
            : ("Player " $ string(TogetherController.RemotePlayers[i].PlayerID));

        DrawRect(PX + 10.0, TY + 6.0, 5.0, 5.0, 128, 158, 218, 195);
        Canvas.SetPos(PX + 20.0, TY);
        Canvas.SetDrawColor(162, 184, 218, 218);
        Canvas.DrawText(NameText,, 1.0, 1.0);
        TY += 17.0;
    }

    // ── fade indicator (when speedrunner feature is active) ──
    if (Link != None && Link.bFadeNearbyPlayers)
    {
        DrawRect(PX + 10.0, TY + 6.0, 5.0, 5.0, 205, 160, 55, 185);
        Canvas.SetPos(PX + 20.0, TY);
        Canvas.SetDrawColor(205, 160, 55, 185);
        Canvas.DrawText("Fade  ON",, 1.0, 1.0);
    }
}

// ─── Bottom-left notifications ────────────────────────────────────────────────
function DrawNotifications()
{
    local int   i, AliveCount;
    local float NotifAlpha, X, Y, XL, YL;

    // compact dead entries
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

    X = 14.0;
    Y = Canvas.ClipY - 30.0 - float(NotifCount) * 23.0;

    for (i = 0; i < NotifCount; i++)
    {
        if (WorldInfo.TimeSeconds > NotifExpire[i] - 1.0)
            NotifAlpha = (NotifExpire[i] - WorldInfo.TimeSeconds) * 220.0;
        else
            NotifAlpha = 220.0;

        Canvas.TextSize(NotifText[i], XL, YL);

        // dark bg + left accent
        DrawRect(X - 5.0, Y - 3.0, XL + 10.0, YL + 6.0, 7, 3, 3, SafeByte(NotifAlpha * 0.70));
        DrawRect(X - 5.0, Y - 3.0, 2.5,        YL + 6.0, 222, 158, 55, SafeByte(NotifAlpha));

        // shadow + text
        Canvas.SetPos(X + 1.0, Y + 1.0);
        Canvas.SetDrawColor(0, 0, 0, SafeByte(NotifAlpha * 0.50));
        Canvas.DrawText(NotifText[i],, 1.0, 1.0);

        Canvas.SetPos(X, Y);
        Canvas.SetDrawColor(255, 215, 75, SafeByte(NotifAlpha));
        Canvas.DrawText(NotifText[i],, 1.0, 1.0);

        Y += 23.0;
    }
}

// ─── World-space player labels ────────────────────────────────────────────────
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

        WorldPos   = TogetherController.RemotePlayers[i].DummyPlayer.Location;
        WorldPos.Z += 190.0;

        ScreenPos = Canvas.Project(WorldPos);
        if (ScreenPos.Z <= 0.0) continue;

        Dist = VSize(WorldPos - PlayerOwner.Pawn.Location);
        if (Dist > 4000.0) continue;

        // fade 2000→4000
        if (Dist > 2000.0)
            Alpha = (1.0 - (Dist - 2000.0) / 2000.0) * 220.0;
        else
            Alpha = 220.0;

        LabelText = TogetherController.RemotePlayers[i].Nickname != ""
            ? TogetherController.RemotePlayers[i].Nickname
            : ("Player " $ string(TogetherController.RemotePlayers[i].PlayerID));

        Canvas.TextSize(LabelText, XL, YL);

        // dark background box
        DrawRect(ScreenPos.X - XL * 0.5 - 6.0, ScreenPos.Y - 3.0,
                 XL + 12.0, YL + 6.0,
                 7, 3, 3, SafeByte(Alpha * 0.65));
        // bottom accent line
        DrawRect(ScreenPos.X - XL * 0.5 - 6.0, ScreenPos.Y + YL + 3.0,
                 XL + 12.0, 2.0,
                 128, 158, 218, SafeByte(Alpha * 0.85));

        // shadow
        Canvas.SetPos(ScreenPos.X - XL * 0.5 + 1.0, ScreenPos.Y + 1.0);
        Canvas.SetDrawColor(0, 0, 0, SafeByte(Alpha * 0.60));
        Canvas.DrawText(LabelText,, 1.0, 1.0);

        // name
        Canvas.SetPos(ScreenPos.X - XL * 0.5, ScreenPos.Y);
        Canvas.SetDrawColor(182, 204, 242, SafeByte(Alpha));
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
    WhiteTex               = Texture2D'EngineResources.WhiteSquareTexture'
}
