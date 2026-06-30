class OLTogetherController extends OLPlayerController;

// ─────────────────────────────────────────────
//  Network
// ─────────────────────────────────────────────
var OLTogetherLink NetworkLink;
var int            MyRole;
var float          LastSendTime;
var float          InterpSpeed;

// ─────────────────────────────────────────────
//  Remote players — parallel fixed-size arrays
//  UE3 does not support array<struct> properly,
//  so we use parallel arrays indexed 0..MAX-1.
// ─────────────────────────────────────────────
const MAX_PLAYERS = 8;

var int     RemoteID          [8];   // 0 = slot empty
var Pawn    RemoteDummy       [8];
var vector  RemoteLoc         [8];
var vector  RemoteVel         [8];
var rotator RemoteRot         [8];
var int     RemoteHasData     [8];   // bool stored as int (UE3: no bool arrays)
var int     RemoteCrouched    [8];
var int     RemoteCamcorder   [8];
var int     RemoteCamState    [8];
var int     RemoteDummyCrouch [8];

// Pending timer target slot (one pending per callback type is enough
// because animations queue naturally and slots fire sequentially)
var int PendingIdleSlot;
var int PendingHidePropSlot;
var int PendingFinishReloadSlot;

// ─────────────────────────────────────────────
//  Init
// ─────────────────────────────────────────────
event PostBeginPlay()
{
    local int i;
    super.PostBeginPlay();

    for (i = 0; i < MAX_PLAYERS; i++)
        RemoteID[i] = 0;

    MyRole      = int(WorldInfo.Game.ParseOption(WorldInfo.GetLocalURL(), "Role"));
    NetworkLink = Spawn(class'OLTogetherLink', self);
    if (NetworkLink != None)
        NetworkLink.ControllerOwner = self;
}

// ─────────────────────────────────────────────
//  Slot helpers
// ─────────────────────────────────────────────
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
            RemoteID[i]          = ID;
            RemoteHasData[i]     = 0;
            RemoteCrouched[i]    = 0;
            RemoteCamcorder[i]   = 0;
            RemoteCamState[i]    = 0;
            RemoteDummyCrouch[i] = 0;
            return i;
        }
    }
    return -1; // full
}

function FreeSlot(int i)
{
    if (RemoteDummy[i] != None)
    {
        RemoteDummy[i].Destroy();
        RemoteDummy[i] = None;
    }
    RemoteID[i] = 0;
}

function int FindOrCreateSlot(int ID)
{
    local int          i;
    local AIController AIC;

    i = FindSlot(ID);
    if (i >= 0)
        return i;

    i = AllocSlot(ID);
    if (i < 0)
        return -1;

    if (Pawn != None)
    {
        RemoteDummy[i] = Spawn(class'OLTogetherHero',,, Pawn.Location, Pawn.Rotation,, true);
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
    }

    return i;
}

function SetupDummyVisuals(OLHero H)
{
    if (H == None)
        return;

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

// ─────────────────────────────────────────────
//  Tick
// ─────────────────────────────────────────────
event PlayerTick(float DeltaTime)
{
    local string  Payload;
    local int     i;
    local vector  ExtraLoc, SmoothLoc, AnimVel;
    local rotator SmoothRot;
    local float   Alpha;

    super.PlayerTick(DeltaTime);

    // ── Send local state ──────────────────────
    if (NetworkLink != None && NetworkLink.bIsConnected && Pawn != None)
    {
        if (WorldInfo.TimeSeconds - LastSendTime > 0.05)
        {
            LastSendTime = WorldInfo.TimeSeconds;
            Payload = "LOC,"
                $ Pawn.Location.X  $ "," $ Pawn.Location.Y  $ "," $ Pawn.Location.Z $ ","
                $ Pawn.Rotation.Pitch $ "," $ Pawn.Rotation.Yaw $ ","
                $ Pawn.Velocity.X  $ "," $ Pawn.Velocity.Y  $ "," $ Pawn.Velocity.Z $ ","
                $ int(Pawn.bIsCrouched) $ ","
                $ (OLHero(Pawn) != None ? int(OLHero(Pawn).bCamcorderDesired) : 0) $ ","
                $ (OLHero(Pawn) != None ? int(OLHero(Pawn).CamcorderState)    : 0);
            NetworkLink.SendText(Payload $ "\n");
        }
    }

    // ── Dead-reckoning per slot ───────────────
    Alpha = FClamp(DeltaTime * InterpSpeed, 0.0, 1.0);

    for (i = 0; i < MAX_PLAYERS; i++)
    {
        if (RemoteID[i] == 0 || RemoteDummy[i] == None || RemoteHasData[i] == 0)
            continue;

        // Extrapolate
        ExtraLoc   = RemoteLoc[i];
        ExtraLoc.X += RemoteVel[i].X * DeltaTime;
        ExtraLoc.Y += RemoteVel[i].Y * DeltaTime;
        ExtraLoc.Z += RemoteVel[i].Z * DeltaTime;
        RemoteLoc[i] = ExtraLoc;

        // Lerp position (manual — no VInterpTo in UE3 base)
        SmoothLoc.X = RemoteDummy[i].Location.X + (ExtraLoc.X - RemoteDummy[i].Location.X) * Alpha;
        SmoothLoc.Y = RemoteDummy[i].Location.Y + (ExtraLoc.Y - RemoteDummy[i].Location.Y) * Alpha;
        SmoothLoc.Z = RemoteDummy[i].Location.Z + (ExtraLoc.Z - RemoteDummy[i].Location.Z) * Alpha;
        RemoteDummy[i].SetLocation(SmoothLoc);

        // Lerp rotation (manual)
        SmoothRot.Pitch = RemoteDummy[i].Rotation.Pitch
            + int((RemoteRot[i].Pitch - RemoteDummy[i].Rotation.Pitch) * Alpha);
        SmoothRot.Yaw   = RemoteDummy[i].Rotation.Yaw
            + int((RemoteRot[i].Yaw   - RemoteDummy[i].Rotation.Yaw)   * Alpha);
        SmoothRot.Roll  = 0;
        RemoteDummy[i].SetRotation(SmoothRot);

        // Feed velocity to AnimTree
        AnimVel   = RemoteVel[i];
        AnimVel.Z = 0;
        RemoteDummy[i].Velocity     = AnimVel;
        RemoteDummy[i].Acceleration = AnimVel;
    }
}

// ─────────────────────────────────────────────
//  Timer callbacks
// ─────────────────────────────────────────────
function PlayCamcorderIdleAnimForSlot()
{
    local OLHero H;
    local int    i;
    i = PendingIdleSlot;
    if (i < 0 || i >= MAX_PLAYERS || RemoteID[i] == 0) return;
    H = OLHero(RemoteDummy[i]);
    if (H != None && H.ShadowProxyRightArmAnimSlot != None)
        H.ShadowProxyRightArmAnimSlot.PlayCustomAnim(
            'player_camcorder_idle', 1.0, 0.05, -1.0, true, true);
}

function HideCamcorderPropForSlot()
{
    local OLHero H;
    local int    i;
    i = PendingHidePropSlot;
    if (i < 0 || i >= MAX_PLAYERS || RemoteID[i] == 0) return;
    H = OLHero(RemoteDummy[i]);
    if (H != None && H.CameraMeshShadowProxy != None)
        H.CameraMeshShadowProxy.SetHidden(true);
}

function FinishInactiveReloadForSlot()
{
    local OLHero H;
    local int    i;
    i = PendingFinishReloadSlot;
    if (i < 0 || i >= MAX_PLAYERS || RemoteID[i] == 0) return;
    H = OLHero(RemoteDummy[i]);
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

// ─────────────────────────────────────────────
//  Receive data from server
// ─────────────────────────────────────────────
function OnReceiveData(string Data)
{
    local array<string> Parts;
    local int           SenderID, i;
    local vector        NewLoc, NewVel;
    local rotator       NewRot;
    local int           NewCrouched, NewCamcorder;
    local int           NewCamState;
    local OLHero        H;

    ParseStringIntoArray(Data, Parts, ",", true);

    if (Parts.Length < 2)
        return;

    SenderID = int(Parts[0]);

    // ── DISCONNECT ────────────────────────────
    if (Parts[1] == "DISCONNECT")
    {
        i = FindSlot(SenderID);
        if (i >= 0)
            FreeSlot(i);
        return;
    }

    // ── LOC ───────────────────────────────────
    // Format: SenderID,LOC,X,Y,Z,Pitch,Yaw,VX,VY,VZ,Crouched,Camcorder,CamcorderState
    if (Parts[1] != "LOC" || Parts.Length < 13)
        return;

    i = FindOrCreateSlot(SenderID);
    if (i < 0)
        return;

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

    if (RemoteDummy[i] == None)
        return;

    H = OLHero(RemoteDummy[i]);

    // ── Crouch ───────────────────────────────
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

    // ── Camcorder ────────────────────────────
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
                            ? 'player_crouch_camcorder_raise'
                            : 'player_camcorder_raise',
                        1.0, 0.15, 0.15, false, true);
                    PendingIdleSlot = i;
                    SetTimer(0.50, false, 'PlayCamcorderIdleAnimForSlot');
                }
                else
                {
                    ClearTimer('PlayCamcorderIdleAnimForSlot');
                    H.ShadowProxyRightArmAnimSlot.PlayCustomAnim(
                        RemoteDummyCrouch[i] != 0
                            ? 'player_crouch_camcorder_lower'
                            : 'player_camcorder_lower',
                        1.0, 0.15, 0.15, false, true);
                    PendingHidePropSlot = i;
                    SetTimer(0.55, false, 'HideCamcorderPropForSlot');
                }
            }
        }
    }

    // ── Camcorder state (reload) ──────────────
    if (NewCamState != RemoteCamState[i])
    {
        if (H != None)
        {
            if (NewCamState == 4) // active reload
            {
                ClearTimer('PlayCamcorderIdleAnimForSlot');
                ClearTimer('FinishInactiveReloadForSlot');
                if (H.ShadowProxyRightArmAnimSlot != None)
                    H.ShadowProxyRightArmAnimSlot.PlayCustomAnim(
                        RemoteDummyCrouch[i] != 0
                            ? 'player_crouch_camcorder_reload'
                            : 'player_camcorder_reload',
                        1.0, 0.15, 0.05, false, true);
                if (H.ShadowProxyLeftArmAnimSlot != None)
                    H.ShadowProxyLeftArmAnimSlot.PlayCustomAnim(
                        RemoteDummyCrouch[i] != 0
                            ? 'player_crouch_camcorder_reload'
                            : 'player_camcorder_reload',
                        1.0, 0.15, 0.4, false, true);
                PendingIdleSlot = i;
                SetTimer(2.85, false, 'PlayCamcorderIdleAnimForSlot');
            }
            else if (NewCamState == 5) // inactive reload
            {
                ClearTimer('PlayCamcorderIdleAnimForSlot');
                ClearTimer('FinishInactiveReloadForSlot');
                if (H.CameraMeshShadowProxy != None)
                    H.CameraMeshShadowProxy.SetHidden(false);
                if (H.ShadowProxyRightArmAnimSlot != None)
                    H.ShadowProxyRightArmAnimSlot.PlayCustomAnim(
                        RemoteDummyCrouch[i] != 0
                            ? 'player_crouch_camcorder_reload_inactive'
                            : 'player_camcorder_reload_inactive',
                        1.0, 0.15, 0.05, false, true);
                if (H.ShadowProxyLeftArmAnimSlot != None)
                    H.ShadowProxyLeftArmAnimSlot.PlayCustomAnim(
                        RemoteDummyCrouch[i] != 0
                            ? 'player_crouch_camcorder_reload_inactive'
                            : 'player_camcorder_reload_inactive',
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
    InterpSpeed         = 12.0
    PendingIdleSlot     = -1
    PendingHidePropSlot = -1
    PendingFinishReloadSlot = -1
}
