class OLTogetherLink extends TcpLink
    config(Multiplayer);

var OLTogetherController ControllerOwner;
var bool bIsConnected;
var bool bIsResolving;

var config string ServerHost;
var config int    ServerPort;
var config string PlayerNickname;

event PostBeginPlay()
{
    super.PostBeginPlay();

    if (ServerHost == "")
        ServerHost = "127.0.0.1";
    if (ServerPort <= 0)
        ServerPort = 7777;

    LinkMode    = MODE_Line;
    ReceiveMode = RMODE_Event;

    // CRITICAL: do not call Resolve()/Open() here. Hitting the native socket
    // code while the level is still mid-load (main menu, checkpoint load,
    // seamless travel) has been confirmed to crash the engine with no
    // UnrealScript stack trace. Defer until the owning player actually has
    // a possessed Pawn, i.e. we're truly in-game.
    SetTimer(0.1, true, 'TryStartConnect');
}

function TryStartConnect()
{
    if (ControllerOwner == None || ControllerOwner.Pawn == None)
        return;

    ClearTimer('TryStartConnect');
    bIsResolving = true;
    `log("OutlastMM: Connecting to" @ ServerHost $ ":" $ string(ServerPort));
    Resolve(ServerHost);
}

event Resolved(IpAddr Addr)
{
    bIsResolving = false;
    Addr.Port    = ServerPort;
    BindPort();
    Open(Addr);
}

event ResolveFailed()
{
    bIsResolving = false;
    bIsConnected = false;
    `log("OutlastMM: DNS resolve failed for" @ ServerHost);
}

event Opened()
{
    bIsConnected = true;
    `log("OutlastMM: Connected to" @ ServerHost $ ":" $ string(ServerPort));
}

event Closed()
{
    bIsConnected = false;
    `log("OutlastMM: Disconnected.");
}

event ReceivedLine(string Line)
{
    if (ControllerOwner != None)
        ControllerOwner.OnReceiveData(Line);
}

DefaultProperties
{
    ServerHost      = "127.0.0.1"
    ServerPort      = 7777
    PlayerNickname  = ""
    bIsConnected    = false
    bIsResolving    = false
}
