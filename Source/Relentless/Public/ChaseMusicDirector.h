#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "ChaseMusicDirector.generated.h"

class UAudioComponent;
class USoundBase;

USTRUCT(BlueprintType)
struct FMusicLayer
{
	GENERATED_BODY()

	// Should be a looping sound, all layers the same length and tempo.
	UPROPERTY(EditAnywhere, Category = "Music")
	TObjectPtr<USoundBase> Sound;

	// Danger at which this layer starts fading in, and is fully in.
	UPROPERTY(EditAnywhere, Category = "Music", meta = (ClampMin = 0, ClampMax = 1))
	float FadeInStart = 0.f;

	UPROPERTY(EditAnywhere, Category = "Music", meta = (ClampMin = 0, ClampMax = 1))
	float FadeInEnd = 0.3f;

	UPROPERTY(EditAnywhere, Category = "Music")
	float MaxVolume = 1.f;
};

// Adaptive score. Each layer fades in with the chase's danger value; the
// ambience drops away as it closes in, so silence means it's near.
UCLASS()
class RELENTLESS_API AChaseMusicDirector : public AActor
{
	GENERATED_BODY()

public:
	AChaseMusicDirector();
	virtual void Tick(float DeltaTime) override;

	// e.g. drone (0-0.2), percussion (0.2-0.5), strings (0.4-0.7), choir (0.7-0.95)
	UPROPERTY(EditAnywhere, Category = "Music")
	TArray<FMusicLayer> Layers;

	UPROPERTY(EditAnywhere, Category = "Music")
	TObjectPtr<USoundBase> Ambience;

	UPROPERTY(EditAnywhere, Category = "Music")
	TObjectPtr<USoundBase> Heartbeat;

protected:
	virtual void BeginPlay() override;

private:
	UAudioComponent* StartLoop(USoundBase* Sound);

	UPROPERTY(Transient)
	TArray<TObjectPtr<UAudioComponent>> LayerComponents;

	UPROPERTY(Transient)
	TObjectPtr<UAudioComponent> AmbienceComponent;

	UPROPERTY(Transient)
	TObjectPtr<UAudioComponent> HeartbeatComponent;
};
