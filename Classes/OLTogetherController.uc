class OLTogetherController extends OLPlayerController;

var OLTogetherLink NetworkLink;
var int   MyRole;
var float LastSendTime;
var float InterpSpeed;
var int   MyPlayerID;
var float LastPingSentTime;
var int   PingMs;

struct RemotePlayerState
{
    var int   PlayerID;
    var Pawn  DummyPlayer;
    var OLTogetherRemoteTimer TimerHelper;

    var vector  LastReceivedLoc;
    var vector  LastReceivedVel;
    var rotator LastReceivedRot;
    var bool    bHasReceivedData;

    var bool   bLastRemoteCrouched;
    var bool   bLastRemoteCamcorder;
    var int    LastRemoteCamcorderState;
    var bool   bDummyCrouched;
    var int    LastLocomotionMode;
    var name   LastCrouchAnim;
    var string Nickname;
};
var array<RemotePlayerState> RemotePlayers;
var Pawn   LastSeenPawn;
var string MyNickname;



simulated event PostBeginPlay()
{
    super.PostBeginPlay();
    MyRole = int(WorldInfo.Game.ParseOption(WorldInfo.Game.ServerOptions, "Role"));
    NetworkLink = Spawn(class'OLTogetherLink', self);
    if (NetworkLink != None)
        NetworkLink.ControllerOwner = self;
    SetTimer(1.0, true, 'SendPing');
}

function int FindRemoteIndex(int PlayerID)
{
    local int i;
    for (i = 0; i < RemotePlayers.Length; i++)
        if (RemotePlayers[i].PlayerID == PlayerID)
            return i;
    return -1;
}

// Returns the shortest signed angular delta in UDK rotator units (-32768..32767).
// Prevents remote players from spinning the long way around when Yaw crosses 0/65536.
function int ShortestAngleDelta(int From, int To)
{
    local int Delta;
    Delta = (To - From) & 65535;
    if (Delta > 32768)
        Delta -= 65536;
    return Delta;
}

function SendPing()
{
    if (NetworkLink == None || !NetworkLink.bIsConnected) return;
    LastPingSentTime = WorldInfo.TimeSeconds;
    NetworkLink.SendText("PING,1\n");
}

event PlayerTick(float DeltaTime)
{
    local string  Payload;
    local vector  SmoothedLoc, AnimVel;
    local rotator SmoothedRot;
    local AIController AIC;
    local int     i;
    local float   Alpha, DistToDummy;
    local bool    bShouldFade;
    local OLHero  DH;

    super.PlayerTick(DeltaTime);

    // --- Send local player state ---
    if (NetworkLink != None && NetworkLink.bIsConnected && Pawn != None)
    {
        if (WorldInfo.TimeSeconds - LastSendTime > 0.05)
        {
            LastSendTime = WorldInfo.TimeSeconds;
            Payload = "LOC,"
                $ Pawn.Location.X $ "," $ Pawn.Location.Y $ "," $ Pawn.Location.Z $ ","
                $ Rotation.Pitch  $ "," $ Rotation.Yaw    $ ","
                $ Pawn.Velocity.X $ "," $ Pawn.Velocity.Y $ "," $ Pawn.Velocity.Z $ ","
                $ int(Pawn.bIsCrouched) $ ","
                $ (OLHero(Pawn) != None ? int(OLHero(Pawn).bCamcorderDesired) : 0) $ ","
                $ (OLHero(Pawn) != None ? int(OLHero(Pawn).CamcorderState)    : 0) $ ","
                $ (OLHero(Pawn) != None ? int(OLHero(Pawn).LocomotionMode) : 0) $ ","
                $ (OLHero(Pawn) != None ? int(OLHero(Pawn).SpecialMove) : 0);
            NetworkLink.SendText(Payload $ "\n");
        }

    }

    // --- Deferred dummy spawn (PlayerTick guarantees Pawn exists) ---
    for (i = 0; i < RemotePlayers.Length; i++)
    {
        if (RemotePlayers[i].DummyPlayer != None || Pawn == None || !RemotePlayers[i].bHasReceivedData)
            continue;

        RemotePlayers[i].DummyPlayer = Spawn(class'OLTogetherHero',,, Pawn.Location, Pawn.Rotation,, true);
        if (RemotePlayers[i].DummyPlayer != None)
        {
            RemotePlayers[i].DummyPlayer.SetPhysics(PHYS_None);
            RemotePlayers[i].DummyPlayer.SetCollision(false, false);
            RemotePlayers[i].DummyPlayer.bCollideWorld = false;

            AIC = Spawn(class'AIController');
            if (AIC != None)
                AIC.Possess(RemotePlayers[i].DummyPlayer, false);

            SetupDummyVisuals(OLHero(RemotePlayers[i].DummyPlayer));
        }
    }

    // --- Interpolation + animation per remote player ---
    Alpha = FClamp(DeltaTime * InterpSpeed, 0.0, 1.0);

    for (i = 0; i < RemotePlayers.Length; i++)
    {
        if (RemotePlayers[i].DummyPlayer == None || !RemotePlayers[i].bHasReceivedData)
            continue;

        SmoothedLoc = VInterpTo(RemotePlayers[i].DummyPlayer.Location,
                                RemotePlayers[i].LastReceivedLoc, DeltaTime, InterpSpeed);
        RemotePlayers[i].DummyPlayer.SetLocation(SmoothedLoc);

        // Yaw only — Outlast character is rigid (no head/body rotation split).
        // Pitch is camera-only and must never be applied to the mesh.
        SmoothedRot.Pitch = 0;
        SmoothedRot.Yaw   = RemotePlayers[i].DummyPlayer.Rotation.Yaw
            + int(ShortestAngleDelta(RemotePlayers[i].DummyPlayer.Rotation.Yaw,
                                     RemotePlayers[i].LastReceivedRot.Yaw) * Alpha);
        SmoothedRot.Roll  = 0;
        RemotePlayers[i].DummyPlayer.SetRotation(SmoothedRot);

        // Feed horizontal velocity to the AnimTree so walk/run locomotion plays
        AnimVel   = RemotePlayers[i].LastReceivedVel;
        AnimVel.Z = 0;
        RemotePlayers[i].DummyPlayer.Velocity     = AnimVel;
        RemotePlayers[i].DummyPlayer.Acceleration = AnimVel;

        DH = OLHero(RemotePlayers[i].DummyPlayer);
        if (DH != None && RemotePlayers[i].LastLocomotionMode == 0)
        {
            DH.LocomotionMode = LM_Walk;
            if (RemotePlayers[i].bLastRemoteCrouched)
                UpdateCrouchAnim(i, AnimVel);
        }

        // --- Proximity fade (speedrunner feature) ---
        if (DH != None && Pawn != None && NetworkLink != None && NetworkLink.bFadeNearbyPlayers)
        {
            DistToDummy  = VSize(SmoothedLoc - Pawn.Location);
            bShouldFade  = (DistToDummy < NetworkLink.NearbyFadeDistance);

            // Hysteresis: once faded, stay hidden until player moves further away
            if (!bShouldFade && DH.ShadowProxy != None && DH.ShadowProxy.HiddenGame)
                bShouldFade = (DistToDummy < NetworkLink.NearbyFadeDistance + NetworkLink.NearbyFadeHysteresis);

            if (DH.ShadowProxy != None)
                DH.ShadowProxy.SetHidden(bShouldFade);
            if (DH.HeadMesh != None)
                DH.HeadMesh.SetHidden(bShouldFade);
            if (bShouldFade && DH.CameraMeshShadowProxy != None)
                DH.CameraMeshShadowProxy.SetHidden(true);
        }
    }

}

function SetupDummyVisuals(OLHero H)
{
    local OLHero LocalHero;

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
    {
        H.CameraMeshShadowProxy.SetHidden(true);

        // handycamShadow has no materials (shadow-only mesh) → white for remote players.
        // Swap in the textured handycam mesh so the camera renders correctly.
        LocalHero = OLHero(Pawn);
        if (LocalHero != None && LocalHero.CameraMesh != None)
            H.CameraMeshShadowProxy.SetSkeletalMesh(LocalHero.CameraMesh.SkeletalMesh);
    }
}

function UpdateCrouchAnim(int Idx, vector AnimVel2D)
{
    local OLHero DH;
    local float  Speed, YawRad, ForwardDot, RightDot;
    local vector Forward, Right, NormVel;
    local name   DesiredAnim;

    DH = OLHero(RemotePlayers[Idx].DummyPlayer);
    if (DH == None || DH.ShadowProxy == None) return;

    Speed = VSize(AnimVel2D);
    if (Speed < 20.0)
    {
        DesiredAnim = 'player_crouch_idle';
    }
    else
    {
        // UDK rotator: full circle = 65536 units → radians = Yaw * (π / 32768)
        YawRad    = RemotePlayers[Idx].DummyPlayer.Rotation.Yaw * (3.14159265 / 32768.0);
        Forward.X = Cos(YawRad);
        Forward.Y = Sin(YawRad);
        Forward.Z = 0;
        Right.X   = Cos(YawRad + 1.5707963);
        Right.Y   = Sin(YawRad + 1.5707963);
        Right.Z   = 0;
        NormVel    = AnimVel2D / Speed;
        ForwardDot = (NormVel.X * Forward.X) + (NormVel.Y * Forward.Y);
        RightDot   = (NormVel.X * Right.X)   + (NormVel.Y * Right.Y);

        if      (ForwardDot >  0.7) DesiredAnim = 'player_crouch_forward';
        else if (ForwardDot < -0.7) DesiredAnim = 'player_crouch_backward';
        else if (RightDot   >  0.0) DesiredAnim = 'player_crouch_strafe_right';
        else                        DesiredAnim = 'player_crouch_strafe_left';
    }

    if (DesiredAnim != RemotePlayers[Idx].LastCrouchAnim)
    {
        RemotePlayers[Idx].LastCrouchAnim = DesiredAnim;
        if (DH.ShadowProxyFullBodyAnimSlot != None)
            DH.ShadowProxyFullBodyAnimSlot.PlayCustomAnim(DesiredAnim, 1.0, 0.1, 0.0, true, true);
    }
}

// --- Callbacks from OLTogetherRemoteTimer ---

function PlayCamcorderIdleAnimFor(int PlayerID)
{
    local int Idx;
    local OLHero DH;
    Idx = FindRemoteIndex(PlayerID);
    if (Idx == -1) return;
    DH = OLHero(RemotePlayers[Idx].DummyPlayer);
    if (DH != None && DH.ShadowProxyRightArmAnimSlot != None)
        DH.ShadowProxyRightArmAnimSlot.PlayCustomAnim(
            'player_camcorder_idle', 1.0, 0.05, -1.0, true, true);
}

function HideCamcorderPropFor(int PlayerID)
{
    local int Idx;
    local OLHero DH;
    Idx = FindRemoteIndex(PlayerID);
    if (Idx == -1) return;
    DH = OLHero(RemotePlayers[Idx].DummyPlayer);
    if (DH != None && DH.CameraMeshShadowProxy != None)
        DH.CameraMeshShadowProxy.SetHidden(true);
}

function FinishInactiveReloadFor(int PlayerID)
{
    local int Idx;
    local OLHero DH;
    Idx = FindRemoteIndex(PlayerID);
    if (Idx == -1) return;
    DH = OLHero(RemotePlayers[Idx].DummyPlayer);
    if (DH != None)
    {
        if (DH.CameraMeshShadowProxy != None)
            DH.CameraMeshShadowProxy.SetHidden(true);
        if (DH.ShadowProxyRightArmAnimSlot != None)
            DH.ShadowProxyRightArmAnimSlot.StopCustomAnim(0.15);
        if (DH.ShadowProxyLeftArmAnimSlot != None)
            DH.ShadowProxyLeftArmAnimSlot.StopCustomAnim(0.15);
    }
}

function PlayCrouchIdleFor(int PlayerID)
{
    local int Idx;
    local OLHero DH;
    Idx = FindRemoteIndex(PlayerID);
    if (Idx == -1) return;
    DH = OLHero(RemotePlayers[Idx].DummyPlayer);
    if (DH != None && DH.ShadowProxyFullBodyAnimSlot != None)
        DH.ShadowProxyFullBodyAnimSlot.PlayCustomAnim('player_crouch_idle', 1.0, 0.15, 0.0, true, true);
}

// --- Remote player lifetime ---

function RemoveRemotePlayer(int PlayerID)
{
    local int Idx;
    local Controller C;
    Idx = FindRemoteIndex(PlayerID);
    if (Idx == -1) return;

    if (RemotePlayers[Idx].DummyPlayer != None)
    {
        C = RemotePlayers[Idx].DummyPlayer.Controller;
        if (C != None) { C.UnPossess(); C.Destroy(); }
        RemotePlayers[Idx].DummyPlayer.Destroy();
    }
    if (RemotePlayers[Idx].TimerHelper != None)
        RemotePlayers[Idx].TimerHelper.Destroy();

    RemotePlayers.Remove(Idx, 1);
}

// --- Data receive ---

function OnReceiveData(string Data)
{
    local array<string> Parts;
    local vector NewLoc, NewVel;
    local rotator NewRot;
    local bool bNewCrouched, bNewCamcorder;
    local int NewCamcorderState, NewLocoMode, OldLocoMode, NewSpecialMove;
    local int    SenderID, Idx;
    local string Nick;
    local OLHero DH;
    local RemotePlayerState NewState;
    local OLTogetherHUD THUD;

    Parts = SplitString(Data, ",", true);
    if (Parts.Length < 2) return;

    THUD = OLTogetherHUD(myHUD);

    // PONG response to our own PING
    if (Parts[0] == "PONG")
    {
        if (LastPingSentTime > 0.0)
            PingMs = int((WorldInfo.TimeSeconds - LastPingSentTime) * 1000.0);
        return;
    }

    // HELLO,<YourID>
    if (Parts[0] == "HELLO")
    {
        MyPlayerID = int(Parts[1]);
        Nick = (NetworkLink != None) ? NetworkLink.PlayerNickname : "";
        if (Nick == "")
            Nick = "Player " $ MyPlayerID;
        NetworkLink.SendText("NICK," $ Nick $ "\n");
        return;
    }

    SenderID = int(Parts[0]);
    if (SenderID <= 0) return;

    if (Parts[1] == "DISCONNECT")
    {
        Idx = FindRemoteIndex(SenderID);
        Nick = (Idx != -1 && RemotePlayers[Idx].Nickname != "") ? RemotePlayers[Idx].Nickname : ("Player " $ SenderID);
        if (THUD != None)
            THUD.AddNotification(Nick $ " disconnected");
        RemoveRemotePlayer(SenderID);
        return;
    }

    if (Parts[1] == "NICK")
    {
        if (Parts.Length >= 3)
        {
            if (SenderID == MyPlayerID)
            {
                MyNickname = Parts[2];
                if (THUD != None)
                    THUD.AddNotification("Connected as " $ MyNickname);
            }
            else
            {
                Idx = FindRemoteIndex(SenderID);
                if (Idx == -1)
                {
                    NewState.PlayerID                 = SenderID;
                    NewState.Nickname                 = Parts[2];
                    NewState.bHasReceivedData         = false;
                    NewState.bLastRemoteCamcorder     = false;
                    NewState.bLastRemoteCrouched      = false;
                    NewState.LastRemoteCamcorderState = 0;
                    NewState.LastLocomotionMode = 0;
                    NewState.LastCrouchAnim           = '';
                    NewState.TimerHelper = Spawn(class'OLTogetherRemoteTimer', self);
                    if (NewState.TimerHelper != None)
                    {
                        NewState.TimerHelper.ControllerOwner = self;
                        NewState.TimerHelper.PlayerID        = SenderID;
                    }
                    RemotePlayers.AddItem(NewState);
                    if (THUD != None)
                        THUD.AddNotification(Parts[2] $ " connected");
                }
                else
                {
                    RemotePlayers[Idx].Nickname = Parts[2];
                }
            }
        }
        return;
    }

    if (Parts.Length < 15 || Parts[1] != "LOC")
        return;

    // Find or create state slot — dummy spawns later in PlayerTick
    Idx = FindRemoteIndex(SenderID);
    if (Idx == -1)
    {
        NewState.PlayerID                 = SenderID;
        NewState.bHasReceivedData         = false;
        NewState.bLastRemoteCamcorder     = false;
        NewState.bLastRemoteCrouched      = false;
        NewState.LastRemoteCamcorderState = 0;
        NewState.LastLocomotionMode = 0;
        NewState.LastCrouchAnim     = '';
        NewState.TimerHelper = Spawn(class'OLTogetherRemoteTimer', self);
        if (NewState.TimerHelper != None)
        {
            NewState.TimerHelper.ControllerOwner = self;
            NewState.TimerHelper.PlayerID        = SenderID;
        }
        RemotePlayers.AddItem(NewState);
        Idx = RemotePlayers.Length - 1;
        if (THUD != None)
            THUD.AddNotification("Player " $ SenderID $ " connected");
    }

    NewLoc.X = float(Parts[2]);
    NewLoc.Y = float(Parts[3]);
    NewLoc.Z = float(Parts[4]);
    NewRot.Pitch = int(Parts[5]);
    NewRot.Yaw   = int(Parts[6]);
    NewRot.Roll  = 0;
    NewVel.X = float(Parts[7]);
    NewVel.Y = float(Parts[8]);
    NewVel.Z = float(Parts[9]);
    bNewCrouched      = int(Parts[10]) != 0;
    bNewCamcorder     = int(Parts[11]) != 0;
    NewCamcorderState = int(Parts[12]);
    NewLocoMode       = int(Parts[13]);
    NewSpecialMove    = int(Parts[14]);

    RemotePlayers[Idx].LastReceivedLoc  = NewLoc;
    RemotePlayers[Idx].LastReceivedVel  = NewVel;
    RemotePlayers[Idx].LastReceivedRot  = NewRot;
    RemotePlayers[Idx].bHasReceivedData = true;

    // Dummy might not be spawned yet (deferred to PlayerTick)
    if (RemotePlayers[Idx].DummyPlayer == None || RemotePlayers[Idx].TimerHelper == None)
        return;

    DH = OLHero(RemotePlayers[Idx].DummyPlayer);
    if (DH == None) return;

    // --- Crouch ---
    if (bNewCrouched != RemotePlayers[Idx].bLastRemoteCrouched)
    {
        RemotePlayers[Idx].bLastRemoteCrouched = bNewCrouched;
        RemotePlayers[Idx].bDummyCrouched      = bNewCrouched;
        RemotePlayers[Idx].LastCrouchAnim      = 'player_crouch_idle';
        RemotePlayers[Idx].TimerHelper.ClearTimer('PlayCrouchIdle');

        if (DH.ShadowProxyFullBodyAnimSlot != None)
        {
            if (bNewCrouched)
            {
                DH.ShadowProxyFullBodyAnimSlot.PlayCustomAnim('player_stand_to_crouch', 1.0, 0.1, -1.0, false, true);
                RemotePlayers[Idx].TimerHelper.SetTimer(0.55, false, 'PlayCrouchIdle');
            }
            else
            {
                DH.ShadowProxyFullBodyAnimSlot.PlayCustomAnim('player_crouch_to_stand', 1.0, 0.1, 0.0, false, true);
            }
        }
        DH.LocomotionMode = LM_Walk;
    }

    // --- Camcorder ---
    if (bNewCamcorder != RemotePlayers[Idx].bLastRemoteCamcorder)
    {
        RemotePlayers[Idx].bLastRemoteCamcorder = bNewCamcorder;
        DH.bCamcorderDesired = bNewCamcorder;

        if (DH.ShadowProxyRightArmAnimSlot != None)
        {
            if (bNewCamcorder)
            {
                RemotePlayers[Idx].TimerHelper.ClearTimer('PlayIdleAnim');
                if (DH.CameraMeshShadowProxy != None)
                    DH.CameraMeshShadowProxy.SetHidden(false);
                DH.ShadowProxyRightArmAnimSlot.PlayCustomAnim(
                    RemotePlayers[Idx].bDummyCrouched
                        ? 'player_crouch_camcorder_raise' : 'player_camcorder_raise',
                    1.0, 0.15, 0.15, false, true);
                RemotePlayers[Idx].TimerHelper.SetTimer(0.50, false, 'PlayIdleAnim');
            }
            else
            {
                RemotePlayers[Idx].TimerHelper.ClearTimer('PlayIdleAnim');
                DH.ShadowProxyRightArmAnimSlot.PlayCustomAnim(
                    RemotePlayers[Idx].bDummyCrouched
                        ? 'player_crouch_camcorder_lower' : 'player_camcorder_lower',
                    1.0, 0.15, 0.15, false, true);
                RemotePlayers[Idx].TimerHelper.SetTimer(0.55, false, 'HideCamcorderProp');
            }
        }
    }

    // --- Camcorder state (reload) ---
    if (NewCamcorderState != RemotePlayers[Idx].LastRemoteCamcorderState)
    {
        if (NewCamcorderState == 4)
        {
            RemotePlayers[Idx].TimerHelper.ClearTimer('PlayIdleAnim');
            RemotePlayers[Idx].TimerHelper.ClearTimer('FinishInactiveReload');
            if (DH.ShadowProxyRightArmAnimSlot != None)
                DH.ShadowProxyRightArmAnimSlot.PlayCustomAnim(
                    RemotePlayers[Idx].bDummyCrouched
                        ? 'player_crouch_camcorder_reload' : 'player_camcorder_reload',
                    1.0, 0.15, 0.05, false, true);
            if (DH.ShadowProxyLeftArmAnimSlot != None)
                DH.ShadowProxyLeftArmAnimSlot.PlayCustomAnim(
                    RemotePlayers[Idx].bDummyCrouched
                        ? 'player_crouch_camcorder_reload' : 'player_camcorder_reload',
                    1.0, 0.15, 0.4, false, true);
            RemotePlayers[Idx].TimerHelper.SetTimer(2.85, false, 'PlayIdleAnim');
        }
        else if (NewCamcorderState == 5)
        {
            RemotePlayers[Idx].TimerHelper.ClearTimer('PlayIdleAnim');
            RemotePlayers[Idx].TimerHelper.ClearTimer('FinishInactiveReload');
            if (DH.CameraMeshShadowProxy != None)
                DH.CameraMeshShadowProxy.SetHidden(false);
            if (DH.ShadowProxyRightArmAnimSlot != None)
                DH.ShadowProxyRightArmAnimSlot.PlayCustomAnim(
                    RemotePlayers[Idx].bDummyCrouched
                        ? 'player_crouch_camcorder_reload_inactive' : 'player_camcorder_reload_inactive',
                    1.0, 0.15, 0.05, false, true);
            if (DH.ShadowProxyLeftArmAnimSlot != None)
                DH.ShadowProxyLeftArmAnimSlot.PlayCustomAnim(
                    RemotePlayers[Idx].bDummyCrouched
                        ? 'player_crouch_camcorder_reload_inactive' : 'player_camcorder_reload_inactive',
                    1.0, 0.15, 0.4, false, true);
            RemotePlayers[Idx].TimerHelper.SetTimer(2.85, false, 'FinishInactiveReload');
        }
        else if (RemotePlayers[Idx].LastRemoteCamcorderState == 4 ||
                 RemotePlayers[Idx].LastRemoteCamcorderState == 5)
        {
            RemotePlayers[Idx].TimerHelper.ClearTimer('PlayIdleAnim');
            RemotePlayers[Idx].TimerHelper.ClearTimer('FinishInactiveReload');
            if (NewCamcorderState == 1 && bNewCamcorder)
            {
                PlayCamcorderIdleAnimFor(SenderID);
                if (DH.ShadowProxyLeftArmAnimSlot != None)
                    DH.ShadowProxyLeftArmAnimSlot.StopCustomAnim(0.2);
            }
            else
            {
                if (DH.CameraMeshShadowProxy != None)
                    DH.CameraMeshShadowProxy.SetHidden(true);
                if (DH.ShadowProxyRightArmAnimSlot != None)
                    DH.ShadowProxyRightArmAnimSlot.StopCustomAnim(0.15);
                if (DH.ShadowProxyLeftArmAnimSlot != None)
                    DH.ShadowProxyLeftArmAnimSlot.StopCustomAnim(0.15);
            }
        }
        RemotePlayers[Idx].LastRemoteCamcorderState = NewCamcorderState;
    }

    // --- Locomotion mode ---
    if (NewLocoMode != RemotePlayers[Idx].LastLocomotionMode)
    {
        OldLocoMode = RemotePlayers[Idx].LastLocomotionMode;
        RemotePlayers[Idx].LastLocomotionMode = NewLocoMode;

        if (OldLocoMode == 8) // leaving locker — stop hide anim
        {
            if (DH.ShadowProxyFullBodyAnimSlot != None)
                DH.ShadowProxyFullBodyAnimSlot.StopCustomAnim(0.1);
        }

        switch (NewLocoMode)
        {
            case 1: // LM_Fall — natural falling off ledge
                DH.LocomotionMode = LM_Fall;
                break;

            case 2: // LM_SpecialMove — jump, enter/exit bed or locker, etc.
                switch (NewSpecialMove)
                {
                    case 3: // SMT_JumpOnSpot
                        if (DH.ShadowProxyFullBodyAnimSlot != None)
                            DH.ShadowProxyFullBodyAnimSlot.PlayCustomAnim('player_jump_on_spot', 1.0, 0.1, 0.0, false, true);
                        break;
                    case 5: // SMT_JumpOver
                        if (DH.ShadowProxyFullBodyAnimSlot != None)
                            DH.ShadowProxyFullBodyAnimSlot.PlayCustomAnim('player_jump_from_run', 1.0, 0.1, 0.0, false, true);
                        break;
                    case 37: // SMT_OpenLockerFromOutside — opens locker door from outside (visible to others)
                        if (DH.ShadowProxyFullBodyAnimSlot != None)
                            DH.ShadowProxyFullBodyAnimSlot.PlayCustomAnim('player_locker_open_straight', 1.0, 0.1, 0.2, false, true);
                        break;
                    case 38: // SMT_EnterLocker — body moves inside; blend to hide pose
                        if (DH.ShadowProxyFullBodyAnimSlot != None)
                            DH.ShadowProxyFullBodyAnimSlot.PlayCustomAnim('player_locker_hide', 1.0, 0.3, -1.0, true, true);
                        break;
                    case 40: // SMT_EnterBed
                        if (DH.ShadowProxyFullBodyAnimSlot != None)
                            DH.ShadowProxyFullBodyAnimSlot.PlayCustomAnim(
                                RemotePlayers[Idx].bLastRemoteCrouched
                                    ? 'player_enter_bed_left' : 'player_enter_bed_left_stand',
                                1.0, 0.15, 0.0, false, true);
                        break;
                    case 41: // SMT_ExitBed
                        if (DH.ShadowProxyFullBodyAnimSlot != None)
                            DH.ShadowProxyFullBodyAnimSlot.PlayCustomAnim('player_exit_bed_left', 1.0, 0.1, 0.1, false, true);
                        break;
                    default:
                        break;
                }
                break;

            case 8: // LM_Locker — hiding in wardrobe/locker
                if (DH.ShadowProxyFullBodyAnimSlot != None)
                    DH.ShadowProxyFullBodyAnimSlot.PlayCustomAnim('player_locker_hide', 1.0, 0.2, -1.0, true, true);
                break;

            case 10: // LM_Bed — hiding under bed; C++ UpdateBedAnimation drives ShadowProxyBedAnimNode
                DH.LocomotionMode = LM_Bed;
                break;

            case 0: // LM_Walk — back to normal
            default:
                DH.LocomotionMode = LM_Walk;
                if (OldLocoMode == 1) // was falling
                {
                    if (DH.ShadowProxyFullBodyAnimSlot != None)
                        DH.ShadowProxyFullBodyAnimSlot.PlayCustomAnim('player_land', 1.0, 0.05, 0.1, false, true);
                }
                else if (OldLocoMode == 8) // was in locker
                {
                    if (DH.ShadowProxyFullBodyAnimSlot != None)
                        DH.ShadowProxyFullBodyAnimSlot.PlayCustomAnim('player_locker_exit', 1.0, 0.1, 0.1, false, true);
                }
                break;
        }
    }
}

DefaultProperties
{
    InterpSpeed      = 12.0
    MyPlayerID       = 0
    LastPingSentTime = 0.0
    PingMs           = 0
}
