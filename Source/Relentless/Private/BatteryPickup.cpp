#include "BatteryPickup.h"
#include "GreyboxUtils.h"
#include "RelentlessCharacter.h"
#include "Components/PointLightComponent.h"
#include "Components/SphereComponent.h"
#include "Components/StaticMeshComponent.h"
#include "Kismet/GameplayStatics.h"
#include "UObject/ConstructorHelpers.h"

ABatteryPickup::ABatteryPickup()
{
	PrimaryActorTick.bCanEverTick = true;

	Sphere = CreateDefaultSubobject<USphereComponent>(TEXT("Sphere"));
	SetRootComponent(Sphere);
	Sphere->InitSphereRadius(80.f);
	Sphere->SetCollisionProfileName(TEXT("Trigger"));
	Sphere->OnComponentBeginOverlap.AddDynamic(this, &ABatteryPickup::OnOverlap);

	static ConstructorHelpers::FObjectFinder<UStaticMesh> Cylinder(Greybox::CylinderPath);
	Mesh = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("Mesh"));
	Mesh->SetupAttachment(Sphere);
	Mesh->SetStaticMesh(Cylinder.Object);
	Mesh->SetRelativeScale3D(FVector(0.12f, 0.12f, 0.25f));
	Mesh->SetCollisionEnabled(ECollisionEnabled::NoCollision);

	// A faint glow so it can be spotted in the dark.
	Glow = CreateDefaultSubobject<UPointLightComponent>(TEXT("Glow"));
	Glow->SetupAttachment(Sphere);
	Glow->IntensityUnits = ELightUnits::Lumens;
	Glow->Intensity = 8.f;
	Glow->AttenuationRadius = 120.f;
	Glow->LightColor = FColor(120, 255, 140);
	Glow->SetCastShadows(false);
}

void ABatteryPickup::BeginPlay()
{
	Super::BeginPlay();
	Greybox::Tint(Mesh, FLinearColor(0.1f, 0.5f, 0.15f));
}

void ABatteryPickup::Tick(float DeltaTime)
{
	Super::Tick(DeltaTime);
	Mesh->AddLocalRotation(FRotator(0.f, 60.f * DeltaTime, 0.f));
	Glow->SetIntensity(8.f + FMath::Sin(GetWorld()->GetTimeSeconds() * 3.f) * 4.f);
}

void ABatteryPickup::OnOverlap(UPrimitiveComponent* OverlappedComponent, AActor* OtherActor, UPrimitiveComponent* OtherComp, int32 OtherBodyIndex, bool bFromSweep, const FHitResult& SweepResult)
{
	if (ARelentlessCharacter* Player = Cast<ARelentlessCharacter>(OtherActor))
	{
		Player->AddBattery(Amount);
		if (PickupSound)
		{
			UGameplayStatics::PlaySoundAtLocation(this, PickupSound, GetActorLocation());
		}
		Destroy();
	}
}
