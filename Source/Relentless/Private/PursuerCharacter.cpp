#include "PursuerCharacter.h"
#include "ChaseDoor.h"
#include "ChaseSubsystem.h"
#include "GreyboxUtils.h"
#include "RelentlessCharacter.h"
#include "Components/CapsuleComponent.h"
#include "Components/PointLightComponent.h"
#include "Components/StaticMeshComponent.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "Kismet/GameplayStatics.h"
#include "UObject/ConstructorHelpers.h"

namespace
{
	UStaticMeshComponent* MakePart(AActor* Owner, USceneComponent* Parent, const TCHAR* Name, UStaticMesh* Mesh,
		const FVector& Location, const FVector& Scale, const FRotator& Rotation = FRotator::ZeroRotator)
	{
		UStaticMeshComponent* Part = Owner->CreateDefaultSubobject<UStaticMeshComponent>(Name);
		Part->SetupAttachment(Parent);
		Part->SetStaticMesh(Mesh);
		Part->SetRelativeLocation(Location);
		Part->SetRelativeRotation(Rotation);
		Part->SetRelativeScale3D(Scale);
		Part->SetCollisionEnabled(ECollisionEnabled::NoCollision);
		Part->SetGenerateOverlapEvents(false);
		return Part;
	}
}

APursuerCharacter::APursuerCharacter()
{
	PrimaryActorTick.bCanEverTick = true;

	// 2.8m tall and hunched: it fits through doorways, never through vents.
	GetCapsuleComponent()->InitCapsuleSize(60.f, 140.f);
	bUseControllerRotationYaw = false;
	AutoPossessAI = EAutoPossessAI::Disabled;

	UCharacterMovementComponent* Move = GetCharacterMovement();
	// No AI controller needed; it steers itself along the trail.
	Move->bRunPhysicsWithNoController = true;
	Move->bOrientRotationToMovement = true;
	Move->RotationRate = FRotator(0.f, 540.f, 0.f);
	Move->MaxWalkSpeed = 550.f;
	Move->MaxAcceleration = 3000.f;
	Move->BrakingDecelerationWalking = 2500.f;
	Move->JumpZVelocity = 600.f;
	Move->MaxStepHeight = 60.f;

	static ConstructorHelpers::FObjectFinder<UStaticMesh> Cube(Greybox::CubePath);
	static ConstructorHelpers::FObjectFinder<UStaticMesh> Sphere(Greybox::SpherePath);
	static ConstructorHelpers::FObjectFinder<UStaticMesh> Cylinder(Greybox::CylinderPath);
	static ConstructorHelpers::FObjectFinder<UStaticMesh> Cone(Greybox::ConePath);

	BodyRoot = CreateDefaultSubobject<USceneComponent>(TEXT("BodyRoot"));
	BodyRoot->SetupAttachment(GetCapsuleComponent());

	Torso = MakePart(this, BodyRoot, TEXT("Torso"), Cylinder.Object, FVector(8.f, 0.f, 25.f), FVector(0.9f, 0.75f, 1.4f), FRotator(-15.f, 0.f, 0.f));
	Head = MakePart(this, BodyRoot, TEXT("Head"), Sphere.Object, FVector(42.f, 0.f, 108.f), FVector(0.55f, 0.5f, 0.6f));
	HornLeft = MakePart(this, Head, TEXT("HornLeft"), Cone.Object, FVector(-10.f, -30.f, 70.f), FVector(0.25f, 0.25f, 0.9f), FRotator(0.f, 0.f, 25.f));
	HornRight = MakePart(this, Head, TEXT("HornRight"), Cone.Object, FVector(-10.f, 30.f, 70.f), FVector(0.25f, 0.25f, 0.9f), FRotator(0.f, 0.f, -25.f));

	ShoulderLeft = CreateDefaultSubobject<USceneComponent>(TEXT("ShoulderLeft"));
	ShoulderLeft->SetupAttachment(BodyRoot);
	ShoulderLeft->SetRelativeLocation(FVector(15.f, -55.f, 80.f));
	ShoulderRight = CreateDefaultSubobject<USceneComponent>(TEXT("ShoulderRight"));
	ShoulderRight->SetupAttachment(BodyRoot);
	ShoulderRight->SetRelativeLocation(FVector(15.f, 55.f, 80.f));
	// Arms far too long for its body.
	ArmLeft = MakePart(this, ShoulderLeft, TEXT("ArmLeft"), Cube.Object, FVector(0.f, 0.f, -80.f), FVector(0.17f, 0.17f, 1.6f));
	ArmRight = MakePart(this, ShoulderRight, TEXT("ArmRight"), Cube.Object, FVector(0.f, 0.f, -80.f), FVector(0.17f, 0.17f, 1.6f));

	LegLeft = MakePart(this, BodyRoot, TEXT("LegLeft"), Cylinder.Object, FVector(0.f, -28.f, -92.f), FVector(0.32f, 0.32f, 0.95f));
	LegRight = MakePart(this, BodyRoot, TEXT("LegRight"), Cylinder.Object, FVector(0.f, 28.f, -92.f), FVector(0.32f, 0.32f, 0.95f));

	EyeGlow = CreateDefaultSubobject<UPointLightComponent>(TEXT("EyeGlow"));
	EyeGlow->SetupAttachment(Head);
	EyeGlow->SetRelativeLocation(FVector(60.f, 0.f, 10.f));
	EyeGlow->IntensityUnits = ELightUnits::Lumens;
	EyeGlow->Intensity = 60.f;
	EyeGlow->AttenuationRadius = 180.f;
	EyeGlow->LightColor = FColor(255, 40, 20);
	EyeGlow->SetCastShadows(false);
}

void APursuerCharacter::BeginPlay()
{
	Super::BeginPlay();

	const FLinearColor Skin(0.012f, 0.012f, 0.015f);
	const FLinearColor Bone(0.22f, 0.19f, 0.15f);
	for (UStaticMeshComponent* Part : { Torso.Get(), Head.Get(), ArmLeft.Get(), ArmRight.Get(), LegLeft.Get(), LegRight.Get() })
	{
		Greybox::Tint(Part, Skin);
	}
	Greybox::Tint(HornLeft, Bone);
	Greybox::Tint(HornRight, Bone);

	if (UChaseSubsystem* Chase = GetWorld()->GetSubsystem<UChaseSubsystem>())
	{
		Chase->RegisterPursuer(this);
	}
	SetConcealed(true);
	EnterState(EPursuerState::Dormant);
}

// ---------------------------------------------------------------------------
// Control from the chase subsystem
// ---------------------------------------------------------------------------

void APursuerCharacter::Activate()
{
	SetConcealed(false);
	ResetTrail();
	EnterState(EPursuerState::Chasing);
	PlaySound(RoarSound);
}

void APursuerCharacter::ResetTo(const FTransform& Where)
{
	SetActorLocationAndRotation(Where.GetLocation(), FRotator(0.f, Where.Rotator().Yaw, 0.f), false, nullptr, ETeleportType::TeleportPhysics);
	SetConcealed(true);
	Trail.Reset();
	TrailIndex = 0;
	TrailGap = UE_BIG_NUMBER;
	BashTarget = nullptr;
	EnterState(EPursuerState::Dormant);
}

void APursuerCharacter::TryStun()
{
	if (State != EPursuerState::Chasing || StunCooldownLeft > 0.f)
	{
		return;
	}
	EnterState(EPursuerState::Stunned);
}

void APursuerCharacter::LosePlayer()
{
	if (State == EPursuerState::Chasing || State == EPursuerState::Bashing || State == EPursuerState::Stunned)
	{
		EnterState(EPursuerState::Lost);
	}
}

void APursuerCharacter::Reappear(const FTransform& Where)
{
	SetActorLocationAndRotation(Where.GetLocation(), FRotator(0.f, Where.Rotator().Yaw, 0.f), false, nullptr, ETeleportType::TeleportPhysics);
	ResumeChase();
}

void APursuerCharacter::ResumeChase()
{
	SetConcealed(false);
	ResetTrail();
	EnterState(EPursuerState::Chasing);
	PlaySound(RoarSound);
}

void APursuerCharacter::Retreat()
{
	if (bConcealed)
	{
		EnterState(EPursuerState::Dormant);
		return;
	}
	EnterState(EPursuerState::Retreating);
}

bool APursuerCharacter::IsActiveThreat() const
{
	if (bConcealed)
	{
		return false;
	}
	return State == EPursuerState::Chasing || State == EPursuerState::Bashing
		|| State == EPursuerState::Stunned || State == EPursuerState::Feeding;
}

// ---------------------------------------------------------------------------
// Tick
// ---------------------------------------------------------------------------

void APursuerCharacter::Tick(float DeltaTime)
{
	Super::Tick(DeltaTime);

	StateTime += DeltaTime;
	StunCooldownLeft = FMath::Max(0.f, StunCooldownLeft - DeltaTime);
	ARelentlessCharacter* Player = GetPlayer();

	switch (State)
	{
	case EPursuerState::Chasing:
		if (!Player || Player->IsDead())
		{
			break;
		}
		RecordTrail(Player);
		UpdateGap(Player);
		UpdateSpeed(Player);
		if (CheckCatch(Player) || CheckDoors())
		{
			break;
		}
		FollowTrail(Player, DeltaTime);
		break;

	case EPursuerState::Bashing:
		if (Player)
		{
			RecordTrail(Player);
			UpdateGap(Player);
		}
		if (AChaseDoor* Door = BashTarget.Get())
		{
			FVector ToDoor = Door->GetActorLocation() - GetActorLocation();
			SetActorRotation(FRotator(0.f, ToDoor.Rotation().Yaw, 0.f));
			if (StateTime >= NextBashHit)
			{
				NextBashHit += 0.6f;
				Door->Rattle();
				PlaySound(BashSound);
			}
			if (StateTime >= BashTime)
			{
				Door->Smash(GetActorForwardVector());
				PlaySound(RoarSound, 0.7f);
				EnterState(EPursuerState::Chasing);
			}
		}
		else
		{
			EnterState(EPursuerState::Chasing);
		}
		break;

	case EPursuerState::Stunned:
		if (Player)
		{
			RecordTrail(Player);
			UpdateGap(Player);
		}
		if (StateTime >= StunDuration)
		{
			EnterState(EPursuerState::Chasing);
		}
		break;

	case EPursuerState::Lost:
		if (!bConcealed && StateTime >= LostConcealDelay)
		{
			SetConcealed(true);
		}
		break;

	case EPursuerState::Retreating:
		if (Player)
		{
			AddMovementInput((GetActorLocation() - Player->GetActorLocation()).GetSafeNormal2D());
		}
		if (StateTime >= 1.5f)
		{
			SetConcealed(true);
			EnterState(EPursuerState::Dormant);
		}
		break;

	default:
		break;
	}

	if (!bConcealed)
	{
		Animate(DeltaTime);

		const float Speed = GetVelocity().Size2D();
		if (GetCharacterMovement()->IsMovingOnGround() && Speed > 50.f)
		{
			StepDistance += Speed * DeltaTime;
			if (StepDistance >= FootstepStride)
			{
				StepDistance = 0.f;
				PlaySound(FootstepSound);
			}
		}
	}
}

void APursuerCharacter::EnterState(EPursuerState NewState)
{
	State = NewState;
	StateTime = 0.f;
	StuckTime = 0.f;

	switch (NewState)
	{
	case EPursuerState::Stunned:
		StunCooldownLeft = StunCooldown;
		GetCharacterMovement()->StopMovementImmediately();
		PlaySound(ScreechSound);
		break;
	case EPursuerState::Bashing:
		NextBashHit = 0.3f;
		GetCharacterMovement()->StopMovementImmediately();
		break;
	case EPursuerState::Lost:
	case EPursuerState::Feeding:
		GetCharacterMovement()->StopMovementImmediately();
		break;
	default:
		break;
	}
}

void APursuerCharacter::SetConcealed(bool bConceal)
{
	bConcealed = bConceal;
	SetActorHiddenInGame(bConceal);
	SetActorEnableCollision(!bConceal);
	GetCharacterMovement()->StopMovementImmediately();
	GetCharacterMovement()->SetMovementMode(bConceal ? MOVE_None : MOVE_Walking);
}

// ---------------------------------------------------------------------------
// Trail following
// ---------------------------------------------------------------------------

void APursuerCharacter::ResetTrail()
{
	Trail.Reset();
	TrailIndex = 0;
	Trail.Add(GetFeetLocation());
}

void APursuerCharacter::RecordTrail(const ARelentlessCharacter* Player)
{
	const FVector Feet = Player->GetFeetLocation();
	if (Trail.Num() == 0 || FVector::DistSquared(Trail.Last(), Feet) > FMath::Square(CrumbSpacing))
	{
		Trail.Add(Feet);
	}
}

void APursuerCharacter::UpdateGap(const ARelentlessCharacter* Player)
{
	FVector Prev = GetFeetLocation();
	float Gap = 0.f;
	for (int32 i = TrailIndex; i < Trail.Num(); ++i)
	{
		Gap += FVector::Dist(Prev, Trail[i]);
		Prev = Trail[i];
	}
	Gap += FVector::Dist(Prev, Player->GetFeetLocation());
	TrailGap = Gap;
}

void APursuerCharacter::UpdateSpeed(const ARelentlessCharacter* Player)
{
	const float T = FMath::Clamp((TrailGap - IdealGap) / FMath::Max(FarGap - IdealGap, 1.f), 0.f, 1.f);
	float Scale = FMath::Lerp(NearSpeedScale, FarSpeedScale, T);
	if (Player->IsExhausted())
	{
		Scale *= ExhaustionMercy;
	}
	GetCharacterMovement()->MaxWalkSpeed = Player->GetSprintSpeed() * Scale;
}

bool APursuerCharacter::CheckCatch(ARelentlessCharacter* Player)
{
	if (FVector::Dist(GetActorLocation(), Player->GetActorLocation()) > KillDistance)
	{
		return false;
	}

	// No killing through a closed door.
	FCollisionQueryParams Params(SCENE_QUERY_STAT(PursuerCatch), false, this);
	Params.AddIgnoredActor(Player);
	FHitResult Hit;
	if (GetWorld()->LineTraceSingleByChannel(Hit, GetHeadLocation(), Player->GetEyeLocation(), ECC_Visibility, Params))
	{
		return false;
	}

	EnterState(EPursuerState::Feeding);
	PlaySound(RoarSound);
	Player->Caught(this);
	return true;
}

bool APursuerCharacter::CheckDoors()
{
	FVector Dir = GetVelocity().GetSafeNormal2D();
	if (Dir.IsNearlyZero() && Trail.IsValidIndex(TrailIndex))
	{
		Dir = (Trail[TrailIndex] - GetFeetLocation()).GetSafeNormal2D();
	}
	if (Dir.IsNearlyZero())
	{
		return false;
	}

	const FVector Start = GetActorLocation();
	const FVector End = Start + Dir * 130.f;
	FCollisionQueryParams Params(SCENE_QUERY_STAT(PursuerDoor), false, this);
	if (const ARelentlessCharacter* Player = GetPlayer())
	{
		Params.AddIgnoredActor(Player);
	}
	FHitResult Hit;
	if (GetWorld()->SweepSingleByChannel(Hit, Start, End, FQuat::Identity, ECC_Visibility, FCollisionShape::MakeSphere(45.f), Params))
	{
		AChaseDoor* Door = Cast<AChaseDoor>(Hit.GetActor());
		if (Door && Door->IsBlocking())
		{
			BashTarget = Door;
			EnterState(EPursuerState::Bashing);
			return true;
		}
	}
	return false;
}

void APursuerCharacter::FollowTrail(const ARelentlessCharacter* Player, float DeltaTime)
{
	const FVector Feet = GetFeetLocation();
	while (TrailIndex < Trail.Num() - 1 && FVector::Dist2D(Feet, Trail[TrailIndex]) < 90.f)
	{
		++TrailIndex;
	}

	FVector Target = Trail.IsValidIndex(TrailIndex) ? Trail[TrailIndex] : Player->GetFeetLocation();
	if (TrailIndex >= Trail.Num() - 1 && FVector::Dist2D(Feet, Target) < 90.f)
	{
		// End of the trail: go straight for them.
		Target = Player->GetFeetLocation();
	}

	AddMovementInput((Target - Feet).GetSafeNormal2D());

	if (Target.Z - Feet.Z > 50.f && GetCharacterMovement()->IsMovingOnGround())
	{
		Jump();
	}

	// If something snags it, skip ahead along the trail rather than standing there.
	if (GetVelocity().Size2D() < 40.f)
	{
		StuckTime += DeltaTime;
		if (StuckTime > 0.8f)
		{
			TrailIndex = FMath::Min(TrailIndex + 4, Trail.Num() - 1);
			StuckTime = 0.f;
		}
	}
	else
	{
		StuckTime = 0.f;
	}

	if (TrailIndex > 256)
	{
		Trail.RemoveAt(0, TrailIndex);
		TrailIndex = 0;
	}
}

// ---------------------------------------------------------------------------
// Procedural greybox animation
// ---------------------------------------------------------------------------

void APursuerCharacter::Animate(float DeltaTime)
{
	const float Speed = GetVelocity().Size2D();
	const float Swing = FMath::Clamp(Speed / 600.f, 0.f, 1.f);
	AnimPhase += DeltaTime * (Speed / 110.f + 0.6f);

	float LeftArm = FMath::Sin(AnimPhase) * 50.f * Swing;
	float RightArm = -LeftArm;
	float HeadRoll = 0.f;
	float EyeLumens = 60.f;

	switch (State)
	{
	case EPursuerState::Bashing:
		LeftArm = 120.f + FMath::Sin(StateTime * 10.f) * 45.f;
		RightArm = 120.f + FMath::Sin(StateTime * 10.f + PI) * 45.f;
		EyeLumens = 120.f;
		break;
	case EPursuerState::Stunned:
		// Shielding its face from the light.
		LeftArm = 150.f;
		RightArm = 140.f;
		HeadRoll = FMath::PerlinNoise1D(StateTime * 20.f) * 30.f;
		EyeLumens = 400.f;
		break;
	case EPursuerState::Feeding:
		LeftArm = RightArm = 85.f;
		EyeLumens = 250.f;
		break;
	case EPursuerState::Lost:
		LeftArm = 60.f + FMath::Sin(StateTime * 6.f) * 30.f;
		RightArm = 60.f + FMath::Sin(StateTime * 6.f + 1.f) * 30.f;
		HeadRoll = FMath::Sin(StateTime * 3.f) * 20.f;
		break;
	default:
		break;
	}

	ShoulderLeft->SetRelativeRotation(FRotator(LeftArm, 0.f, -8.f));
	ShoulderRight->SetRelativeRotation(FRotator(RightArm, 0.f, 8.f));
	LegLeft->SetRelativeRotation(FRotator(-FMath::Sin(AnimPhase) * 25.f * Swing, 0.f, 0.f));
	LegRight->SetRelativeRotation(FRotator(FMath::Sin(AnimPhase) * 25.f * Swing, 0.f, 0.f));
	Head->SetRelativeRotation(FRotator(0.f, 0.f, HeadRoll));
	BodyRoot->SetRelativeLocation(FVector(0.f, 0.f, FMath::Abs(FMath::Sin(AnimPhase)) * 8.f * Swing));
	EyeGlow->SetIntensity(FMath::FInterpTo(EyeGlow->Intensity, EyeLumens, DeltaTime, 8.f));
}

// ---------------------------------------------------------------------------

void APursuerCharacter::PlaySound(USoundBase* Sound, float Volume)
{
	if (Sound && !bConcealed)
	{
		UGameplayStatics::PlaySoundAtLocation(this, Sound, GetActorLocation(), Volume);
	}
}

FVector APursuerCharacter::GetFeetLocation() const
{
	return GetActorLocation() - FVector(0.f, 0.f, GetCapsuleComponent()->GetScaledCapsuleHalfHeight());
}

FVector APursuerCharacter::GetHeadLocation() const
{
	return Head->GetComponentLocation();
}

ARelentlessCharacter* APursuerCharacter::GetPlayer() const
{
	if (const UChaseSubsystem* Chase = GetWorld()->GetSubsystem<UChaseSubsystem>())
	{
		if (ARelentlessCharacter* Player = Chase->GetPlayer())
		{
			return Player;
		}
	}
	return Cast<ARelentlessCharacter>(UGameplayStatics::GetPlayerCharacter(this, 0));
}
