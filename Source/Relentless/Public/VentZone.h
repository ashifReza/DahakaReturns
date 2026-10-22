#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "VentZone.generated.h"

class UBoxComponent;

// A crawlspace. Inside it the player is forced to crouch and the pursuer is too
// big to follow; it gives up, vanishes, and ambushes from AmbushPoint when the
// player crawls out the far end.
UCLASS()
class RELENTLESS_API AVentZone : public AActor
{
	GENERATED_BODY()

public:
	AVentZone();

	FTransform GetAmbushWorld() const { return AmbushPoint * GetActorTransform(); }

	UPROPERTY(EditAnywhere, Category = "Vent", meta = (MakeEditWidget = true))
	FTransform AmbushPoint = FTransform(FVector(-1000.f, 300.f, 50.f));

	UPROPERTY(EditAnywhere, Category = "Vent")
	float AmbushDelay = 1.2f;

protected:
	UPROPERTY(VisibleAnywhere, Category = "Vent")
	TObjectPtr<UBoxComponent> Box;

	UFUNCTION()
	void OnBeginOverlap(UPrimitiveComponent* OverlappedComponent, AActor* OtherActor, UPrimitiveComponent* OtherComp, int32 OtherBodyIndex, bool bFromSweep, const FHitResult& SweepResult);

	UFUNCTION()
	void OnEndOverlap(UPrimitiveComponent* OverlappedComponent, AActor* OtherActor, UPrimitiveComponent* OtherComp, int32 OtherBodyIndex);
};
