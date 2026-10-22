#include "FlickerLight.h"
#include "ChaseSubsystem.h"
#include "GreyboxUtils.h"
#include "PursuerCharacter.h"
#include "Components/PointLightComponent.h"
#include "Components/StaticMeshComponent.h"
#include "UObject/ConstructorHelpers.h"

AFlickerLight::AFlickerLight()
{
	PrimaryActorTick.bCanEverTick = true;

	Light = CreateDefaultSubobject<UPointLightComponent>(TEXT("Light"));
	SetRootComponent(Light);
	Light->IntensityUnits = ELightUnits::Lumens;
	Light->SetCastShadows(true);

	static ConstructorHelpers::FObjectFinder<UStaticMesh> Cube(Greybox::CubePath);
	Fixture = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("Fixture"));
	Fixture->SetupAttachment(Light);
	Fixture->SetStaticMesh(Cube.Object);
	Fixture->SetRelativeLocation(FVector(0.f, 0.f, 12.f));
	Fixture->SetRelativeScale3D(FVector(0.8f, 0.12f, 0.05f));
	Fixture->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	Fixture->SetCastShadow(false);
}

void AFlickerLight::OnConstruction(const FTransform& Transform)
{
	Super::OnConstruction(Transform);
	ApplySettings();
}

void AFlickerLight::BeginPlay()
{
	Super::BeginPlay();
	ApplySettings();
	Seed = FMath::FRandRange(0.f, 1000.f);
}

void AFlickerLight::ApplySettings()
{
	Light->SetIntensity(Lumens);
	Light->SetLightColor(LightColor);
	Light->SetAttenuationRadius(Radius);
}

void AFlickerLight::Tick(float DeltaTime)
{
	Super::Tick(DeltaTime);

	const float Time = GetWorld()->GetTimeSeconds() + Seed;
	float Target = 1.f;

	// Random sputters: mostly on, occasionally drops out.
	const float Noise = FMath::PerlinNoise1D(Time * 6.f) * 0.5f + 0.5f;
	if (Noise > 1.f - Faultiness * 0.5f)
	{
		Target = 0.05f;
	}

	const UChaseSubsystem* Chase = GetWorld()->GetSubsystem<UChaseSubsystem>();
	const APursuerCharacter* Pursuer = Chase ? Chase->GetPursuer() : nullptr;
	if (Pursuer && Pursuer->IsActiveThreat())
	{
		const float Dist = FVector::Dist(Pursuer->GetActorLocation(), GetActorLocation());
		if (Dist < DarkenRadius)
		{
			Target = 0.f;
		}
		else if (Dist < DarkenRadius * 1.6f)
		{
			// Struggling as it approaches.
			Target *= (FMath::PerlinNoise1D(Time * 25.f) > 0.f) ? 1.f : 0.1f;
		}
	}

	Level = FMath::FInterpTo(Level, Target, DeltaTime, 30.f);
	Light->SetIntensity(Lumens * Level);
}
