class OLTogetherController extends OLPlayerController;

var OLTogetherLink NetworkLink;
var int            MyRole;
var float          LastSendTime;
var float          InterpSpeed;
var int            MyPlayerID;

const MAX_PLAYERS = 8;

var int     RemoteID          [8];
var Pawn    RemoteDummy       [8];
var vector  RemoteLoc         [8];
var vector  RemoteVel         [8];
var rotator RemoteRot         [8];
var int     RemoteHasData     [8];
var int     RemoteCrouched    [8];
var int     RemoteCamcorder   [8];
var int     RemoteCamState    [8];
var int     RemoteDummyCrouch [8];

var int PendingIdleSlot;
var int PendingHidePropSlot;
var int PendingFinishReloadSlot;

// ─────────────────────────────────────────────
//  Validate slot — the single safe-guard used everywhere.
// ─────────────────────────────────────────────
function bool IsSlotValid(int i)
{
    if (i < 0 || i >= MAX_PLAYERS) return false;
    if (RemoteID[i] == 0)          return false;
    if (RemoteDummy[i] == None)    return false;
    if (RemoteDummy[i].bDeleteMe)
    {
        RemoteDummy[i] = None;
        ClearSlotData(i);
        return false;
    }
    return true;
}

event PostBeginPlay()
{
    local int i;
    super.PostBeginPlay();
    for (i = 0; i < MAX_PLAYERS; i++)
        ClearSlotData(i);
    MyPlayerID = 0;
    MyRole     = int(WorldInfo.Game.ParseOption(WorldInfo.GetLocalURL(), "Role"));

    // Spawn the TcpLink actor now, but it will NOT touch sockets until
    // we have a Pawn — see OLTogetherLink.TryStartConnect(). Spawning the
    // actor itself here is safe; only Resolve()/Open() were the problem.
    NetworkLink = Spawn(class'OLTogetherLink', self);
    if (NetworkLink != None)
        NetworkLink.ControllerOwner = self;
}

function ClearSlotData(int i)
{
    RemoteID[i]          = 0;
    RemoteDummy[i]       = None;
    RemoteHasData[i]     = 0;
    RemoteCrouched[i]    = 0;
    RemoteCamcorder[i]   = 0;
    RemoteCamState[i]    = 0;
    RemoteDummyCrouch[i] = 0;
    RemoteLoc[i]         = vect(0,0,0);
    RemoteVel[i]         = vect(0,0,0);
    RemoteRot[i]         = rot(0,0,0);
}

function int FindSlot(int ID)
{
    local int i;
    for (i = 0; i < MAX_PLAYERS; i++)
        if (RemoteID[i] == ID)
            return i;
    return -1;
}

function int AllocSlot(int ID)
{
    local int i;
    for (i = 0; i < MAX_PLAYERS; i++)
    {
        if (RemoteID[i] == 0)
        {
            ClearSlotData(i);
            RemoteID[i] = ID;
            return i;
        }
    }
    return -1;
}

function FreeSlot(int i)
{
    local Controller C;
    if (i < 0 || i >= MAX_PLAYERS) return;

    if (RemoteDummy[i] != None && !RemoteDummy[i].bDeleteMe)
    {
        C = RemoteDummy[i].Controller;
        if (C != None)
        {
            C.UnPossess();
            C.Destroy();
        }
        RemoteDummy[i].Destroy();
    }
    ClearSlotData(i);
}

function int FindOrCreateSlot(int ID)
{
    local int          i;
    local AIController AIC;
    local vector       SpawnLoc;
    local OLTogetherHUD THUD;

    i = FindSlot(ID);
    if (i >= 0) return i;

    // Only spawn dummies once we ourselves are fully in-game
    if (Pawn == None || Pawn.bDeleteMe) return -1;

    i = AllocSlot(ID);
    if (i < 0) return -1;

    SpawnLoc = Pawn.Location;

    RemoteDummy[i] = Spawn(class'OLTogetherHero',,, SpawnLoc,,, true);
    if (RemoteDummy[i] != None)
    {
        RemoteDummy[i].SetPhysics(PHYS_Walking);
        RemoteDummy[i].SetCollision(true, true);
        RemoteDummy[i].bCollideWorld = false;

        AIC = Spawn(class'AIController');
        if (AIC != None)
            AIC.Possess(RemoteDummy[i], false);

        SetupDummyVisuals(OLHero(RemoteDummy[i]));
    }

    THUD = OLTogetherHUD(myHUD);
    if (THUD != None)
        THUD.AddNotification("Player " $ ID $ " connected");

    return i;
}

function SetupDummyVisuals(OLHero H)
{
    if (H == None) return;
    if (H.Mesh != None)
    {
        H.Mesh.SetHidden(true);
        H.Mesh.SetOwnerNoSee(true);
        H.Mesh.bUpdateSkelWhenNotRendered    = true;
        H.Mesh.bTickAnimNodesWhenNotRendered = true;
    }
    if (H.ShadowProxy != None)
    {
        H.ShadowProxy.SetOwnerNoSee(false);
        H.ShadowProxy.SetHidden(false);
        H.ShadowProxy.bUpdateSkelWhenNotRendered    = true;
        H.ShadowProxy.bTickAnimNodesWhenNotRendered = true;
    }
    if (H.HeadMesh != None)
    {
        H.HeadMesh.SetHidden(false);
        H.HeadMesh.SetOwnerNoSee(false);
    }
    if (H.CameraMeshShadowProxy != None)
        H.CameraMeshShadowProxy.SetHidden(true);
}

event PlayerTick(float DeltaTime)
{
    local string  Payload;
    local int     i;
    local vector  ExtraLoc, SmoothLoc, AnimVel;
    local rotator SmoothRot;
    local float   Alpha;

    super.PlayerTick(DeltaTime);

    if (NetworkLink != None && NetworkLink.bIsConnected && Pawn != None && !Pawn.bDeleteMe)
    {
        if (WorldInfo.TimeSeconds - LastSendTime > 0.05)
        {
            LastSendTime = WorldInfo.TimeSeconds;
            Payload = "LOC,"
                $ Pawn.Location.X  $ "," $ Pawn.Location.Y  $ "," $ Pawn.Location.Z $ ","
                $ Rotation.Pitch $ "," $ Rotation.Yaw $ ","
                $ Pawn.Velocity.X  $ "," $ Pawn.Velocity.Y  $ "," $ Pawn.Velocity.Z $ ","
                $ int(Pawn.bIsCrouched) $ ","
                $ (OLHero(Pawn) != None ? int(OLHero(Pawn).bCamcorderDesired) : 0) $ ","
                $ (OLHero(Pawn) != None ? int(OLHero(Pawn).CamcorderState)    : 0);
            NetworkLink.SendText(Payload $ "\n");
        }
    }

    // No remote-player work until we ourselves have a pawn (i.e. in-game)
    if (Pawn == None)
        return;

    Alpha = FClamp(DeltaTime * InterpSpeed, 0.0, 1.0);

    for (i = 0; i < MAX_PLAYERS; i++)
    {
        if (!IsSlotValid(i) || RemoteHasData[i] == 0)
            continue;

        ExtraLoc    = RemoteLoc[i];
        ExtraLoc.X += RemoteVel[i].X * DeltaTime;
        ExtraLoc.Y += RemoteVel[i].Y * DeltaTime;
        ExtraLoc.Z += RemoteVel[i].Z * DeltaTime;
        RemoteLoc[i] = ExtraLoc;

        SmoothLoc.X = RemoteDummy[i].Location.X + (ExtraLoc.X - RemoteDummy[i].Location.X) * Alpha;
        SmoothLoc.Y = RemoteDummy[i].Location.Y + (ExtraLoc.Y - RemoteDummy[i].Location.Y) * Alpha;
        SmoothLoc.Z = RemoteDummy[i].Location.Z + (ExtraLoc.Z - RemoteDummy[i].Location.Z) * Alpha;
        RemoteDummy[i].SetLocation(SmoothLoc);

        SmoothRot.Pitch = RemoteDummy[i].Rotation.Pitch
            + int((RemoteRot[i].Pitch - RemoteDummy[i].Rotation.Pitch) * Alpha);
        SmoothRot.Yaw   = RemoteDummy[i].Rotation.Yaw
            + int((RemoteRot[i].Yaw   - RemoteDummy[i].Rotation.Yaw)   * Alpha);
        SmoothRot.Roll  = 0;
        RemoteDummy[i].SetRotation(SmoothRot);
        if (OLHero(RemoteDummy[i]) != None && OLHero(RemoteDummy[i]).ShadowProxy != None)
            OLHero(RemoteDummy[i]).ShadowProxy.SetRotation(SmoothRot);

        AnimVel   = RemoteVel[i];
        AnimVel.Z = 0;
        RemoteDummy[i].Velocity     = AnimVel;
        RemoteDummy[i].Acceleration = AnimVel;
    }
}

function PlayCamcorderIdleAnimForSlot()
{
    local OLHero H;
    if (!IsSlotValid(PendingIdleSlot)) return;
    H = OLHero(RemoteDummy[PendingIdleSlot]);
    if (H != None && H.ShadowProxyRightArmAnimSlot != None)
        H.ShadowProxyRightArmAnimSlot.PlayCustomAnim(
            'player_camcorder_idle', 1.0, 0.05, -1.0, true, true);
}

function HideCamcorderPropForSlot()
{
    local OLHero H;
    if (!IsSlotValid(PendingHidePropSlot)) return;
    H = OLHero(RemoteDummy[PendingHidePropSlot]);
    if (H != None && H.CameraMeshShadowProxy != None)
        H.CameraMeshShadowProxy.SetHidden(true);
}

function FinishInactiveReloadForSlot()
{
    local OLHero H;
    if (!IsSlotValid(PendingFinishReloadSlot)) return;
    H = OLHero(RemoteDummy[PendingFinishReloadSlot]);
    if (H != None)
    {
        if (H.CameraMeshShadowProxy != None)
            H.CameraMeshShadowProxy.SetHidden(true);
        if (H.ShadowProxyRightArmAnimSlot != None)
            H.ShadowProxyRightArmAnimSlot.StopCustomAnim(0.15);
        if (H.ShadowProxyLeftArmAnimSlot != None)
            H.ShadowProxyLeftArmAnimSlot.StopCustomAnim(0.15);
    }
}

function OnReceiveData(string Data)
{
    local array<string> Parts;
    local int           SenderID, i;
    local vector        NewLoc, NewVel;
    local rotator       NewRot;
    local int           NewCrouched, NewCamcorder, NewCamState;
    local OLHero        H;
    local OLTogetherHUD THUD;

    // Never process while we ourselves aren't fully in-game
    if (Pawn == None) return;

    ParseStringIntoArray(Data, Parts, ",", true);
    if (Parts.Length < 2) return;

    THUD = OLTogetherHUD(myHUD);

    // HELLO,YourID
    if (Parts[0] == "HELLO")
    {
        MyPlayerID = int(Parts[1]);
        if (THUD != None)
            THUD.AddNotification("Connected as Player " $ MyPlayerID);
        return;
    }

    SenderID = int(Parts[0]);
    if (SenderID <= 0) return;

    if (Parts[1] == "DISCONNECT")
    {
        i = FindSlot(SenderID);
        if (i >= 0)
        {
            if (THUD != None)
                THUD.AddNotification("Player " $ SenderID $ " disconnected");
            FreeSlot(i);
        }
        return;
    }

    if (Parts[1] != "LOC" || Parts.Length < 13) return;

    i = FindOrCreateSlot(SenderID);
    if (i < 0) return;

    NewLoc.X     = float(Parts[2]);
    NewLoc.Y     = float(Parts[3]);
    NewLoc.Z     = float(Parts[4]);
    NewRot.Pitch = int(Parts[5]);
    NewRot.Yaw   = int(Parts[6]);
    NewRot.Roll  = 0;
    NewVel.X     = float(Parts[7]);
    NewVel.Y     = float(Parts[8]);
    NewVel.Z     = float(Parts[9]);
    NewCrouched  = int(Parts[10]);
    NewCamcorder = int(Parts[11]);
    NewCamState  = int(Parts[12]);

    RemoteLoc[i]     = NewLoc;
    RemoteVel[i]     = NewVel;
    RemoteRot[i]     = NewRot;
    RemoteHasData[i] = 1;

    if (!IsSlotValid(i)) return;
    H = OLHero(RemoteDummy[i]);

    if (NewCrouched != RemoteCrouched[i])
    {
        RemoteCrouched[i]    = NewCrouched;
        RemoteDummyCrouch[i] = NewCrouched;
        if (NewCrouched != 0)
            RemoteDummy[i].ForceCrouch();
        else
            RemoteDummy[i].UnCrouch();
        if (H != None && H.ShadowProxy != None)
            H.ShadowProxy.PlayAnim(
                NewCrouched != 0 ? 'player_stand_to_crouch' : 'player_crouch_to_stand',
                1.0, false, true);
    }

    if (NewCamcorder != RemoteCamcorder[i])
    {
        RemoteCamcorder[i] = NewCamcorder;
        if (H != None)
        {
            H.bCamcorderDesired = (NewCamcorder != 0);
            if (H.ShadowProxyRightArmAnimSlot != None)
            {
                if (NewCamcorder != 0)
                {
                    ClearTimer('HideCamcorderPropForSlot');
                    if (H.CameraMeshShadowProxy != None)
                        H.CameraMeshShadowProxy.SetHidden(false);
                    H.ShadowProxyRightArmAnimSlot.PlayCustomAnim(
                        RemoteDummyCrouch[i] != 0
                            ? 'player_crouch_camcorder_raise' : 'player_camcorder_raise',
                        1.0, 0.15, 0.15, false, true);
                    PendingIdleSlot = i;
                    SetTimer(0.50, false, 'PlayCamcorderIdleAnimForSlot');
                }
                else
                {
                    ClearTimer('PlayCamcorderIdleAnimForSlot');
                    H.ShadowProxyRightArmAnimSlot.PlayCustomAnim(
                        RemoteDummyCrouch[i] != 0
                            ? 'player_crouch_camcorder_lower' : 'player_camcorder_lower',
                        1.0, 0.15, 0.15, false, true);
                    PendingHidePropSlot = i;
                    SetTimer(0.55, false, 'HideCamcorderPropForSlot');
                }
            }
        }
    }

    if (NewCamState != RemoteCamState[i])
    {
        if (H != None)
        {
            if (NewCamState == 4)
            {
                ClearTimer('PlayCamcorderIdleAnimForSlot');
                ClearTimer('FinishInactiveReloadForSlot');
                if (H.ShadowProxyRightArmAnimSlot != None)
                    H.ShadowProxyRightArmAnimSlot.PlayCustomAnim(
                        RemoteDummyCrouch[i] != 0
                            ? 'player_crouch_camcorder_reload' : 'player_camcorder_reload',
                        1.0, 0.15, 0.05, false, true);
                if (H.ShadowProxyLeftArmAnimSlot != None)
                    H.ShadowProxyLeftArmAnimSlot.PlayCustomAnim(
                        RemoteDummyCrouch[i] != 0
                            ? 'player_crouch_camcorder_reload' : 'player_camcorder_reload',
                        1.0, 0.15, 0.4, false, true);
                PendingIdleSlot = i;
                SetTimer(2.85, false, 'PlayCamcorderIdleAnimForSlot');
            }
            else if (NewCamState == 5)
            {
                ClearTimer('PlayCamcorderIdleAnimForSlot');
                ClearTimer('FinishInactiveReloadForSlot');
                if (H.CameraMeshShadowProxy != None)
                    H.CameraMeshShadowProxy.SetHidden(false);
                if (H.ShadowProxyRightArmAnimSlot != None)
                    H.ShadowProxyRightArmAnimSlot.PlayCustomAnim(
                        RemoteDummyCrouch[i] != 0
                            ? 'player_crouch_camcorder_reload_inactive' : 'player_camcorder_reload_inactive',
                        1.0, 0.15, 0.05, false, true);
                if (H.ShadowProxyLeftArmAnimSlot != None)
                    H.ShadowProxyLeftArmAnimSlot.PlayCustomAnim(
                        RemoteDummyCrouch[i] != 0
                            ? 'player_crouch_camcorder_reload_inactive' : 'player_camcorder_reload_inactive',
                        1.0, 0.15, 0.4, false, true);
                PendingFinishReloadSlot = i;
                SetTimer(2.85, false, 'FinishInactiveReloadForSlot');
            }
            else if (RemoteCamState[i] == 4 || RemoteCamState[i] == 5)
            {
                ClearTimer('PlayCamcorderIdleAnimForSlot');
                ClearTimer('FinishInactiveReloadForSlot');
                if (NewCamState == 1 && NewCamcorder != 0)
                {
                    if (H.ShadowProxyRightArmAnimSlot != None)
                        H.ShadowProxyRightArmAnimSlot.PlayCustomAnim(
                            'player_camcorder_idle', 1.0, 0.05, -1.0, true, true);
                    if (H.ShadowProxyLeftArmAnimSlot != None)
                        H.ShadowProxyLeftArmAnimSlot.StopCustomAnim(0.2);
                }
                else
                {
                    if (H.CameraMeshShadowProxy != None)
                        H.CameraMeshShadowProxy.SetHidden(true);
                    if (H.ShadowProxyRightArmAnimSlot != None)
                        H.ShadowProxyRightArmAnimSlot.StopCustomAnim(0.15);
                    if (H.ShadowProxyLeftArmAnimSlot != None)
                        H.ShadowProxyLeftArmAnimSlot.StopCustomAnim(0.15);
                }
            }
        }
        RemoteCamState[i] = NewCamState;
    }
}

DefaultProperties
{
    InterpSpeed             = 12.0
    PendingIdleSlot         = -1
    PendingHidePropSlot     = -1
    PendingFinishReloadSlot = -1
    MyPlayerID              = 0
}
