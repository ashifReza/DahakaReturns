#include "ChaseDoor.h"
#include "ChaseSubsystem.h"
#include "GreyboxUtils.h"
#include "RelentlessCharacter.h"
#include "Components/StaticMeshComponent.h"
#include "Engine/CollisionProfile.h"
#include "Kismet/GameplayStatics.h"
#include "UObject/ConstructorHelpers.h"

#define LOCTEXT_NAMESPACE "ChaseDoor"

AChaseDoor::AChaseDoor()
{
	PrimaryActorTick.bCanEverTick = true;

	Root = CreateDefaultSubobject<USceneComponent>(TEXT("Root"));
	SetRootComponent(Root);

	Hinge = CreateDefaultSubobject<USceneComponent>(TEXT("Hinge"));
	Hinge->SetupAttachment(Root);

	static ConstructorHelpers::FObjectFinder<UStaticMesh> Cube(Greybox::CubePath);
	Panel = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("Panel"));
	Panel->SetupAttachment(Hinge);
	Panel->SetStaticMesh(Cube.Object);
	Panel->SetCollisionProfileName(UCollisionProfile::BlockAll_ProfileName);

	LayoutPanel();
}

void AChaseDoor::OnConstruction(const FTransform& Transform)
{
	Super::OnConstruction(Transform);
	LayoutPanel();
	CurrentYaw = (bStartsOpen && !bHeavy) ? OpenYaw : 0.f;
	Hinge->SetRelativeRotation(FRotator(0.f, CurrentYaw, 0.f));
}

void AChaseDoor::BeginPlay()
{
	Super::BeginPlay();
	Greybox::Tint(Panel, Color);
	ResetDoor();

	if (UChaseSubsystem* Chase = GetWorld()->GetSubsystem<UChaseSubsystem>())
	{
		Chase->OnChaseReset.AddUObject(this, &AChaseDoor::ResetDoor);
	}
}

void AChaseDoor::LayoutPanel()
{
	// The actor sits at the bottom-centre of the doorway; the hinge is on its -X edge.
	Hinge->SetRelativeLocation(FVector(-Width * 0.5f, 0.f, 0.f));
	Panel->SetRelativeLocation(FVector(Width * 0.5f, 0.f, Height * 0.5f));
	Panel->SetRelativeRotation(FRotator::ZeroRotator);
	Panel->SetRelativeScale3D(FVector(Width / 100.f, Thickness / 100.f, Height / 100.f));
}

void AChaseDoor::ResetDoor()
{
	if (Panel->IsSimulatingPhysics())
	{
		Panel->SetSimulatePhysics(false);
	}
	Panel->AttachToComponent(Hinge, FAttachmentTransformRules::SnapToTargetNotIncludingScale);
	Panel->SetCollisionResponseToAllChannels(ECR_Block);
	Panel->SetVisibility(true);
	LayoutPanel();

	Holder = nullptr;
	HoldProgress = 0.f;
	RattleTime = 0.f;
	State = (bStartsOpen && !bHeavy) ? EChaseDoorState::Open : EChaseDoorState::Closed;
	CurrentYaw = TargetYaw = (State == EChaseDoorState::Open) ? OpenYaw : 0.f;
	Hinge->SetRelativeRotation(FRotator(0.f, CurrentYaw, 0.f));
}

void AChaseDoor::Tick(float DeltaTime)
{
	Super::Tick(DeltaTime);

	if (State == EChaseDoorState::Broken)
	{
		return;
	}

	// Forcing a heavy door open.
	if (ARelentlessCharacter* Player = Holder.Get())
	{
		if (Player->IsDead() || FVector::Dist(Player->GetActorLocation(), GetActorLocation()) > 350.f)
		{
			Holder = nullptr;
		}
		else
		{
			HoldProgress += DeltaTime / FMath::Max(HoldTime, 0.1f);
			RattleTime = FMath::Max(RattleTime, 0.1f);
			if (HoldProgress >= 1.f)
			{
				Holder = nullptr;
				HoldProgress = 0.f;
				SetDoorState(EChaseDoorState::Open, 3.f);
				if (CreakSound)
				{
					UGameplayStatics::PlaySoundAtLocation(this, CreakSound, GetActorLocation());
				}
			}
		}
	}
	else
	{
		HoldProgress = FMath::Max(0.f, HoldProgress - DeltaTime * 0.5f);
	}

	CurrentYaw = FMath::FInterpTo(CurrentYaw, TargetYaw, DeltaTime, SwingSpeed);
	float Shake = 0.f;
	if (RattleTime > 0.f)
	{
		RattleTime -= DeltaTime;
		Shake = FMath::Sin(GetWorld()->GetTimeSeconds() * 70.f) * 1.5f;
	}
	// Show a crack opening while it's being forced.
	const float Strain = HoldProgress * 6.f;
	Hinge->SetRelativeRotation(FRotator(0.f, CurrentYaw + Shake + Strain, 0.f));
}

void AChaseDoor::SetDoorState(EChaseDoorState NewState, float Speed)
{
	State = NewState;
	SwingSpeed = Speed;
	TargetYaw = (NewState == EChaseDoorState::Open) ? OpenYaw : 0.f;
}

bool AChaseDoor::CanInteract() const
{
	if (State == EChaseDoorState::Broken)
	{
		return false;
	}
	return !(bHeavy && State == EChaseDoorState::Open);
}

FText AChaseDoor::GetInteractPrompt() const
{
	if (!CanInteract())
	{
		return FText::GetEmpty();
	}
	if (bHeavy)
	{
		return LOCTEXT("ForceOpen", "Hold [E] to force the door");
	}
	return State == EChaseDoorState::Open ? LOCTEXT("Slam", "[E] Slam the door") : LOCTEXT("Open", "[E] Open");
}

void AChaseDoor::BeginInteract(ARelentlessCharacter* By)
{
	if (!CanInteract())
	{
		return;
	}
	if (bHeavy)
	{
		Holder = By;
		return;
	}
	if (State == EChaseDoorState::Open)
	{
		SetDoorState(EChaseDoorState::Closed, 18.f);
		if (SlamSound)
		{
			UGameplayStatics::PlaySoundAtLocation(this, SlamSound, GetActorLocation());
		}
	}
	else
	{
		SetDoorState(EChaseDoorState::Open, 5.f);
	}
}

void AChaseDoor::EndInteract(ARelentlessCharacter* By)
{
	if (Holder.Get() == By)
	{
		Holder = nullptr;
	}
}

float AChaseDoor::GetInteractProgress() const
{
	return (bHeavy && State == EChaseDoorState::Closed && Holder.IsValid()) ? HoldProgress : -1.f;
}

bool AChaseDoor::IsBlocking() const
{
	return State == EChaseDoorState::Closed && FMath::Abs(CurrentYaw) < 45.f;
}

void AChaseDoor::Rattle()
{
	RattleTime = 0.35f;
}

void AChaseDoor::Smash(const FVector& Direction)
{
	if (State == EChaseDoorState::Broken)
	{
		return;
	}
	State = EChaseDoorState::Broken;
	Holder = nullptr;

	// Wreckage flies but no longer blocks anyone.
	Panel->SetCollisionResponseToAllChannels(ECR_Block);
	Panel->SetCollisionResponseToChannel(ECC_Pawn, ECR_Ignore);
	Panel->SetCollisionResponseToChannel(ECC_Visibility, ECR_Ignore);
	Panel->SetCollisionResponseToChannel(ECC_Camera, ECR_Ignore);
	Panel->SetSimulatePhysics(true);
	Panel->AddImpulse(Direction.GetSafeNormal() * 900.f + FVector(0.f, 0.f, 150.f), NAME_None, true);
	Panel->AddAngularImpulseInDegrees(FVector(FMath::FRandRange(-200.f, 200.f), FMath::FRandRange(-200.f, 200.f), 0.f), NAME_None, true);

	if (BreakSound)
	{
		UGameplayStatics::PlaySoundAtLocation(this, BreakSound, GetActorLocation());
	}
}

#undef LOCTEXT_NAMESPACE
