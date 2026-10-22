#include "ChaseMusicDirector.h"
#include "ChaseSubsystem.h"
#include "Components/AudioComponent.h"
#include "Kismet/GameplayStatics.h"

AChaseMusicDirector::AChaseMusicDirector()
{
	PrimaryActorTick.bCanEverTick = true;
	SetRootComponent(CreateDefaultSubobject<USceneComponent>(TEXT("Root")));
}

void AChaseMusicDirector::BeginPlay()
{
	Super::BeginPlay();

	for (const FMusicLayer& Layer : Layers)
	{
		LayerComponents.Add(StartLoop(Layer.Sound));
	}
	AmbienceComponent = StartLoop(Ambience);
	HeartbeatComponent = StartLoop(Heartbeat);
	if (AmbienceComponent)
	{
		AmbienceComponent->SetVolumeMultiplier(1.f);
	}
}

UAudioComponent* AChaseMusicDirector::StartLoop(USoundBase* Sound)
{
	if (!Sound)
	{
		return nullptr;
	}
	UAudioComponent* Comp = UGameplayStatics::CreateSound2D(this, Sound, 1.f, 1.f, 0.f, nullptr, false, false);
	if (Comp)
	{
		Comp->SetVolumeMultiplier(0.001f);
		Comp->Play();
	}
	return Comp;
}

void AChaseMusicDirector::Tick(float DeltaTime)
{
	Super::Tick(DeltaTime);

	const UChaseSubsystem* Chase = GetWorld()->GetSubsystem<UChaseSubsystem>();
	const float Danger = Chase ? Chase->GetDanger() : 0.f;

	for (int32 i = 0; i < Layers.Num() && i < LayerComponents.Num(); ++i)
	{
		if (UAudioComponent* Comp = LayerComponents[i])
		{
			const FMusicLayer& Layer = Layers[i];
			const float Range = FMath::Max(Layer.FadeInEnd - Layer.FadeInStart, 0.01f);
			const float T = FMath::Clamp((Danger - Layer.FadeInStart) / Range, 0.f, 1.f);
			Comp->SetVolumeMultiplier(FMath::Max(0.001f, FMath::SmoothStep(0.f, 1.f, T) * Layer.MaxVolume));
		}
	}
	if (AmbienceComponent)
	{
		AmbienceComponent->SetVolumeMultiplier(FMath::Max(0.001f, 1.f - Danger * 0.95f));
	}
	if (HeartbeatComponent)
	{
		HeartbeatComponent->SetVolumeMultiplier(FMath::Max(0.001f, (Danger - 0.3f) / 0.7f));
		HeartbeatComponent->SetPitchMultiplier(FMath::Lerp(0.9f, 1.5f, Danger));
	}
}
